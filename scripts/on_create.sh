#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Define log file
LOG_FILE="/var/log/on-create.log"
exec > >(tee -i "$LOG_FILE") 2>&1
echo "Starting the on-create script at $(date)"

# Function to log errors
error_exit() {
	echo "Error on line $1. Exiting." | tee -a "$LOG_FILE"
	exit 1
}

trap 'error_exit $LINENO' ERR

# Install required packages
for pkg in curl nginx; do
	if ! command -v $pkg &>/dev/null; then
		echo "$pkg could not be found. Installing $pkg..." | tee -a "$LOG_FILE"
		sudo yum install -y "$pkg" | sudo tee -a "$LOG_FILE" || {
			echo "Failed to install $pkg" | tee -a "$LOG_FILE"
			exit 1
		}
	else
		echo "$pkg is already installed." | tee -a "$LOG_FILE"
	fi
done

# Configure SELinux to allow nginx to proxy
if command -v setsebool &>/dev/null; then
	echo "Configuring SELinux for nginx..." | tee -a "$LOG_FILE"
	sudo setsebool -P httpd_can_network_connect 1 || {
		echo "Warning: Failed to configure SELinux" | tee -a "$LOG_FILE"
	}
fi

# Create persistent directories
PERSISTENT_DIR="/home/ec2-user/SageMaker/.local/code-server"
JUPYTER_DIR="/home/ec2-user/.jupyter"
mkdir -p "${JUPYTER_DIR}"

echo "Creating persistent directory at ${PERSISTENT_DIR}..." | tee -a "$LOG_FILE"
mkdir -p "${PERSISTENT_DIR}"

# Install code-server to persistent location
echo "Installing code-server to persistent storage..." | tee -a "$LOG_FILE"
export PREFIX="${PERSISTENT_DIR}"
if curl -fsSL https://code-server.dev/install.sh | sh >>"$LOG_FILE" 2>&1; then
	echo "code-server installed successfully to ${PERSISTENT_DIR}" | tee -a "$LOG_FILE"

	# Create symbolic link to make it available in PATH
	sudo ln -sf "${PERSISTENT_DIR}/bin/code-server" /usr/local/bin/code-server
else
	echo "Failed to install code-server" | tee -a "$LOG_FILE"
	exit 1
fi

echo "Script completed successfully at $(date)" | tee -a "$LOG_FILE"
