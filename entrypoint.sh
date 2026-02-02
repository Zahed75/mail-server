#!/bin/bash
set -e

echo "========================================"
echo "Mail Server Initialization"
echo "========================================"
echo "Domain: ${DOMAIN}"
echo "Hostname: ${HOSTNAME}"
echo "Postmaster: ${POSTMASTER_ADDRESS}"
echo "========================================"

# Wait for database to be ready
echo "Waiting for MySQL database to be ready..."
for i in {1..60}; do
    if mysqladmin ping -h"database" -u"root" -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
        echo "✓ Database is ready!"
        break
    else
        if [ $i -eq 60 ]; then
            echo "✗ Database connection failed after 60 seconds"
            exit 1
        else
            echo "Database not ready yet (attempt $i/60)..."
            sleep 1
        fi
    fi
done

# Update configurations WITHOUT using -i flag (causes issues with read-only mounts)
echo "Updating configurations..."

# Use temp files for sed operations
if [ -f /etc/postfix/main.cf ]; then
    cp /etc/postfix/main.cf /tmp/main.cf
    sed "s/{{DOMAIN}}/${DOMAIN}/g" /tmp/main.cf > /tmp/main2.cf
    sed "s/{{HOSTNAME}}/${HOSTNAME}/g" /tmp/main2.cf > /etc/postfix/main.cf
    rm -f /tmp/main.cf /tmp/main2.cf
    echo "✓ Postfix configuration updated"
fi

if [ -f /etc/dovecot/dovecot.conf ]; then
    cp /etc/dovecot/dovecot.conf /tmp/dovecot.conf
    sed "s/{{DOMAIN}}/${DOMAIN}/g" /tmp/dovecot.conf > /etc/dovecot/dovecot.conf
    rm -f /tmp/dovecot.conf
    echo "✓ Dovecot configuration updated"
fi

# Create MySQL configs
echo "Creating MySQL configuration files..."

cat > /etc/postfix/mysql-virtual-domains.cf << EOF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s' AND active=1
EOF

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf << EOF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s' AND active=1
EOF

cat > /etc/postfix/mysql-virtual-alias-maps.cf << EOF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s' AND active=1
EOF

echo "✓ MySQL configuration files created"

# Initialize database
echo "Initializing database..."
sleep 5  # Give MySQL more time
mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS mailserver;" 2>/dev/null || true

if [ -f /docker-entrypoint-initdb.d/init.sql ]; then
    mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} mailserver < /docker-entrypoint-initdb.d/init.sql 2>/dev/null || true
    echo "✓ Database initialized"
fi

# Create directories
mkdir -p /var/mail/vhosts/${DOMAIN}
chown -R vmail:vmail /var/mail
chmod -R 770 /var/mail

# Generate SSL if needed
if [ ! -f /etc/dovecot/ssl/dovecot.pem ]; then
    echo "Generating SSL certificates..."
    mkdir -p /etc/dovecot/ssl
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/dovecot/ssl/dovecot.key \
        -out /etc/dovecot/ssl/dovecot.pem \
        -subj "/C=BD/ST=Dhaka/L=Dhaka/O=Syscomatic/CN=${HOSTNAME}"
    chmod 600 /etc/dovecot/ssl/dovecot.key
fi

echo "========================================"
echo "Starting Mail Services"
echo "========================================"

# Start services
exec supervisord -n -c /etc/supervisor/supervisord.conf