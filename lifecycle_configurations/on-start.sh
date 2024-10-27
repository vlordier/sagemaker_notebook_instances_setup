#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

# OVERVIEW:
# This script runs every time the SageMaker notebook instance starts.
# It starts necessary services and sets up cron jobs for autostop.

echo "Running on-start script..."

# Define a base directory
BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup"

# Start code-server service
echo "Starting code-server service..."
sudo systemctl daemon-reload
sudo systemctl restart code-server || {
	echo "Failed to start code-server service"
	exit 1
}

# Start Nginx
echo "Starting Nginx..."
sudo systemctl restart nginx || {
	echo "Failed to start Nginx service"
	exit 1
}

# Ensure autostop is configured
echo "Configuring autostop..."
AUTOSTOP_CONFIG="/home/ec2-user/SageMaker/my-sagemaker-setup/autostop/autostop_config.env"
if [ ! -f "$AUTOSTOP_CONFIG" ]; then
	echo "Creating autostop configuration..."
	cat <<EOF >"$AUTOSTOP_CONFIG"
IDLE_TIME=5400
AWS_PROFILE=saml
AWS_REGION=eu-west-1
TIMEZONE=Europe/Paris
CPU_THRESHOLD=5
EOF
fi

# Output VSCode URL to logs
PUBLIC_DNS=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
CODE_SERVER_URL="https://${PUBLIC_DNS}"
echo "VSCode is running at: ${CODE_SERVER_URL}" | sudo tee -a /var/log/jupyter.log

# Set up autostop cron job
echo "Setting up autostop cron job..."
cd "$BASE_DIR/autostop"

# Load configuration
CONFIG_FILE="/home/ec2-user/SageMaker/my-sagemaker-setup/config/instance_config.env"
if [ ! -f "$CONFIG_FILE" ]; then
	echo "Configuration file not found at $CONFIG_FILE"
	echo "Using default configuration from defaults.env"
	CONFIG_FILE="/home/ec2-user/SageMaker/my-sagemaker-setup/config/defaults.env"
fi

set -a
source "$CONFIG_FILE"
set +a

# Set up cron job for autostop
(
	crontab -l 2>/dev/null
	echo "$CRON_FREQUENCY python3 /usr/local/bin/autostop.py >> /var/log/autostop.log 2>&1"
) | crontab -

echo "on-start script completed."
