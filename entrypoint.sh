#!/bin/bash
set -e

echo "========================================"
echo "Mail Server Initialization"
echo "========================================"
echo "Domain: ${DOMAIN}"
echo "Hostname: ${HOSTNAME}"
echo "Postmaster: ${POSTMASTER_ADDRESS}"
echo "========================================"

# Wait for database to be ready (with timeout)
echo "Waiting for MySQL database to be ready..."
for i in {1..60}; do
    if mysqladmin ping -h"database" -u"root" -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
        echo "✓ Database is ready!"
        break
    else
        if [ $i -eq 60 ]; then
            echo "✗ Database connection failed after 60 seconds"
            echo "Trying to continue anyway..."
        else
            echo "Database not ready yet (attempt $i/60)..."
            sleep 1
        fi
    fi
done

# Update Postfix configuration with environment variables
if [ -f /etc/postfix/main.cf ]; then
    echo "Updating Postfix configuration..."
    sed -i "s/{{DOMAIN}}/${DOMAIN}/g" /etc/postfix/main.cf
    sed -i "s/{{HOSTNAME}}/${HOSTNAME}/g" /etc/postfix/main.cf
    echo "✓ Postfix configuration updated"
fi

# Update Dovecot configuration
if [ -f /etc/dovecot/dovecot.conf ]; then
    echo "Updating Dovecot configuration..."
    sed -i "s/{{DOMAIN}}/${DOMAIN}/g" /etc/dovecot/dovecot.conf
    sed -i "s/{{HOSTNAME}}/${HOSTNAME}/g" /etc/dovecot/dovecot.conf
    echo "✓ Dovecot configuration updated"
fi

# Create MySQL configuration files for Postfix
echo "Creating Postfix MySQL configuration files..."

# virtual_domains.cf
cat > /etc/postfix/mysql-virtual-domains.cf << EOF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s' AND active=1
EOF

# virtual_mailbox_maps.cf
cat > /etc/postfix/mysql-virtual-mailbox-maps.cf << EOF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s' AND active=1
EOF

# virtual_alias_maps.cf
cat > /etc/postfix/mysql-virtual-alias-maps.cf << EOF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s' AND active=1
EOF

# virtual_mailboxes.cf
cat > /etc/postfix/mysql-virtual-mailboxes.cf << EOF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT CONCAT(SUBSTRING_INDEX(email,'@',-1),'/',SUBSTRING_INDEX(email,'@',1),'/') FROM virtual_users WHERE email='%s'
EOF

echo "✓ Postfix MySQL configuration files created"

# Create Dovecot SQL configuration
echo "Creating Dovecot SQL configuration..."
cat > /etc/dovecot/dovecot-sql.conf.ext << EOF
driver = mysql
connect = host=database dbname=mailserver user=mailuser password=${MYSQL_PASSWORD}
default_pass_scheme = PLAIN

password_query = \\
  SELECT email as user, password FROM virtual_users WHERE email='%u' AND active=1

user_query = \\
  SELECT '/var/mail/vhosts/%d/%n' as home, 'maildir:/var/mail/vhosts/%d/%n' as mail, \\
  5000 AS uid, 5000 AS gid FROM virtual_users WHERE email='%u'

iterate_query = SELECT email as user FROM virtual_users
EOF

chmod 600 /etc/dovecot/dovecot-sql.conf.ext
echo "✓ Dovecot SQL configuration created"

# Initialize database if tables don't exist
echo "Checking database schema..."
DB_EXISTS=$(mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES LIKE 'mailserver';" | grep -c mailserver || true)

if [ "$DB_EXISTS" -eq 1 ]; then
    echo "Database 'mailserver' exists"
    
    # Check if tables exist
    TABLE_COUNT=$(mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} mailserver -e "SHOW TABLES;" | wc -l)
    
    if [ "$TABLE_COUNT" -lt 4 ]; then
        echo "Initializing database schema..."
        if [ -f /docker-entrypoint-initdb.d/init.sql ]; then
            mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} mailserver < /docker-entrypoint-initdb.d/init.sql
            echo "✓ Database schema initialized"
        else
            echo "⚠ init.sql file not found"
        fi
    else
        echo "✓ Database tables already exist"
    fi
