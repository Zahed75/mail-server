#!/bin/bash
set -e

echo "========================================"
echo "Mail Server Starting"
echo "========================================"
echo "Domain: system.syscomatic.com"
echo "Hostname: mail.system.syscomatic.com"
echo "========================================"

# Wait for database
echo "Waiting for MySQL database..."
for i in {1..60}; do
    if mysqladmin ping -h"database" -u"root" -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
        echo "✓ Database is ready!"
        break
    else
        if [ $i -eq 60 ]; then
            echo "✗ Database timeout"
        else
            sleep 1
        fi
    fi
done

# Create MySQL config files
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

# Create Dovecot SQL config
cat > /etc/dovecot/dovecot-sql.conf.ext << EOF
driver = mysql
connect = host=database dbname=mailserver user=mailuser password=${MYSQL_PASSWORD}
default_pass_scheme = PLAIN

password_query = SELECT email as user, password FROM virtual_users WHERE email='%u' AND active=1
user_query = SELECT '/var/mail/vhosts/%d/%n' as home, 'maildir:/var/mail/vhosts/%d/%n' as mail, 5000 AS uid, 5000 AS gid FROM virtual_users WHERE email='%u'
EOF

chmod 600 /etc/dovecot/dovecot-sql.conf.ext

# Initialize database if needed
echo "Initializing database..."
mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS mailserver;" 2>/dev/null || true

if [ -f /docker-entrypoint-initdb.d/init.sql ]; then
    mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} mailserver < /docker-entrypoint-initdb.d/init.sql 2>/dev/null || true
fi

# Create directories
mkdir -p /var/mail/vhosts/system.syscomatic.com
chown -R vmail:vmail /var/mail

echo "========================================"
echo "Starting services..."
echo "========================================"

exec supervisord -n -c /etc/supervisor/supervisord.conf