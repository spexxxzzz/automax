#!/bin/bash

# SSL Setup Script for app.autobro.cloud
# Run this script on your VM to set up SSL certificates

set -e

DOMAIN="app.autobro.cloud"
EMAIL="your-email@example.com"  # Replace with your actual email

echo "🚀 Setting up SSL for $DOMAIN..."

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p nginx/logs
mkdir -p nginx/ssl

# Create Docker network if it doesn't exist
echo "🌐 Creating Docker network..."
docker network create suna-network 2>/dev/null || echo "Network already exists"

# Step 1: Start services without SSL first
echo "🔧 Starting services without SSL..."
docker compose -f docker-compose.yml up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Step 2: Start Nginx with HTTP only for certificate validation
echo "🔐 Starting Nginx for certificate validation..."
docker compose -f docker-compose.nginx.yml up -d nginx

# Wait for Nginx to be ready
echo "⏳ Waiting for Nginx to start..."
sleep 10

# Step 3: Get SSL certificate (staging first for testing)
echo "📜 Obtaining SSL certificate (staging)..."
docker compose -f docker-compose.nginx.yml run --rm certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email $EMAIL \
  --agree-tos \
  --no-eff-email \
  --staging \
  -d $DOMAIN

# Step 4: Test certificate was obtained
if docker compose -f docker-compose.nginx.yml exec nginx ls /etc/letsencrypt/live/$DOMAIN/fullchain.pem; then
    echo "✅ Staging certificate obtained successfully!"
    
    # Step 5: Get production certificate
    echo "🎯 Getting production certificate..."
    docker compose -f docker-compose.nginx.yml run --rm certbot certonly \
      --webroot \
      --webroot-path=/var/www/certbot \
      --email $EMAIL \
      --agree-tos \
      --no-eff-email \
      --force-renewal \
      -d $DOMAIN
    
    if docker compose -f docker-compose.nginx.yml exec nginx ls /etc/letsencrypt/live/$DOMAIN/fullchain.pem; then
        echo "🎉 Production certificate obtained successfully!"
        
        # Step 6: Reload Nginx with SSL configuration
        echo "🔄 Reloading Nginx with SSL..."
        docker compose -f docker-compose.nginx.yml exec nginx nginx -s reload
        
        echo ""
        echo "🎉 SSL setup complete!"
        echo "🌐 Your site should now be available at: https://$DOMAIN"
        echo ""
        echo "📋 Next steps:"
        echo "1. Update DNS records to point $DOMAIN to your server IP"
        echo "2. Test the site: curl -I https://$DOMAIN"
        echo "3. Set up certificate auto-renewal (see setup-renewal.sh)"
        
    else
        echo "❌ Failed to obtain production certificate"
        exit 1
    fi
else
    echo "❌ Failed to obtain staging certificate"
    echo "🔍 Check your DNS settings and ensure $DOMAIN points to this server"
    exit 1
fi



