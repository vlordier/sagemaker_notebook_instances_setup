#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

echo "🚀 Starting instance creation setup..."

# Define paths
BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup"
LIFECYCLE_DIR="/home/ec2-user/SageMaker/lifecycle_configurations"
PASSWORD_LOG="/home/ec2-user/SageMaker/code-server-password.txt"
PASSWORD_BACKUP="/home/ec2-user/SageMaker/.code-server-password.backup"
CERT_DIR="/opt/ml/certificates"
NGINX_CONF="/etc/nginx/nginx.conf"

# Function to create directories with proper permissions
create_directory() {
	local dir="$1"
	echo "📁 Creating directory: $dir"
	sudo mkdir -p "$dir"
	sudo chown ec2-user:ec2-user "$dir"
	sudo chmod 755 "$dir"
}

# Create required directories
for dir in "$LIFECYCLE_DIR" "$BASE_DIR" "$BASE_DIR/autostop" "$BASE_DIR/code-server"; do
	create_directory "$dir"
done

# Run code-server setup if the setup script exists
echo "⚙️ Setting up code-server..."
if [ -f "$BASE_DIR/code-server/on-create.sh" ]; then
	bash "$BASE_DIR/code-server/on-create.sh"
else
	echo "⚠️ Warning: code-server setup script not found."
fi

# Initialize autostop configuration
echo "🔧 Configuring autostop..."
if [ -f "$BASE_DIR/autostop/autostop_config.env" ]; then
	source "$BASE_DIR/autostop/autostop_config.env"
else
	echo "⚠️ Warning: autostop configuration not found."
fi

# Ensure code-server directories are properly set up
create_directory "$BASE_DIR/autostop"
create_directory "$BASE_DIR/code-server"

# Install code-server
echo "📦 Installing code-server..."
if ! curl -fsSL https://code-server.dev/install.sh | sh; then
	echo "❌ Error: Failed to install code-server."
	exit 1
fi

# Generate a secure random password using OpenSSL
echo "🔐 Generating secure random password for code-server..."
PASSWORD=$(openssl rand -base64 16)

# Store the password in log files for future use
echo "📝 Saving code-server password..."
echo "Generated code-server password" | tee "$PASSWORD_LOG"
echo "$PASSWORD" >>"$PASSWORD_LOG"
sudo chmod 600 "$PASSWORD_LOG"
echo "$PASSWORD" | sudo tee "$PASSWORD_BACKUP" >/dev/null
sudo chmod 600 "$PASSWORD_BACKUP"

# Configure code-server
echo "⚙️ Configuring code-server..."
mkdir -p /home/ec2-user/.config/code-server
cat <<EOF >/home/ec2-user/.config/code-server/config.yaml
bind-addr: 127.0.0.1:8080
auth: password
password: $PASSWORD  # Dynamically generated password
cert: false
EOF
sudo chown -R ec2-user:ec2-user /home/ec2-user/.config

# Create systemd service for code-server
echo "🔧 Setting up systemd service for code-server..."
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

# Reload systemd configuration and start code-server service
sudo systemctl daemon-reload
sudo systemctl enable code-server
sudo systemctl start code-server

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

# Configure Nginx for reverse proxy to code-server
echo "🔧 Configuring Nginx for reverse proxy to code-server..."
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

        location / {
            proxy_pass http://127.0.0.1:8080/;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Accept-Encoding gzip;
            proxy_set_header Host \$host;

            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        location /health {
            access_log off;
            return 200 'healthy\n';
        }
    }
}
EOF

# Test Nginx configuration before restarting
echo "🔄 Testing Nginx configuration..."
if ! sudo nginx -t; then
	echo "❌ Error: Nginx configuration test failed."
	exit 1
fi

# Enable and start Nginx service
echo "🚀 Enabling and starting Nginx service..."
sudo systemctl enable nginx
sudo systemctl start nginx

echo "✅ Code-server setup completed. Password saved to $PASSWORD_LOG."

# Additional system setup
echo "🛠️ Running additional system setup..."
sudo yum update -y
sudo yum install -y git wget

# Set up Python environment
echo "🐍 Setting up Python environment..."
if ! conda create -n python3 python=3.11 -y; then
	echo "❌ Error: Failed to set up Python environment."
	exit 1
fi
source activate python3

# Install Python packages
echo "📦 Installing Python packages..."
pip install --upgrade pip
pip install boto3 pandas numpy matplotlib seaborn scikit-learn jupyter

echo "🎉 Setup complete."
