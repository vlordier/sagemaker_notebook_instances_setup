#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Ensure script has proper permissions
if [ ! -x "$0" ]; then
	echo "❌ Error: Script must be executable"
	chmod +x "$0" || {
		echo "Failed to set executable permission"
		exit 1
	}
fi

VENV_DIR="venv"
REQUIREMENTS="requirements.txt"

# Ensure requirements.txt is readable
if [ ! -r "$REQUIREMENTS" ]; then
	echo "❌ Error: Cannot read $REQUIREMENTS"
	chmod 644 "$REQUIREMENTS" || {
		echo "Failed to set permissions on $REQUIREMENTS"
		exit 1
	}
fi

# Check if python3 is installed
if ! command -v python3 &>/dev/null; then
	echo "Python3 is required but not installed. Please install Python3 first."
	exit 1
fi

# Check if virtualenv is installed
if ! python3 -m pip show virtualenv &>/dev/null; then
	echo "Installing virtualenv..."
	python3 -m pip install --user virtualenv
fi

# Create virtualenv if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
	echo "Creating virtual environment..."
	python3 -m venv "$VENV_DIR"
fi

# Activate virtualenv and install requirements
echo "Installing requirements..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
pip install --upgrade pip

# Install requirements
pip install -r "$REQUIREMENTS"

echo "Setup complete! To activate the virtual environment, run:"
echo "source venv/bin/activate"
