#!/bin/bash
set -e

echo "=========================================="
echo "Mail Server Setup for system.syscomatic.com"
echo "Integrating with aaPanel Nginx"
echo "=========================================="

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Creating .env file with default values..."
    cat > .env << EOF
# Mail Server Configuration
DOMAIN=system.syscomatic.com
HOSTNAME=mail.system.syscomatic.com
POSTMASTER_PASSWORD=$(openssl rand -base64 16)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16)
MYSQL_PASSWORD=$(openssl rand -base64 16)
RAINLOOP_ADMIN_PASSWORD=$(openssl rand -base64 12)

# Server IP
SERVER_IP=156.67.216.209
EOF
    export $(cat .env | grep -v '^#' | xargs)
fi

# Create directory structure
echo "Creating directory structure..."
mkdir -p ssl

# Generate SSL certificates if not exists
if [ ! -f ssl/mail.crt ] || [ ! -f ssl/mail.key ]; then
    echo "Generating SSL certificates..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout ssl/mail.key \
        -out ssl/mail.crt \
        -subj "/C=BD/ST=Dhaka/L=Dhaka/O=Syscomatic/CN=mail.system.syscomatic.com"
    chmod 600 ssl/mail.key
fi

# Create Docker network
echo "Creating Docker network..."
docker network create mail-network 2>/dev/null || echo "Network already exists"

# Stop and remove existing containers
echo "Cleaning up existing containers..."
docker-compose down 2>/dev/null || true

# Build and start containers
echo "Building and starting containers..."
docker-compose build
docker-compose up -d

echo "Waiting for services to start..."
sleep 30

# Configure aaPanel Nginx
echo "Configuring aaPanel Nginx..."
NGINX_CONF="/www/server/panel/vhost/nginx/system.syscomatic.com.conf"

if [ -f "$NGINX_CONF" ]; then
    echo "Backing up existing Nginx config..."
    cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d%H%M%S)"
fi

# Create Nginx configuration for aaPanel
cat > /tmp/system_nginx.conf << EOF
# Webmail - RainLoop
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # Timeouts
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
}

# Static files caching
location ~* \\.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|eot)\$ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host \$host;
    expires 1y;
    add_header Cache-Control "public, immutable";
}

# Protect sensitive paths
location ~ /(data|vendor|\\.git) {
    deny all;
    return 404;
}
EOF

echo "Add the above Nginx configuration to your aaPanel site for system.syscomatic.com"
echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "Services running on localhost:"
echo "- Mail server ports: 25, 143, 587, 993, 465"
echo "- Webmail: http://127.0.0.1:8080"
echo ""
echo "aaPanel Nginx Configuration Required:"
echo "1. Login to aaPanel"
echo "2. Go to Websites → system.syscomatic.com"
echo "3. Click 'Configuration' (Nginx)"
echo "4. Add the proxy configuration shown above"
echo ""
echo "Access Points after Nginx config:"
echo "1. Webmail: https://system.syscomatic.com"
echo "2. Admin Panel: https://system.syscomatic.com/?admin"
echo "   Username: admin"
echo "   Password: ${RAINLOOP_ADMIN_PASSWORD}"
echo ""
echo "Mail Server Settings:"
echo "IMAP: mail.system.syscomatic.com:993 (SSL)"
echo "SMTP: mail.system.syscomatic.com:587 (STARTTLS)"
echo "Admin Email: admin@system.syscomatic.com"
echo ""
echo "To add users:"
echo "mysql -h 127.0.0.1 -P 3306 -u mailuser -p${MYSQL_PASSWORD} mailserver"
echo ""
echo "Check logs: docker-compose logs -f"
echo "Stop services: docker-compose down"
echo "Start services: docker-compose up -d"
echo "=========================================="