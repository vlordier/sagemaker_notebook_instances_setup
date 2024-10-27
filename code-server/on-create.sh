#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

# OVERVIEW:
# This script runs once when the SageMaker notebook instance is created.
# It installs code-server, generates a secure password, and configures Nginx for access over HTTPS.

# Define the base directory for code-server setup
BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup"

# Create necessary directories
mkdir -p "$BASE_DIR/code-server"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root"
	exit 1
fi

# Install code-server
echo "📦 Installing code-server..."
if ! curl -fsSL https://code-server.dev/install.sh | sh; then
	echo "Failed to install code-server"
	exit 1
fi

# Generate a secure random password using OpenSSL
PASSWORD=$(openssl rand -base64 16)

# Log the generated password to files for future retrieval
PASSWORD_LOG="/home/ec2-user/SageMaker/code-server-password.txt"
PASSWORD_BACKUP="/home/ec2-user/SageMaker/.code-server-password.backup"
echo "Generated code-server password: $PASSWORD" | tee "$PASSWORD_LOG"
echo "$PASSWORD" | sudo tee "$PASSWORD_BACKUP" >/dev/null
sudo chmod 600 "$PASSWORD_BACKUP"

# Create the code-server configuration file
echo "⚙️ Configuring code-server..."
mkdir -p /home/ec2-user/.config/code-server
cat <<EOF >/home/ec2-user/.config/code-server/config.yaml
bind-addr: 127.0.0.1:8080
auth: password
password: $PASSWORD  # Dynamically generated password
cert: false
EOF

# Set correct permissions
chown -R ec2-user:ec2-user /home/ec2-user/.config

# Create a systemd service for code-server
echo "🔧 Setting up code-server service..."
cat <<EOF | sudo tee /etc/systemd/system/code-server.service
[Unit]
Description=code-server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/code-server
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Install and configure Nginx
echo "🌐 Installing Nginx..."
sudo amazon-linux-extras install nginx1 -y

# Generate self-signed SSL certificates with stronger security
echo "Generating self-signed SSL certificates..."
sudo mkdir -p /opt/ml/certificates
sudo openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
	-sha256 \
	-keyout /opt/ml/certificates/mykey.key \
	-out /opt/ml/certificates/mycert.crt \
	-subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$(hostname)" \
	-addext "subjectAltName = DNS:$(hostname),DNS:localhost"
sudo chmod 600 /opt/ml/certificates/mykey.key
sudo chown -R nginx:nginx /opt/ml/certificates

# Configure Nginx to reverse proxy code-server
echo "Configuring Nginx for code-server reverse proxy..."
cat <<EOF | sudo tee /etc/nginx/nginx.conf
user  nginx;
worker_processes  auto;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    server {
        listen 0.0.0.0:443 ssl;
        server_name _;

        ssl_certificate     /opt/ml/certificates/mycert.crt;
        ssl_certificate_key /opt/ml/certificates/mykey.key;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 'healthy\n';
        }

        location / {
            proxy_pass http://127.0.0.1:8080/;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Accept-Encoding gzip;
            proxy_set_header Host \$host;

            # Timeout settings
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
    }
}
EOF

# Enable and start Nginx service
echo "Starting Nginx service..."
sudo systemctl enable nginx
sudo systemctl start nginx

echo "Code-server setup completed during instance creation."
echo "Password for code-server has been saved to $PASSWORD_LOG"
