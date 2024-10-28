#!/bin/bash
#!/bin/bash

# Exit on error, undefined vars, and pipe failures
set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

# Enable debug mode (set DEBUG=true to enable)
DEBUG=${DEBUG:-false}
if [ "$DEBUG" = "true" ]; then
	set -x
fi

# OVERVIEW:
# This script sets up the autostop functionality for the SageMaker notebook instance.
# It installs required dependencies, copies the autostop script, and sets up the cron job.

# Define the base directory where the scripts are located
BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup/autostop"

# Load configuration from file
CONFIG_FILE="$BASE_DIR/autostop_config.env"
if [ -f "$CONFIG_FILE" ]; then
	echo "Loading configuration from $CONFIG_FILE"
	set -a # Automatically export all variables
	# shellcheck source=/dev/null
	if ! . "$CONFIG_FILE"; then
		echo "Error loading configuration file"
		exit 1
	fi

	# Validate required variables
	required_vars=(
		"AWS_REGION" "TIMEZONE" "START_HOUR" "START_MINUTE"
		"END_HOUR" "END_MINUTE" "IDLE_TIME" "CRON_FREQUENCY"
		"ACTIVE_DAYS" "CPU_THRESHOLD" "CPU_CHECK_DURATION"
		"IGNORE_CONNECTIONS"
	)

	for var in "${required_vars[@]}"; do
		if [ -z "${!var:-}" ]; then
			echo "Required variable $var is not set in config file"
			exit 1
		fi
	done
	set +a
else
	echo "Configuration file $CONFIG_FILE not found. Exiting."
	exit 1
fi

# Maximum number of retries for operations
MAX_RETRIES=3

# Function to retry operations
retry_operation() {
	local cmd="$1"
	local retry=0

	while [ $retry -lt $MAX_RETRIES ]; do
		if eval "$cmd"; then
			return 0
		fi
		retry=$((retry + 1))
		echo "Command failed, attempt $retry of $MAX_RETRIES"
		sleep $((retry * 2))
	done
	return 1
}

# Function to check system services with retries
check_system_services() {
	echo "🔍 Checking system services..."
	required_services=("nginx" "code-server")
	max_retries=3
	retry_delay=5

	for service in "${required_services[@]}"; do
		retries=0
		while [ $retries -lt $max_retries ]; do
			if systemctl is-active --quiet "$service"; then
				break
			fi
			retries=$((retries + 1))
			if [ $retries -eq $max_retries ]; then
				echo "❌ Error: $service is not running after $max_retries attempts"
				return 1
			fi
			echo "⚠️ Service $service not running, attempt $retries of $max_retries"
			echo "Attempting to start $service..."
			sudo systemctl start "$service"
			sleep $retry_delay
		done
	done
	echo "✅ All required services are running"
	return 0
}

# Function to install missing dependencies
install_dependencies() {
	echo "📦 Checking and installing dependencies..."

	# Ensure Python 3 is installed
	if ! command -v python3 &>/dev/null; then
		echo "Python3 not found. Installing..."
		sudo yum install -y python3 || {
			echo "Failed to install python3"
			exit 1
		}
	fi

	# Ensure pip3 is installed
	if ! command -v pip3 &>/dev/null; then
		echo "pip3 not found. Installing..."
		sudo python3 -m ensurepip || sudo yum install -y python3-pip || {
			echo "Failed to install pip3"
			exit 1
		}
	fi

	# Ensure required Python packages are installed
	required_packages="boto3 requests urllib3 psutil pytz"
	for package in $required_packages; do
		if ! python3 -c "import $package" &>/dev/null; then
			echo "Installing $package..."
			if ! sudo pip3 install "$package"; then
				echo "Failed to install $package"
				exit 1
			fi
		fi
	done

	echo "All dependencies are installed."
}

# Function to copy the autostop script to /usr/local/bin
copy_autostop_script() {
	echo "Copying autostop.py to /usr/local/bin..."
	sudo cp "$BASE_DIR/autostop.py" /usr/local/bin/autostop.py
	sudo chmod +x /usr/local/bin/autostop.py
}

# Validate numeric environment variables
validate_numeric_vars() {
	local vars=("START_HOUR" "END_HOUR" "START_MINUTE" "END_MINUTE" "IDLE_TIME" "CPU_THRESHOLD" "CPU_CHECK_DURATION")
	for var in "${vars[@]}"; do
		if ! [[ ${!var} =~ ^[0-9]+$ ]]; then
			echo "Error: $var must be a number"
			return 1
		fi
	done

	# Validate hour and minute ranges
	if [ "$START_HOUR" -gt 23 ] || [ "$END_HOUR" -gt 23 ]; then
		echo "Error: Hours must be between 0 and 23"
		return 1
	fi
	if [ "$START_MINUTE" -gt 59 ] || [ "$END_MINUTE" -gt 59 ]; then
		echo "Error: Minutes must be between 0 and 59"
		return 1
	fi
	return 0
}

# Function to set up the cron job for the autostop script
setup_cron_job() {
	echo "⏰ Setting up the autostop script in cron..."

	# Validate numeric variables before proceeding
	if ! validate_numeric_vars; then
		echo "Failed to validate configuration variables"
		exit 1
	fi

	# Remove existing autostop entries to avoid duplicates
	(crontab -l | grep -v 'autostop.py' || true) | crontab -

	# Prepare the cron job command
	CRON_COMMAND="$CRON_FREQUENCY python3 /usr/local/bin/autostop.py \
    --time $IDLE_TIME \
    --start $START_HOUR --end $END_HOUR \
    --start-min $START_MINUTE --end-min $END_MINUTE \
    --timezone '$TIMEZONE' --active-days ${ACTIVE_DAYS[*]} \
    --cpu-threshold $CPU_THRESHOLD --cpu-check-duration $CPU_CHECK_DURATION"

	# Add the ignore-connections flag if set
	if [ "$IGNORE_CONNECTIONS" = true ]; then
		CRON_COMMAND="$CRON_COMMAND --ignore-connections"
	fi

	# Redirect output to log file
	CRON_COMMAND="$CRON_COMMAND >> /var/log/autostop.log 2>&1"

	# Add the new cron job
	(
		crontab -l 2>/dev/null
		echo "$CRON_COMMAND"
	) | crontab -

	echo "Cron job added successfully."
}

# MAIN EXECUTION
main() {
	# Step 1: Check system services
	check_system_services || {
		echo "❌ Critical services are not running"
		exit 1
	}

	# Step 2: Install necessary dependencies
	install_dependencies

	# Step 2: Copy the autostop script to /usr/local/bin
	copy_autostop_script

	# Step 3: Set up the cron job with the configured parameters
	setup_cron_job

	# Set up health check cron job
	echo "Setting up health check monitoring..."
	(crontab -l 2>/dev/null | grep -v 'healthcheck.sh' || true) | crontab -
	(
		crontab -l 2>/dev/null
		echo "*/5 * * * * /home/ec2-user/SageMaker/my-sagemaker-setup/healthcheck.sh >> /var/log/healthcheck.log 2>&1"
	) | crontab -

	echo "Autostop setup completed."
}

# Call the main function to execute the script logic
main
