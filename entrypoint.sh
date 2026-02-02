#!/bin/bash
set -e

echo "========================================"
echo "Mail Server Starting"
echo "========================================"
echo "Domain: system.syscomatic.com"
echo "Hostname: mail.system.syscomatic.com"
echo "========================================"

# Wait for database
for i in {1..60}; do
    if mysqladmin ping -h"database" -u"root" -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
        echo "✓ Database ready"
        break
    else
        sleep 1
    fi
done

# Create MySQL configs
cat > /etc/postfix/mysql-virtual-domains.cf << MYSQLCF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s' AND active=1
MYSQLCF

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf << MYSQLCF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s' AND active=1
MYSQLCF

cat > /etc/postfix/mysql-virtual-alias-maps.cf << MYSQLCF
user = mailuser
password = ${MYSQL_PASSWORD}
hosts = database
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s' AND active=1
MYSQLCF

# Dovecot SQL config
cat > /etc/dovecot/dovecot-sql.conf.ext << DOVECOTSQL
driver = mysql
connect = host=database dbname=mailserver user=mailuser password=${MYSQL_PASSWORD}
default_pass_scheme = PLAIN
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u' AND active=1
user_query = SELECT '/var/mail/vhosts/%d/%n' as home, 'maildir:/var/mail/vhosts/%d/%n' as mail, 5000 AS uid, 5000 AS gid FROM virtual_users WHERE email='%u'
DOVECOTSQL

chmod 600 /etc/dovecot/dovecot-sql.conf.ext

# Generate Dovecot SSL if not exists
if [ ! -f /etc/dovecot/private/dovecot.pem ]; then
    echo "Generating Dovecot SSL certificates..."
    mkdir -p /etc/dovecot/private
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/dovecot/private/dovecot.pem \
        -out /etc/dovecot/dovecot.pem \
        -subj "/C=BD/ST=Dhaka/L=Dhaka/O=Syscomatic/CN=mail.system.syscomatic.com"
    chmod 600 /etc/dovecot/private/dovecot.pem
    chown dovecot:dovecot /etc/dovecot/private/dovecot.pem
fi

# Initialize DB
mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS mailserver;" 2>/dev/null || true
[ -f /docker-entrypoint-initdb.d/init.sql ] && mysql -h database -u root -p${MYSQL_ROOT_PASSWORD} mailserver < /docker-entrypoint-initdb.d/init.sql 2>/dev/null || true

mkdir -p /var/mail/vhosts/system.syscomatic.com
chown -R vmail:vmail /var/mail
chmod -R 770 /var/mail

echo "Starting services..."
exec supervisord -n -c /etc/supervisor/supervisord.conf