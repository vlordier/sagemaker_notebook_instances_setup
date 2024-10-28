#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Define absolute paths
LIFECYCLE_DIR="/home/ec2-user/SageMaker/lifecycle_configurations"
REPO_LIFECYCLE_DIR="./lifecycle_configurations"
BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup"
CODE_SERVER_DIR="${BASE_DIR}/code-server"
AUTOSTOP_DIR="${BASE_DIR}/autostop"

# Create all required directories
for dir in "$LIFECYCLE_DIR" "$BASE_DIR" "$CODE_SERVER_DIR" "$AUTOSTOP_DIR"; do
	mkdir -p "$dir" || {
		echo "Failed to create directory: $dir"
		exit 1
	}
done

# Copy lifecycle scripts
echo "Copying lifecycle configuration scripts..."
cp -f "${REPO_LIFECYCLE_DIR}/on-create.sh" "${LIFECYCLE_DIR}/on-create.sh" || {
	echo "Failed to copy on-create.sh"
	exit 1
}
cp -f "${REPO_LIFECYCLE_DIR}/on-start.sh" "${LIFECYCLE_DIR}/on-start.sh" || {
	echo "Failed to copy on-start.sh"
	exit 1
}

# Copy code-server files
echo "Setting up code-server..."
cp -f "${REPO_LIFECYCLE_DIR}/on-create.sh" "${CODE_SERVER_DIR}/on-create.sh" || {
	echo "Failed to copy code-server setup script"
	exit 1
}

# Copy autostop files
echo "Setting up autostop..."
cp -f autostop/autostop.py "${AUTOSTOP_DIR}/autostop.py" || {
	echo "Failed to copy autostop.py"
	exit 1
}
cp -f autostop/autostop_config.env "${AUTOSTOP_DIR}/autostop_config.env" || {
	echo "Failed to copy autostop_config.env"
	exit 1
}

# Verify all required files exist
required_files=(
	"${LIFECYCLE_DIR}/on-create.sh"
	"${LIFECYCLE_DIR}/on-start.sh"
	"${CODE_SERVER_DIR}/on-create.sh"
	"${AUTOSTOP_DIR}/autostop.py"
	"${AUTOSTOP_DIR}/autostop_config.env"
)

for file in "${required_files[@]}"; do
	if [ ! -f "$file" ]; then
		echo "Failed to verify file exists: $file"
		exit 1
	fi
done

# Set correct permissions
chmod 755 "${LIFECYCLE_DIR}/on-create.sh"
chmod 755 "${LIFECYCLE_DIR}/on-start.sh"
chmod 755 "${AUTOSTOP_DIR}/autostop.py"
chmod 644 "${AUTOSTOP_DIR}/autostop_config.env"

echo "Setup completed successfully:"
echo "- Lifecycle scripts installed to: ${LIFECYCLE_DIR}"
echo "- Code-server setup in: ${CODE_SERVER_DIR}"
echo "- Autostop configured in: ${AUTOSTOP_DIR}"
