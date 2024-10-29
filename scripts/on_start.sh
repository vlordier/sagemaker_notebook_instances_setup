#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Log file for this script
LOG_FILE="/var/log/on-start.log"
exec > >(tee -i "$LOG_FILE") 2>&1
echo "Starting code-server and monitoring for idle activity at $(date)"

# Ensure persistent directory exists
PERSISTENT_DIR="/home/ec2-user/SageMaker/.local/code-server"
mkdir -p "${PERSISTENT_DIR}"

# Function to install VS Code extensions from .vscode/extensions.json
install_vscode_extensions() {
	local vscode_dir="$1"
	if [ -f "${vscode_dir}/extensions.json" ]; then
		echo "Found extensions.json in ${vscode_dir}" | tee -a "$LOG_FILE"
		# Extract extension IDs and install them
		extensions=$(jq -r '.recommendations[]' "${vscode_dir}/extensions.json" 2>/dev/null)
		if [ -n "$extensions" ]; then
			while IFS= read -r extension; do
				echo "Installing extension: ${extension}" | tee -a "$LOG_FILE"
				code-server --install-extension "$extension" >>"$LOG_FILE" 2>&1
			done <<<"$extensions"
		fi
	fi
}

# Function to handle devcontainer setup
setup_devcontainer() {
	local vscode_dir="$1"
	if [ -f "${vscode_dir}/devcontainer.json" ]; then
		echo "Found devcontainer.json in ${vscode_dir}" | tee -a "$LOG_FILE"
		# TODO: Implement devcontainer setup logic
		# This would involve parsing devcontainer.json and setting up the environment
		# For now, we'll just log that we found it
		echo "Note: devcontainer.json support is planned for future implementation" | tee -a "$LOG_FILE"
	fi
}

# Scan for .vscode directories and process configurations
echo "Scanning for .vscode configurations..." | tee -a "$LOG_FILE"
find /home/ec2-user/SageMaker -type d -name ".vscode" 2>/dev/null | while read -r vscode_dir; do
	echo "Processing .vscode directory: ${vscode_dir}" | tee -a "$LOG_FILE"
	install_vscode_extensions "$vscode_dir"
	setup_devcontainer "$vscode_dir"
done

# Start code-server from persistent location
export PATH="${PERSISTENT_DIR}/bin:$PATH"
nohup code-server --bind-addr 0.0.0.0:8080 --auth none --user-data-dir "${PERSISTENT_DIR}/data" >/var/log/code-server.log 2>&1 &
CODE_SERVER_PID=$!
echo "code-server started with PID $CODE_SERVER_PID" | tee -a "$LOG_FILE"

# Get instance information from metadata service
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
NOTEBOOK_NAME=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/sagemaker:notebook-name)

# Print access information
echo "Access VS Code directly at port 8080" | tee -a "$LOG_FILE"
FULL_URL="https://${NOTEBOOK_NAME}.notebook.${REGION}.sagemaker.aws:8080/"
echo "Full URL: ${FULL_URL}" | tee -a "$LOG_FILE"

# Test URL accessibility
echo "Testing URL accessibility..." | tee -a "$LOG_FILE"
MAX_RETRIES=12 # Try for 2 minutes (12 * 10 seconds)
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
	if curl -s -o /dev/null -w "%{http_code}" "${FULL_URL}" | grep -q "200\|302"; then
		echo "✓ URL is accessible!" | tee -a "$LOG_FILE"
		break
	else
		echo "Waiting for URL to become accessible (attempt $((RETRY_COUNT + 1))/${MAX_RETRIES})..." | tee -a "$LOG_FILE"
		sleep 10
		RETRY_COUNT=$((RETRY_COUNT + 1))
	fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
	echo "⚠️  Warning: URL could not be verified after ${MAX_RETRIES} attempts" | tee -a "$LOG_FILE"
	echo "Please check the URL manually and ensure all services are running correctly" | tee -a "$LOG_FILE"
fi

# Get environment variables with defaults
IDLE_TIMEOUT="${IDLE_TIMEOUT:-5400}" # Default: 1.5 hours in seconds
INSTANCE_NAME="${INSTANCE_NAME:-default-notebook}"
TIMEZONE="${TIMEZONE:-UTC}" # Default: UTC

while true; do
	# Check for the last modification time of code-server logs to detect activity
	if [ -f /var/log/code-server.log ]; then
		last_activity=$(date +%s -r /var/log/code-server.log)
	else
		echo "Log file not found. Exiting monitoring loop." | tee -a "$LOG_FILE"
		break
	fi

	current_time=$(date +%s)
	idle_time=$((current_time - last_activity))

	if [[ $idle_time -ge $IDLE_TIMEOUT ]]; then
		echo "code-server idle for $IDLE_TIMEOUT seconds. Stopping instance..." | tee -a "$LOG_FILE"
		if ! aws sagemaker stop-notebook-instance --notebook-instance-name "$INSTANCE_NAME"; then
			echo "Failed to stop notebook instance" | tee -a "$LOG_FILE"
			exit 1
		fi
		break
	fi

	# Sleep for 5 minutes before checking again
	sleep 300
done

echo "Script completed at $(date)" | tee -a "$LOG_FILE"
