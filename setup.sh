#!/bin/bash
#
# SageMaker Setup Script
#
# This script automates the setup of an AWS SageMaker instance using Terraform.
# It prompts the user for configuration values, validates them, and applies
# the Terraform configuration to create the SageMaker instance.
#
# Prerequisites:
# - AWS CLI installed and configured with appropriate credentials.
# - Terraform installed.
# - The 'config/defaults.env' file with default configuration values.
# - The 'configure.sh' and 'install.sh' scripts are now merged into this script.
#
# Usage:
# Run this script from the project root directory:
#   ./setup_sagemaker.sh
#
# Options:
# - Set DEBUG=true to enable debug mode.
# - Set LOG_FILE to specify a file for logging output.
#
# Note:
# - This script logs output to a log file if LOG_FILE is specified.
#

# Exit on error, undefined vars, and pipe failures
set -euo pipefail
IFS=$'\n\t'

# Prevent concurrent execution
LOCKFILE="/tmp/$(basename "$0").lock"

if [ -e "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
	echo "Another instance of this script is already running (PID $(cat "$LOCKFILE")). Exiting."
	exit 1
fi

# Write current PID to lockfile
echo $$ >"$LOCKFILE"

# Ensure lockfile is removed on exit
trap 'rm -f "$LOCKFILE"' EXIT

# Enable debug mode (set DEBUG=true to enable)
DEBUG=${DEBUG:-false}
if [ "$DEBUG" = "true" ]; then
	set -x
fi

# Configure logging
LOG_FILE=${LOG_FILE:-./autostop.log}

log() {
	local message="$1"
	echo -e "$message" >&2 # Output to stderr instead of stdout
	if [ -n "$LOG_FILE" ]; then
		echo -e "$(date '+%Y-%m-%d %H:%M:%S') $message" >>"./autostop.log"
	fi
}

# Load default configuration
if [ ! -f config/defaults.env ]; then
	log "❌ Error: config/defaults.env not found."
	log "Please ensure that the 'config/defaults.env' file exists."
	log "You can create one based on 'config/defaults.sample.env'."
	exit 1
fi
# shellcheck disable=SC1091
source config/defaults.env

# Set default values if not set in defaults.env
AWS_PROFILE=${AWS_PROFILE:-"default"}
AWS_REGION=${AWS_REGION:-"us-east-1"}
TIMEZONE=${TIMEZONE:-"UTC"}
START_HOUR=${START_HOUR:-9}
START_MINUTE=${START_MINUTE:-0}
END_HOUR=${END_HOUR:-17}
END_MINUTE=${END_MINUTE:-0}
IDLE_TIME=${IDLE_TIME:-5400}

# Validation functions
validate_aws_profile() {
	local profile=$1
	log "🔍 Validating AWS profile..."
	if ! aws configure list-profiles | grep -qw "$profile"; then
		log "❌ AWS profile '$profile' does not exist."
		exit 1
	fi
	return 0
}

validate_aws_region() {
	local region=$1
	log "🔍 Validating AWS region..."
	if ! aws ec2 describe-regions --query "Regions[].RegionName" --output text >/dev/null 2>&1; then
		log "❌ Error: Unable to describe AWS regions. Please check your AWS credentials and network connectivity."
		return 1
	fi
	if ! aws ec2 describe-regions --query "Regions[].RegionName" --output text | grep -qw "$region"; then
		log "❌ Invalid AWS region: $region"
		return 1
	fi
	return 0
}

validate_timezone() {
	local tz=$1
	if ! [ -f "/usr/share/zoneinfo/$tz" ]; then
		log "❌ Invalid timezone: $tz"
		return 1
	fi
	return 0
}

validate_hour() {
	local hour=$1
	if ! [[ $hour =~ ^[0-9]+$ ]] || [ "$hour" -lt 0 ] || [ "$hour" -gt 23 ]; then
		log "❌ Hour must be between 0 and 23"
		return 1
	fi
	return 0
}

validate_minute() {
	local minute=$1
	if ! [[ $minute =~ ^[0-9]+$ ]] || [ "$minute" -lt 0 ] || [ "$minute" -gt 59 ]; then
		log "❌ Minute must be between 0 and 59"
		return 1
	fi
	return 0
}

validate_idle_time() {
	local idle=$1
	if ! [[ $idle =~ ^[0-9]+$ ]] || [ "$idle" -lt 300 ] || [ "$idle" -gt 86400 ]; then
		log "❌ Idle time must be between 300 and 86400 seconds (5 minutes to 24 hours)"
		return 1
	fi
	return 0
}

validate_nickname() {
	local nickname=$1
	if [[ ! $nickname =~ ^[a-zA-Z0-9-]+$ ]]; then
		log "❌ Nickname must contain only letters, numbers, and hyphens"
		return 1
	fi
	if [ ${#nickname} -gt 20 ]; then
		log "❌ Nickname must be 20 characters or less"
		return 1
	fi
	return 0
}

get_valid_input() {
	local prompt=$1
	local default=$2
	local validator=$3
	local value

	while true; do
		read -r -p "$prompt" value
		value=${value:-$default}

		if $validator "$value"; then
			echo "$value"
			return 0
		fi
		log "Please try again."
	done
}

# Get user nickname
log "👤 User Nickname Configuration"
USER_NICKNAME=$(get_valid_input "Enter your nickname (default: default): " "default" validate_nickname)

# Get user confirmation for AWS profile
log "🔑 AWS Profile Configuration"
USER_AWS_PROFILE=$(get_valid_input "Enter AWS profile (default: $AWS_PROFILE): " "$AWS_PROFILE" validate_aws_profile)

# Export AWS_PROFILE to use in AWS CLI commands
export AWS_PROFILE="$USER_AWS_PROFILE"

# Verify AWS credentials
log "🔑 Verifying AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
	log "❌ Error: AWS credentials not valid for profile '$USER_AWS_PROFILE'. Please check your AWS configuration."
	exit 1
fi
log "✅ AWS credentials verified"

# Get user confirmation for AWS region
log "🌎 AWS Region Configuration"
USER_AWS_REGION=$(get_valid_input "Enter AWS region (default: $AWS_REGION): " "$AWS_REGION" validate_aws_region)

# Get user confirmation for timezone
log "🕒 Timezone Configuration"
USER_TIMEZONE=$(get_valid_input "Enter timezone (default: $TIMEZONE): " "$TIMEZONE" validate_timezone)

# Get user confirmation for active hours
log "⏰ Active Hours Configuration"
USER_START_HOUR=$(get_valid_input "Enter start hour (24h format, default: $START_HOUR): " "$START_HOUR" validate_hour)
USER_START_MINUTE=$(get_valid_input "Enter start minute (default: $START_MINUTE): " "$START_MINUTE" validate_minute)
USER_END_HOUR=$(get_valid_input "Enter end hour (24h format, default: $END_HOUR): " "$END_HOUR" validate_hour)
USER_END_MINUTE=$(get_valid_input "Enter end minute (default: $END_MINUTE): " "$END_MINUTE" validate_minute)

# Validate that end time is after start time
start_mins=$((USER_START_HOUR * 60 + USER_START_MINUTE))
end_mins=$((USER_END_HOUR * 60 + USER_END_MINUTE))
if [ "$end_mins" -le "$start_mins" ]; then
	log "❌ Error: End time must be after start time"
	exit 1
fi

# Get user confirmation for idle time
log "🕑 Idle Time Configuration"
USER_IDLE_TIME=$(get_valid_input "Enter idle time threshold in seconds (default: $IDLE_TIME): " "$IDLE_TIME" validate_idle_time)

# Save configuration
if [ ! -d "autostop" ]; then
	log "❌ Error: 'autostop' directory not found."
	exit 1
fi

cat >autostop/autostop_config.env <<EOF
AWS_REGION=$USER_AWS_REGION
TIMEZONE=$USER_TIMEZONE
START_HOUR=$USER_START_HOUR
START_MINUTE=$USER_START_MINUTE
END_HOUR=$USER_END_HOUR
END_MINUTE=$USER_END_MINUTE
IDLE_TIME=$USER_IDLE_TIME
EOF

log "🚀 Starting SageMaker Setup..."

# Set instance name based on nickname
INSTANCE_NAME="${USER_NICKNAME}-notebook"

# Start log streaming in background
aws logs tail "/aws/sagemaker/NotebookInstances/$INSTANCE_NAME" --follow &
LOGGER_PID=$!

# Trap to kill logger on script exit
trap 'kill $LOGGER_PID 2>/dev/null' EXIT

# Check prerequisites
command -v terraform >/dev/null 2>&1 || {
	log "❌ Error: Terraform is required but not installed. Aborting."
	exit 1
}
command -v aws >/dev/null 2>&1 || {
	log "❌ Error: AWS CLI is required but not installed. Aborting."
	exit 1
}

# Check and set executable permissions for required scripts
check_script_permissions() {
	local script=$1
	if [ ! -f "$script" ]; then
		log "❌ Error: Required script not found: $script"
		exit 1
	fi

	if [ ! -x "$script" ]; then
		log "📝 Setting executable permission for $script"
		if ! chmod +x "$script"; then
			log "❌ Error: Failed to set executable permission for $script"
			exit 1
		fi
	fi
}

log "🔧 Checking script permissions..."
REQUIRED_SCRIPTS=(
	"autostop/auto_stop.sh"
	"autostop/setup_venv.sh"
	"code-server/on-create.sh"
	"code-server/on-start.sh"
	"configure.sh"
	"healthcheck.sh"
	"install.sh"
	"lifecycle_configurations/on-create.sh"
	"lifecycle_configurations/on-start.sh"
	"terraform/tf_apply.sh"
	"aws_helpers.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
	check_script_permissions "$script"
done

log "✅ All script permissions verified"

# Add nickname validation function

# Save configuration
if [ ! -d "autostop" ]; then
	log "❌ Error: 'autostop' directory not found."
	exit 1
fi

cat >autostop/autostop_config.env <<EOF
AWS_REGION=$USER_AWS_REGION
TIMEZONE=$USER_TIMEZONE
START_HOUR=$USER_START_HOUR
START_MINUTE=$USER_START_MINUTE
END_HOUR=$USER_END_HOUR
END_MINUTE=$USER_END_MINUTE
IDLE_TIME=$USER_IDLE_TIME
EOF

log "🚀 Starting SageMaker Setup..."

# Set instance name based on nickname
INSTANCE_NAME="${USER_NICKNAME}-notebook"

# Start log streaming in background
aws logs tail "/aws/sagemaker/NotebookInstances/$INSTANCE_NAME" --follow &
LOGGER_PID=$!

# Trap to kill logger on script exit
trap 'kill $LOGGER_PID 2>/dev/null' EXIT

# Check prerequisites
command -v terraform >/dev/null 2>&1 || {
	log "❌ Error: Terraform is required but not installed. Aborting."
	exit 1
}
command -v aws >/dev/null 2>&1 || {
	log "❌ Error: AWS CLI is required but not installed. Aborting."
	exit 1
}

# Check and set executable permissions for required scripts
check_script_permissions() {
	local script=$1
	if [ ! -f "$script" ]; then
		log "❌ Error: Required script not found: $script"
		exit 1
	fi

	if [ ! -x "$script" ]; then
		log "📝 Setting executable permission for $script"
		if ! chmod +x "$script"; then
			log "❌ Error: Failed to set executable permission for $script"
			exit 1
		fi
	fi
}

log "🔧 Checking script permissions..."
REQUIRED_SCRIPTS=(
	"autostop/auto_stop.sh"
	"autostop/setup_venv.sh"
	"code-server/on-create.sh"
	"code-server/on-start.sh"
	"configure.sh"
	"healthcheck.sh"
	"install.sh"
	"lifecycle_configurations/on-create.sh"
	"lifecycle_configurations/on-start.sh"
	"terraform/tf_apply.sh"
	"aws_helpers.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
	check_script_permissions "$script"
done

log "✅ All script permissions verified"

# Export collected values for configure.sh
export USER_NICKNAME="$USER_NICKNAME"
export AWS_REGION="$USER_AWS_REGION"
export TIMEZONE="$USER_TIMEZONE"
export START_HOUR="$USER_START_HOUR"
export START_MINUTE="$USER_START_MINUTE"
export END_HOUR="$USER_END_HOUR"
export END_MINUTE="$USER_END_MINUTE"
export IDLE_TIME="$USER_IDLE_TIME"

# Run configuration script with exported values
log "🔄 Running configuration script..."
if ! ./configure.sh; then
	log "❌ Configuration script failed"
	exit 1
fi

# Get and validate SageMaker role ARN
get_and_validate_role_arn() {
	local role_arn=""
	local valid=false

	# Get AWS account ID
	local account_id
	account_id=$(aws sts get-caller-identity --query Account --output text --profile "$USER_AWS_PROFILE")
	if [ -z "$account_id" ]; then
		log "❌ Failed to get AWS account ID"
		exit 1
	fi

	# List available SageMaker roles
	log "🔍 Searching for existing SageMaker roles..."
	local roles
	# shellcheck disable=SC2016
	roles=$(aws iam list-roles --profile "$USER_AWS_PROFILE" --query 'Roles[?contains(RoleName, `SageMaker`) == `true`].Arn' --output text)

	if [ -n "$roles" ]; then
		log "✅ Found existing SageMaker roles:"
		echo "$roles" | tr '\t' '\n' | while read -r role; do
			log "   $role"
		done
	else
		log "⚠️  No existing SageMaker roles found"
	fi

	# Show example with actual account number
	local example_arn="arn:aws:iam::${account_id}:role/service-role/AmazonSageMaker-ExecutionRole-YourRoleName"

	while [ "$valid" != "true" ]; do
		if [ -z "${SAGEMAKER_ROLE_ARN:-}" ]; then
			echo "Example role ARN format for your account:"
			echo "  $example_arn"
			read -r -p "🔑 Enter your SageMaker execution role ARN: " role_arn
		else
			role_arn="$SAGEMAKER_ROLE_ARN"
		fi

		# Validate ARN format
		if [[ $role_arn =~ ^arn:aws[a-z\-]*:iam::[0-9]{12}:role/[a-zA-Z_0-9+=,.@\-_/]+$ ]]; then
			# Extract role name from ARN
			role_name="${role_arn##*/}"

			# Verify role exists using AWS CLI
			if aws iam get-role --role-name "$role_name" --profile "$USER_AWS_PROFILE" >/dev/null 2>&1; then
				# Verify role has SageMaker policy
				if aws iam list-attached-role-policies --role-name "$role_name" --profile "$USER_AWS_PROFILE" | grep -q "AmazonSageMakerFullAccess"; then
					valid=true
					SAGEMAKER_ROLE_ARN="$role_arn"
				else
					log "❌ Role exists but doesn't have SageMaker permissions. The role needs AmazonSageMakerFullAccess policy."
					SAGEMAKER_ROLE_ARN=""
				fi
			else
				log "❌ Role '$role_name' not found in AWS account $account_id"
				SAGEMAKER_ROLE_ARN=""
			fi
		else
			log "❌ Invalid role ARN format. Please use the example format shown above."
			SAGEMAKER_ROLE_ARN=""
		fi
	done
}

# Get and validate role ARN
get_and_validate_role_arn

# Export the validated role ARN for terraform
export TF_VAR_sagemaker_role_arn="$SAGEMAKER_ROLE_ARN"

# Initialize and apply Terraform configuration
log "📦 Initializing Terraform..."
if [ ! -d "terraform" ]; then
	log "❌ Error: 'terraform' directory not found. Please ensure you are in the correct directory."
	exit 1
fi
cd terraform
export TF_VAR_aws_region="$USER_AWS_REGION"
export TF_VAR_aws_profile="$USER_AWS_PROFILE"
export TF_VAR_user_nickname="$USER_NICKNAME"

if [ ! -d ".terraform" ]; then
	if ! terraform init; then
		log "❌ Error: Terraform initialization failed"
		exit 1
	fi
fi

# Check for existing Terraform state
if [ -f "terraform.tfstate" ]; then
	log "⚠️  Existing Terraform state detected."
	read -r -p "Do you want to (R)eapply, (D)estroy, or (E)xit? [R/D/E]: " action
	case "$action" in
	R | r)
		log "🔄 Reapplying Terraform configuration..."
		;;
	D | d)
		log "🔥 Destroying existing Terraform resources..."
		if ! terraform destroy -auto-approve; then
			log "❌ Error: Terraform destroy failed"
			exit 1
		fi
		# Reinitialize Terraform after destroy
		if ! terraform init; then
			log "❌ Error: Terraform initialization failed"
			exit 1
		fi
		;;
	E | e)
		log "🚪 Exiting..."
		exit 0
		;;
	*)
		log "❌ Invalid option. Exiting."
		exit 1
		;;
	esac
fi

log "🚧 Applying Terraform configuration..."
if ! terraform apply -auto-approve; then
	log "❌ Error: Terraform apply failed"
	exit 1
fi

log "✅ Setup completed successfully!"
log "Check the Terraform output above for the instance details."
log "The instance will take a few minutes to be fully ready."
