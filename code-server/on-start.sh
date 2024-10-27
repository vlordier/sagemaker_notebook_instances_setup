#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

# OVERVIEW:
# This script runs every time the SageMaker notebook instance starts.
# It starts necessary services like code-server and Nginx, and logs the URL for VSCode access.

# Start code-server service
echo "🚀 Starting code-server service..."
if ! sudo systemctl daemon-reload; then
	echo "Failed to reload systemd daemon"
	exit 1
fi

if ! sudo systemctl start code-server; then
	echo "Failed to start code-server service"
	exit 1
fi

# Start Nginx
echo "🌐 Starting Nginx..."
if ! sudo systemctl start nginx; then
	echo "Failed to start Nginx"
	exit 1
fi

# Retrieve and log the password from the password file
PASSWORD_LOG="/home/ec2-user/SageMaker/code-server-password.txt"
if [ -f "$PASSWORD_LOG" ]; then
	PASSWORD=$(grep 'Generated code-server password' "$PASSWORD_LOG" | awk '{print $4}')
	echo "🔑 Password for code-server: $PASSWORD"
else
	echo "Password log not found!"
fi

# Output VSCode URL to logs
PUBLIC_DNS=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
CODE_SERVER_URL="https://${PUBLIC_DNS}"
echo "VSCode is running at: ${CODE_SERVER_URL}" | sudo tee -a /var/log/jupyter.log

# Start health monitoring
echo "🏥 Starting health monitoring..."
if ! /home/ec2-user/SageMaker/my-sagemaker-setup/healthcheck.sh >/var/log/healthcheck.log 2>&1; then
	echo "Warning: Health check failed on startup"
fi

echo "Code-server is ready for use."
