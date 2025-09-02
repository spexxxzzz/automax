#!/bin/bash

# Script to update your existing Nginx configuration for app.autobro.cloud
# This will modify your current Nginx config to use the new domain

set -e

OLD_DOMAIN="try.autobro.cloud"
NEW_DOMAIN="app.autobro.cloud"

echo "🔄 Updating Nginx configuration from $OLD_DOMAIN to $NEW_DOMAIN..."

# First, let's find your current Nginx configuration file
NGINX_CONFIG=""
if [ -f "/etc/nginx/sites-available/$OLD_DOMAIN" ]; then
    NGINX_CONFIG="/etc/nginx/sites-available/$OLD_DOMAIN"
elif [ -f "/etc/nginx/sites-available/default" ]; then
    NGINX_CONFIG="/etc/nginx/sites-available/default"
elif [ -f "/etc/nginx/conf.d/$OLD_DOMAIN.conf" ]; then
    NGINX_CONFIG="/etc/nginx/conf.d/$OLD_DOMAIN.conf"
elif [ -f "/etc/nginx/conf.d/default.conf" ]; then
    NGINX_CONFIG="/etc/nginx/conf.d/default.conf"
else
    echo "❌ Could not find existing Nginx configuration file"
    echo "Please run this command to find it: sudo find /etc/nginx -name '*.conf' -type f"
    exit 1
fi

echo "📁 Found Nginx config at: $NGINX_CONFIG"

# Create backup
echo "💾 Creating backup of current configuration..."
sudo cp "$NGINX_CONFIG" "${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

# Create new configuration for app.autobro.cloud
echo "📝 Creating new configuration for $NEW_DOMAIN..."
sudo tee "/etc/nginx/sites-available/$NEW_DOMAIN" > /dev/null << EOF
server {
    server_name $NEW_DOMAIN;

    # Forward all non-API traffic to the frontend
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Additional settings for better performance
        proxy_buffering off;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        proxy_connect_timeout 30s;
    }

    # Forward all API traffic to the backend
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Settings for API calls
        proxy_buffering off;
        proxy_read_timeout 1800s;
        proxy_send_timeout 1800s;
        proxy_connect_timeout 60s;
    }

    # WebSocket support for real-time features
    location /ws {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://localhost:8000/api/health;
        proxy_set_header Host \$host;
        proxy_read_timeout 10s;
        proxy_send_timeout 10s;
        proxy_connect_timeout 5s;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/$NEW_DOMAIN/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/$NEW_DOMAIN/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

}

server {
    if (\$host = $NEW_DOMAIN) {
        return 301 https://\$host\$request_uri;
    } # managed by Certbot

    listen 80;
    server_name $NEW_DOMAIN;
    return 404; # managed by Certbot
}
EOF

# Enable the new site
echo "✅ Enabling new site configuration..."
sudo ln -sf "/etc/nginx/sites-available/$NEW_DOMAIN" "/etc/nginx/sites-enabled/$NEW_DOMAIN"

# Test Nginx configuration
echo "🧪 Testing Nginx configuration..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo "✅ Nginx configuration is valid!"
    
    # Reload Nginx
    echo "🔄 Reloading Nginx..."
    sudo systemctl reload nginx
    
    echo ""
    echo "🎉 Nginx configuration updated successfully!"
    echo "🌐 Your site should now be available at: https://$NEW_DOMAIN"
    echo ""
    echo "📋 What was done:"
    echo "• Created backup: ${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "• Created new config: /etc/nginx/sites-available/$NEW_DOMAIN"
    echo "• Enabled new site: /etc/nginx/sites-enabled/$NEW_DOMAIN"
    echo "• Updated SSL certificate paths for $NEW_DOMAIN"
    echo ""
    echo "🔍 Test your site:"
    echo "  curl -I https://$NEW_DOMAIN"
    echo "  curl -I http://$NEW_DOMAIN (should redirect to HTTPS)"
    
    # Optional: Disable old site if desired
    echo ""
    echo "💡 Optional: To disable the old $OLD_DOMAIN site, run:"
    echo "  sudo rm /etc/nginx/sites-enabled/$OLD_DOMAIN"
    echo "  sudo systemctl reload nginx"
    
else
    echo "❌ Nginx configuration test failed!"
    echo "Please check the configuration and try again."
    echo "Backup is available at: ${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    exit 1
fi
