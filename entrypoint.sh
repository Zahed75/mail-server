#!/bin/bash
set -e

echo "Starting mail server for ${DOMAIN}..."

# Update configurations with environment variables
if [ -f /etc/postfix/main.cf ]; then
    sed -i "s/{{DOMAIN}}/${DOMAIN}/g" /etc/postfix/main.cf
    sed -i "s/{{HOSTNAME}}/${HOSTNAME}/g" /etc/postfix/main.cf
fi

if [ -f /etc/dovecot/dovecot.conf ]; then
    sed -i "s/{{DOMAIN}}/${DOMAIN}/g" /etc/dovecot/dovecot.conf
fi

# Generate self-signed SSL if not provided
if [ ! -f /etc/ssl/mail/mail.crt ] && [ ! -f /etc/ssl/mail/mail.key ]; then
    echo "Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/ssl/mail/mail.key \
        -out /etc/ssl/mail/mail.crt \
        -subj "/C=BD/ST=Dhaka/L=Dhaka/O=Syscomatic/CN=${HOSTNAME}"
    chmod 600 /etc/ssl/mail/mail.key
fi

# Start services
echo "Starting Postfix and Dovecot..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf