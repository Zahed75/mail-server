#!/bin/bash
set -e

echo "========================================"
echo "Starting Mail Server for ${DOMAIN}"
echo "Hostname: ${HOSTNAME}"
echo "========================================"

# Wait for database to be ready
echo "Waiting for database..."
while ! mysqladmin ping -h"database" -u"root" -p"${MYSQL_ROOT_PASSWORD}" --silent; do
    sleep 1
done

echo "Database is ready!"

# Update configurations with environment variables
if [ -f /etc/postfix/main.cf ]; then
    sed -i "s/{{DOMAIN}}/${DOMAIN}/g" /etc/postfix/main.cf
    sed -i "s/{{HOSTNAME}}/${HOSTNAME}/g" /etc/postfix/main.cf
    echo "Postfix configuration updated"
fi

if [ -f /etc/dovecot/dovecot.conf ]; then
    sed -i "s/{{DOMAIN}}/${DOMAIN}/g" /etc/dovecot/dovecot.conf
    echo "Dovecot configuration updated"
fi

# Set MySQL credentials in Dovecot SQL config
if [ -f /etc/dovecot/dovecot-sql.conf.ext ]; then
    sed -i "s/{{MYSQL_PASSWORD}}/${MYSQL_PASSWORD}/g" /etc/dovecot/dovecot-sql.conf.ext
fi

# Initialize database if needed
echo "Initializing database..."
mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS mailserver;"
mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} mailserver < /docker-entrypoint-initdb.d/init.sql 2>/dev/null || true

# Create vmail directory structure
mkdir -p /var/mail/vhosts/${DOMAIN}
chown -R vmail:vmail /var/mail

# Generate SSL if using self-signed
if [ ! -f /etc/dovecot/ssl/dovecot.key ]; then
    echo "Generating Dovecot SSL certificates..."
    mkdir -p /etc/dovecot/ssl
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/dovecot/ssl/dovecot.key \
        -out /etc/dovecot/ssl/dovecot.pem \
        -subj "/C=BD/ST=Dhaka/L=Dhaka/O=Syscomatic/CN=${HOSTNAME}"
    chmod 600 /etc/dovecot/ssl/dovecot.key
fi

# Start services
echo "========================================"
echo "Starting Postfix and Dovecot..."
echo "========================================"
exec supervisord -n -c /etc/supervisor/supervisord.conf