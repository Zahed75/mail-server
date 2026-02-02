#!/bin/bash
set -e

echo "=========================================="
echo "Mail Server Setup for system.syscomatic.com"
echo "=========================================="

# Create .env file if not exists
if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env << EOF
# Mail Server Configuration
DOMAIN=system.syscomatic.com
HOSTNAME=mail.system.syscomatic.com
POSTMASTER_PASSWORD=$(openssl rand -base64 12)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16)
MYSQL_PASSWORD=$(openssl rand -base64 16)
RAINLOOP_ADMIN_PASSWORD=$(openssl rand -base64 12)

# Server IP
SERVER_IP=156.67.216.209
EOF
fi

# Load environment variables
export $(cat .env | grep -v '^#' | xargs)

echo "Environment variables loaded."

# Create necessary directories
mkdir -p ssl

# Create Docker network
echo "Creating Docker network..."
docker network create mail-network 2>/dev/null || echo "Network already exists"

# Stop and remove existing containers
echo "Cleaning up existing containers..."
docker-compose down 2>/dev/null || true

# Build and start containers
echo "Building and starting containers..."
docker-compose build --no-cache
docker-compose up -d

echo "Waiting for services to start..."
sleep 30

# Show deployment info
echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "Docker Containers Status:"
docker-compose ps
echo ""
echo "Mail Server Ports (localhost only):"
echo "- SMTP: 127.0.0.1:1025"
echo "- SMTP Submission: 127.0.0.1:1587"
echo "- IMAP: 127.0.0.1:1143"
echo "- IMAPS: 127.0.0.1:1993"
echo "- SMTPS: 127.0.0.1:1465"
echo ""
echo "Webmail: http://127.0.0.1:8080"
echo "Admin Panel: http://127.0.0.1:8080/?admin"
echo "Admin Password: ${RAINLOOP_ADMIN_PASSWORD}"
echo ""
echo "MySQL Database:"
echo "Host: 127.0.0.1:3306"
echo "Username: mailuser"
echo "Password: ${MYSQL_PASSWORD}"
echo "Database: mailserver"
echo ""
echo "=========================================="
echo "AA-PANEL NGINX CONFIGURATION"
echo "=========================================="
echo ""
echo "Add this to your aaPanel Nginx config for system.syscomatic.com:"
echo ""
cat << 'EOF'
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
}
EOF
echo ""
echo "=========================================="
echo "To check logs: docker-compose logs -f"
echo "To stop: docker-compose down"
echo "To start: docker-compose up -d"
echo "=========================================="