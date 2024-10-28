#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Ensure the script has proper permissions
if [ ! -x "$0" ]; then
	echo "❌ Error: Script must be executable"
	chmod +x "$0" || {
		echo "Failed to set executable permission"
		exit 1
	}
fi

VENV_DIR="venv"
REQUIREMENTS="../requirements.txt"

# Ensure requirements.txt is readable
if [ ! -r "$REQUIREMENTS" ]; then
	echo "❌ Error: Cannot read $REQUIREMENTS"
	if chmod 644 "$REQUIREMENTS"; then
		echo "Permissions set on $REQUIREMENTS"
	else
		echo "Failed to set permissions on $REQUIREMENTS"
		exit 1
	fi
fi

# Check if python3 is installed
if ! command -v python3 &>/dev/null; then
	echo "❌ Error: Python3 is required but not installed. Please install Python3 first."
	exit 1
fi

# Check if pip is installed
if ! python3 -m pip --version &>/dev/null; then
	echo "❌ Error: pip is not installed. Installing pip..."
	curl https://bootstrap.pypa.io/get-pip.py | python3 || {
		echo "Failed to install pip"
		exit 1
	}
fi

# Check if virtualenv is installed and install if missing
if ! python3 -m pip show virtualenv &>/dev/null; then
	echo "📦 Installing virtualenv..."
	python3 -m pip install --user virtualenv || {
		echo "Failed to install virtualenv"
		exit 1
	}
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
	echo "🌱 Creating virtual environment in $VENV_DIR..."
	python3 -m venv "$VENV_DIR" || {
		echo "Failed to create virtual environment"
		exit 1
	}
else
	echo "✅ Virtual environment already exists at $VENV_DIR"
fi

# Activate the virtual environment and install dependencies
echo "🔧 Activating virtual environment and installing dependencies..."
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# Upgrade pip to the latest version
echo "⬆️  Upgrading pip..."
pip install --upgrade pip || {
	echo "Failed to upgrade pip"
	exit 1
}

# Install required packages from requirements.txt
echo "📜 Installing packages from $REQUIREMENTS..."
if ! pip install -r "$REQUIREMENTS"; then
	echo "❌ Error: Failed to install packages"
	exit 1
fi

echo "✅ Setup complete! To activate the virtual environment, run:"
echo "source $VENV_DIR/bin/activate"
