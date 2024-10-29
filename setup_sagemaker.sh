#!/bin/bash
set -euo pipefail

# Script Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/setup_sagemaker.log"
CONFIG_FILE="${SCRIPT_DIR}/defaults.env"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
VALID_INSTANCE_TYPES=("ml.t2.medium" "ml.t2.large" "ml.t3.medium" "ml.t3.large" "ml.m5.large")

# Logging function
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
error() {
	log "ERROR: $*"
	exit 1
}

# Load configuration from file
load_config() {
	if [[ -f $CONFIG_FILE ]]; then
		log "Loading configuration from $CONFIG_FILE..."
		# shellcheck source=/dev/null
		source "$CONFIG_FILE"
	else
		log "No config file found, proceeding with defaults."
	fi
}

# Ask for confirmation
confirm_input() {
	local prompt="$1"
	local default_value="$2"
	read -r -p "$prompt [$default_value]: " input
	echo "${input:-$default_value}"
}

# Validate commands
check_required_commands() {
	for cmd in aws terraform; do
		command -v "$cmd" >/dev/null || error "'$cmd' is required"
	done
}

# Validate instance type
validate_instance_type() {
	local instance_type="$1"
	[[ " ${VALID_INSTANCE_TYPES[*]} " == *" $instance_type "* ]] || error "Invalid instance type: $instance_type"
}

# Fetch VPC and Subnet
fetch_vpc_and_subnet() {
	log "Fetching VPCs and Subnets..."
	VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)
	SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text)
}

# Save Terraform configuration
save_terraform_config() {
	log "Saving Terraform configuration..."
	mkdir -p "$TERRAFORM_DIR"
	cat >"$TERRAFORM_DIR/terraform.tfvars" <<EOF
vpc_id        = "$VPC_ID"
subnet_id     = "$SUBNET_ID"
aws_profile   = "$AWS_PROFILE"
aws_region    = "$AWS_REGION"
instance_type = "$INSTANCE_TYPE"
volume_size   = $VOLUME_SIZE
instance_name = "$INSTANCE_NAME"
EOF
}

# Main function
main() {
	log "Starting SageMaker setup..."

	check_required_commands
	load_config

	# Get user input with default values and validation
	AWS_PROFILE=$(confirm_input "Enter AWS profile" "${AWS_PROFILE:-default}")
	AWS_REGION=$(confirm_input "Enter AWS region" "${AWS_REGION:-us-west-2}")
	INSTANCE_TYPE=$(confirm_input "Enter instance type" "${INSTANCE_TYPE:-ml.t3.large}")
	validate_instance_type "$INSTANCE_TYPE"
	VOLUME_SIZE=$(confirm_input "Enter volume size in GB" "${VOLUME_SIZE:-20}")
	INSTANCE_NAME=$(confirm_input "Enter instance name" "${INSTANCE_NAME:-sagemaker-instance}")

	fetch_vpc_and_subnet
	save_terraform_config

	log "Running Terraform..."
	cd "$TERRAFORM_DIR"
	terraform init -input=false
	terraform apply -auto-approve -input=false

	log "Setup completed."
}

main "$@"
