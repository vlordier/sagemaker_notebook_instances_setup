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

# Ensure curl is available
if ! command -v curl &>/dev/null; then
	echo "curl could not be found. Installing curl..." | tee -a "$LOG_FILE"
	sudo yum install -y curl >>"$LOG_FILE" 2>&1 || {
		echo "Failed to install curl" | tee -a "$LOG_FILE"
		exit 1
	}
else
	echo "curl is already installed." | tee -a "$LOG_FILE"
fi

# Create persistent directories
PERSISTENT_DIR="/home/ec2-user/SageMaker/.local/code-server"
JUPYTER_DIR="/home/ec2-user/.jupyter"
mkdir -p "${JUPYTER_DIR}"

# Install required pip packages
echo "Installing Jupyter server proxy..." | tee -a "$LOG_FILE"
pip install jupyter-server-proxy jupyterlab-codserver >>"$LOG_FILE" 2>&1 || {
	echo "Failed to install Jupyter packages" | tee -a "$LOG_FILE"
	exit 1
}
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
