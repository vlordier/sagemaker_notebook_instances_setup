#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

# OVERVIEW:
# This script runs once when the SageMaker notebook instance is created.
# It installs necessary software and sets up initial configurations for autostop and code-server.

echo "Running on-create script..."

# Define a base directory
BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup"

# Ensure the base directory exists and has the correct permissions
# This is important because the SageMaker notebook instance is ephemeral
# and the lifecycle configuration scripts run as the root user.

# Create the base directory if it does not exist
if [ ! -d "$BASE_DIR" ]; then
	mkdir -p "$BASE_DIR"
fi

# Set the correct permissions for the base directory
chmod 755 "$BASE_DIR"

# Create necessary directories with proper permissions
mkdir -p "$BASE_DIR/autostop" "$BASE_DIR/code-server"
chmod 755 "$BASE_DIR" "$BASE_DIR/autostop" "$BASE_DIR/code-server"

# Function to verify and set permissions
verify_permissions() {
	local file=$1
	local perms=$2
	if [ ! -f "$file" ]; then
		echo "❌ Error: File not found: $file"
		return 1
	fi
	if [ "$(stat -f "%Lp" "$file")" != "$perms" ]; then
		echo "Setting permissions $perms on $file"
		chmod "$perms" "$file" || return 1
	fi
	return 0
}

# Verify permissions of critical files
critical_files=(
	"$BASE_DIR/autostop/autostop.py:755"
	"$BASE_DIR/code-server/on-create.sh:755"
	"$BASE_DIR/code-server/on-start.sh:755"
	"$BASE_DIR/healthcheck.sh:755"
)

for file_entry in "${critical_files[@]}"; do
	IFS=':' read -r file perms <<<"$file_entry"
	verify_permissions "$file" "$perms" || echo "⚠️ Warning: Permission check failed for $file"
done

# Install dependencies and set up autostop
echo "Setting up autostop functionality..."
cd "$BASE_DIR/autostop"

# Install dependencies for autostop
sudo yum install -y python3
sudo python3 -m pip install --upgrade pip
sudo pip3 install boto3 requests urllib3 pytz psutil

# Copy autostop.py to /usr/local/bin (we copy from the persistent SageMaker directory)
sudo cp "$BASE_DIR/autostop/autostop.py" /usr/local/bin/autostop.py
sudo chmod +x /usr/local/bin/autostop.py

echo "Autostop initial setup completed."

# Install and configure code-server
echo "Installing code-server..."
curl -fsSL https://code-server.dev/install.sh | sh

# Create code-server config
mkdir -p /home/ec2-user/.config/code-server
cat <<EOF >/home/ec2-user/.config/code-server/config.yaml
bind-addr: 127.0.0.1:8080
auth: password
password: your_secure_password  # Replace with a strong password
cert: false
EOF

# Set ownership
chown -R ec2-user:ec2-user /home/ec2-user/.config

# Create systemd service for code-server
echo "Setting up code-server service..."
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

# Install Nginx
echo "Installing Nginx..."
sudo amazon-linux-extras install nginx1 -y

# Generate self-signed SSL certificates (for testing purposes)
echo "Generating self-signed SSL certificates..."
sudo mkdir -p /opt/ml/certificates
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
	-keyout /opt/ml/certificates/mykey.key \
	-out /opt/ml/certificates/mycert.crt \
	-subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=localhost"
sudo chown -R nginx:nginx /opt/ml/certificates

# Configure Nginx
echo "Configuring Nginx..."
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

        location / {
            proxy_pass http://127.0.0.1:8080/;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Accept-Encoding gzip;
            proxy_set_header Host \$host;
        }
    }
}
EOF

echo "on-create script completed."