else
    echo "Creating database..."
    mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS mailserver;"
    
    if [ -f /docker-entrypoint-initdb.d/init.sql ]; then
        mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} mailserver < /docker-entrypoint-initdb.d/init.sql
        echo "✓ Database created and initialized"
    fi
fi

# Create vmail directory structure
echo "Creating mail directory structure..."
mkdir -p /var/mail/vhosts/${DOMAIN}
chown -R vmail:vmail /var/mail
chmod -R 770 /var/mail
echo "✓ Mail directories created"

# Generate Dovecot SSL certificates if not exist
if [ ! -f /etc/dovecot/ssl/dovecot.pem ] || [ ! -f /etc/dovecot/ssl/dovecot.key ]; then
    echo "Generating Dovecot SSL certificates..."
    mkdir -p /etc/dovecot/ssl
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/dovecot/ssl/dovecot.key \
        -out /etc/dovecot/ssl/dovecot.pem \
        -subj "/C=BD/ST=Dhaka/L=Dhaka/O=Syscomatic/CN=${HOSTNAME}"
    chmod 600 /etc/dovecot/ssl/dovecot.key
    chown dovecot:dovecot /etc/dovecot/ssl/dovecot.key
    echo "✓ Dovecot SSL certificates generated"
fi

# Set Postfix permissions
chown -R postfix:postfix /etc/postfix
chmod -R 750 /etc/postfix

# Create Postfix lookup tables
echo "Creating Postfix lookup tables..."
postmap /etc/postfix/mysql-virtual-domains.cf 2>/dev/null || true
postmap /etc/postfix/mysql-virtual-mailbox-maps.cf 2>/dev/null || true
postmap /etc/postfix/mysql-virtual-alias-maps.cf 2>/dev/null || true
postmap /etc/postfix/mysql-virtual-mailboxes.cf 2>/dev/null || true
echo "✓ Postfix lookup tables created"

# Create auth socket directory
mkdir -p /var/spool/postfix/private
chown postfix:postfix /var/spool/postfix/private
chmod 750 /var/spool/postfix/private

# Test MySQL connection
echo "Testing MySQL connection for mail services..."
if mysql -h database -u mailuser -p${MYSQL_PASSWORD} mailserver -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✓ MySQL connection successful"
    
    # Check if admin user exists
    ADMIN_EXISTS=$(mysql -h database -u mailuser -p${MYSQL_PASSWORD} mailserver -e "SELECT COUNT(*) FROM virtual_users WHERE email='${POSTMASTER_ADDRESS}';" | tail -1)
    
    if [ "$ADMIN_EXISTS" -eq 0 ]; then
        echo "Creating admin user: ${POSTMASTER_ADDRESS}"
        DOMAIN_ID=$(mysql -h database -u mailuser -p${MYSQL_PASSWORD} mailserver -e "SELECT id FROM virtual_domains WHERE name='${DOMAIN}';" | tail -1)
        
        if [ -n "$DOMAIN_ID" ] && [ "$DOMAIN_ID" -gt 0 ]; then
            mysql -h database -u mailuser -p${MYSQL_PASSWORD} mailserver -e \
                "INSERT INTO virtual_users (domain_id, email, password) VALUES (${DOMAIN_ID}, '${POSTMASTER_ADDRESS}', '{PLAIN}${POSTMASTER_PASSWORD}');"
            echo "✓ Admin user created"
        fi
    else
        echo "✓ Admin user already exists"
    fi
else
    echo "⚠ MySQL connection test failed"
fi

# Set up log directory
mkdir -p /var/log/mail
chown -R syslog:adm /var/log/mail
chmod -R 750 /var/log/mail

echo "========================================"
echo "Starting Mail Services"
echo "========================================"

# Start services via supervisor
exec supervisord -n -c /etc/supervisor/supervisord.conf