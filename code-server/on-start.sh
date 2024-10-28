#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

echo "🚀 Starting code-server and Nginx services..."

# Reload systemd to account for new/updated services
echo "🔄 Reloading systemd daemon..."
if ! sudo systemctl daemon-reload; then
	echo "❌ Error: Failed to reload systemd daemon."
	exit 1
fi

# Start code-server service with error handling
echo "📦 Starting code-server service..."
if sudo systemctl start code-server; then
	echo "✅ code-server service started successfully."
else
	echo "❌ Error: Failed to start code-server service."
	sudo journalctl -xeu code-server.service
	exit 1
fi

# Start Nginx service with error handling
echo "🌐 Starting Nginx service..."
if sudo systemctl start nginx; then
	echo "✅ Nginx service started successfully."
else
	echo "❌ Error: Failed to start Nginx service."
	sudo journalctl -xeu nginx.service
	exit 1
fi

# Check and display code-server password
PASSWORD_LOG="/home/ec2-user/SageMaker/code-server-password.txt"
if [ -f "$PASSWORD_LOG" ]; then
	PASSWORD=$(grep 'Generated code-server password' "$PASSWORD_LOG" | awk '{print $4}')
	if [ -n "$PASSWORD" ]; then
		echo "🔑 Code-server password: $PASSWORD"
	else
		echo "⚠️ Warning: Unable to retrieve code-server password from $PASSWORD_LOG."
	fi
else
	echo "⚠️ Warning: Password log file not found at $PASSWORD_LOG."
fi

# Fetch and display the public DNS for code-server access
PUBLIC_DNS=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname || echo "UNKNOWN")
if [ "$PUBLIC_DNS" != "UNKNOWN" ]; then
	echo "🌍 Code-server URL: https://${PUBLIC_DNS}"
else
	echo "⚠️ Warning: Unable to retrieve public DNS hostname."
fi

echo "✅ All services started successfully."
