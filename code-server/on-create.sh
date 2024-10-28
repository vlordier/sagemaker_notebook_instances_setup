#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

echo "🚀 Starting code-server installation and setup..."

# Define paths
BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup"
CODE_SERVER_DIR="$BASE_DIR/code-server"
PASSWORD_LOG="/home/ec2-user/SageMaker/code-server-password.txt"
PASSWORD_BACKUP="/home/ec2-user/SageMaker/.code-server-password.backup"
CERT_DIR="/opt/ml/certificates"
NGINX_CONF="/etc/nginx/nginx.conf"

# Check sudo privileges
echo "🔑 Verifying sudo privileges..."
if ! sudo -v; then
	echo "❌ Error: This script requires sudo privileges."
	exit 1
fi

# Install necessary system packages
echo "📦 Installing required system packages (git, wget)..."
if ! sudo yum update -y && sudo yum install -y git wget; then
	echo "❌ Error: Failed to install system packages."
	exit 1
fi

# Install code-server
echo "📥 Installing code-server..."
if ! curl -fsSL https://code-server.dev/install.sh | sh; then
	echo "❌ Error: Failed to install code-server."
	exit 1
fi

# Generate a secure random password using OpenSSL
echo "🔐 Generating a secure random password for code-server..."
PASSWORD=$(openssl rand -base64 16)

# Log the generated password to files for future retrieval
echo "📝 Storing the generated password..."
echo "Generated code-server password" | tee "$PASSWORD_LOG"
echo "$PASSWORD" >>"$PASSWORD_LOG"
sudo chmod 600 "$PASSWORD_LOG"
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

# Set correct permissions for the code-server configuration
sudo chown -R ec2-user:ec2-user /home/ec2-user/.config

# Create a systemd service for code-server
echo "🔧 Setting up code-server systemd service..."
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

# Reload systemd and enable code-server
echo "🔄 Reloading systemd and enabling code-server service..."
sudo systemctl daemon-reload
sudo systemctl enable code-server

# Install and configure Nginx
echo "🌐 Installing and configuring Nginx..."
if ! sudo amazon-linux-extras install nginx1 -y; then
	echo "❌ Error: Failed to install Nginx."
	exit 1
fi

# Generate self-signed SSL certificates
echo "🔒 Generating self-signed SSL certificates..."
sudo mkdir -p "$CERT_DIR"
if ! sudo openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
	-sha256 \
	-keyout "$CERT_DIR/mykey.key" \
	-out "$CERT_DIR/mycert.crt" \
	-subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$(hostname)" \
	-addext "subjectAltName = DNS:$(hostname),DNS:localhost"; then
	echo "❌ Error: Failed to generate SSL certificates."
	exit 1
fi
sudo chmod 600 "$CERT_DIR/mykey.key"
sudo chown -R nginx:nginx "$CERT_DIR"

# Configure Nginx for code-server reverse proxy
echo "🔧 Configuring Nginx to reverse proxy to code-server..."
cat <<EOF | sudo tee "$NGINX_CONF"
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

        ssl_certificate     $CERT_DIR/mycert.crt;
        ssl_certificate_key $CERT_DIR/mykey.key;

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
echo "🚀 Enabling and starting Nginx service..."
sudo systemctl enable nginx
if ! sudo systemctl start nginx; then
	echo "❌ Error: Failed to start Nginx."
	exit 1
fi

# Create and set up a Python virtual environment
echo "🐍 Setting up Python environment..."
if ! conda create -n python3 python=3.9 -y; then
	echo "❌ Error: Failed to create Python environment."
	exit 1
fi
source activate python3

# Install necessary Python packages
echo "📦 Installing Python packages..."
if ! pip install --upgrade pip && pip install boto3 pandas numpy matplotlib seaborn scikit-learn jupyter; then
	echo "❌ Error: Failed to install Python packages."
	exit 1
fi

echo "✅ Code-server setup completed!"
echo "🔑 The password for code-server has been saved to $PASSWORD_LOG"
