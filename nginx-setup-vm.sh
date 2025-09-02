#!/bin/bash

# Complete Nginx Setup Script for VM
# Run this on your VM to set up Nginx with your existing SSL certificate

set -e

DOMAIN="app.autobro.cloud"

echo "🚀 Setting up Nginx for $DOMAIN with existing SSL certificate..."

# Step 1: Install Nginx if not already installed
echo "📦 Installing Nginx..."
sudo apt update
sudo apt install -y nginx

# Step 2: Remove default Nginx config
echo "🗑️ Removing default Nginx configuration..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-available/default

# Step 3: Create Nginx configuration for your domain
echo "📝 Creating Nginx configuration..."
sudo tee /etc/nginx/sites-available/app.autobro.cloud > /dev/null << 'EOF'
# Upstream servers for load balancing
upstream frontend {
    server 127.0.0.1:3000;
    keepalive 32;
}

upstream backend {
    server 127.0.0.1:8000;
    keepalive 32;
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name app.autobro.cloud;
    
    # Allow Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }
    
    # Redirect all other HTTP traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name app.autobro.cloud;

    # SSL Configuration (using your existing certificates)
    ssl_certificate /etc/letsencrypt/live/app.autobro.cloud/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.autobro.cloud/privkey.pem;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Client settings
    client_max_body_size 50M;
    client_body_timeout 60s;
    client_header_timeout 60s;

    # API Backend routes
    location /api/ {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        proxy_cache_bypass $http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 1800s;
        proxy_send_timeout 1800s;
        proxy_connect_timeout 60s;
    }

    # WebSocket connections for real-time features
    location /ws {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Frontend and static files
    location / {
        proxy_pass http://frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        
        proxy_cache_bypass $http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        proxy_connect_timeout 30s;
    }

    # Static assets caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary Accept-Encoding;
    }

    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://backend/api/health;
        proxy_set_header Host $host;
        proxy_read_timeout 10s;
        proxy_send_timeout 10s;
        proxy_connect_timeout 5s;
    }

    # Block common attack patterns
    location ~* \.(php|asp|aspx|jsp)$ {
        return 444;
    }
    
    location ~* /(\.|wp-|admin|phpmyadmin) {
        return 444;
    }
}
EOF

# Step 4: Enable the site
echo "✅ Enabling site configuration..."
sudo ln -sf /etc/nginx/sites-available/app.autobro.cloud /etc/nginx/sites-enabled/

# Step 5: Test Nginx configuration
echo "🧪 Testing Nginx configuration..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration is valid!"
    
    # Step 6: Restart Nginx
    echo "🔄 Restarting Nginx..."
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    
    echo ""
    echo "🎉 Nginx setup complete!"
    echo "🌐 Your site should now be available at: https://$DOMAIN"
    echo ""
    echo "📋 Status check:"
    echo "• Nginx status: $(sudo systemctl is-active nginx)"
    echo "• SSL certificate: $(sudo ls -la /etc/letsencrypt/live/$DOMAIN/fullchain.pem 2>/dev/null && echo 'Found' || echo 'Not found')"
    echo ""
    echo "🔍 Test your site:"
    echo "  curl -I https://$DOMAIN"
    echo "  curl -I http://$DOMAIN (should redirect to HTTPS)"
    
else
    echo "❌ Nginx configuration test failed!"
    echo "Please check the configuration and try again."
    exit 1
fi






