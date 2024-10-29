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
	# Ensure AWS CLI is using correct profile and region
	export AWS_PROFILE
	export AWS_REGION

	log "Fetching available VPCs..."

	# Get list of VPCs with their names and CIDR blocks
	vpc_list=$(aws ec2 describe-vpcs --query 'Vpcs[].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output text)

	if [ -z "$vpc_list" ]; then
		error "No VPCs found in region $AWS_REGION"
	fi

	echo "Available VPCs:"
	echo "$vpc_list" | nl

	# Ask user to select a VPC
	read -r -p "Select VPC number from the list above: " vpc_num

	# Get the selected VPC ID
	VPC_ID=$(echo "$vpc_list" | sed -n "${vpc_num}p" | awk '{print $1}')

	if [ -z "$VPC_ID" ]; then
		error "Invalid VPC selection"
	fi

	log "Selected VPC: $VPC_ID"

	# Get available subnets for the selected VPC
	subnet_list=$(aws ec2 describe-subnets \
		--filters "Name=vpc-id,Values=$VPC_ID" \
		--query 'Subnets[].[SubnetId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
		--output text)

	if [ -z "$subnet_list" ]; then
		error "No subnets found in VPC $VPC_ID"
	fi

	echo "Available Subnets:"
	echo "$subnet_list" | nl

	# Ask user to select a subnet
	read -r -p "Select subnet number from the list above: " subnet_num

	# Get the selected subnet ID
	SUBNET_ID=$(echo "$subnet_list" | sed -n "${subnet_num}p" | awk '{print $1}')

	if [ -z "$SUBNET_ID" ]; then
		error "Invalid subnet selection"
	fi

	log "Selected Subnet: $SUBNET_ID"
}

# Get SageMaker IAM role from user
get_sagemaker_role() {
	log "Fetching available IAM roles..."

	# Get list of roles that have SageMaker policies attached
	role_list=$(aws iam list-roles --query 'Roles[?contains(AssumeRolePolicyDocument.Statement[].Principal.Service, `sagemaker.amazonaws.com`)].[RoleName,Arn]' --output text)

	if [ -z "$role_list" ]; then
		error "No suitable SageMaker roles found. Please create a role with SageMaker trust relationship first."
	fi

	echo "Available SageMaker roles:"
	echo "$role_list" | nl

	while true; do
		read -r -p "Select role number from the list above (or paste a full role ARN): " role_input

		if [[ $role_input =~ ^[0-9]+$ ]]; then
			# User selected a number from the list
			SAGEMAKER_ROLE_ARN=$(echo "$role_list" | sed -n "${role_input}p" | awk '{print $2}')
		else
			# User pasted a role ARN
			SAGEMAKER_ROLE_ARN="$role_input"
		fi

		# Validate role ARN format and existence
		if [[ $SAGEMAKER_ROLE_ARN =~ ^arn:aws[a-z\-]*:iam::[0-9]{12}:role/[a-zA-Z_0-9+=,.@\-_/]+$ ]]; then
			if aws iam get-role --role-name "${SAGEMAKER_ROLE_ARN##*/}" >/dev/null 2>&1; then
				log "Using role: $SAGEMAKER_ROLE_ARN"
				break
			fi
		fi
		log "Invalid selection or role ARN. Please try again."
	done
}

# Save Terraform configuration
save_terraform_config() {
	log "Saving Terraform configuration..."
	mkdir -p "$TERRAFORM_DIR"
	cat >"$TERRAFORM_DIR/terraform.tfvars" <<EOF
vpc_id             = "$VPC_ID"
subnet_id          = "$SUBNET_ID"
aws_profile        = "$AWS_PROFILE"
aws_region         = "$AWS_REGION"
instance_type      = "$INSTANCE_TYPE"
volume_size        = $VOLUME_SIZE
instance_name      = "$INSTANCE_NAME"
sagemaker_role_arn = "$SAGEMAKER_ROLE_ARN"
EOF
}

# Main function
main() {
	log "Starting SageMaker setup..."

	check_required_commands
	load_config

	# Get and set AWS profile
	AWS_PROFILE=$(confirm_input "Enter AWS profile" "${AWS_PROFILE:-default}")
	export AWS_PROFILE

	# Validate and set AWS region
	while true; do
		AWS_REGION=$(confirm_input "Enter AWS region" "${AWS_REGION:-us-west-2}")
		# Remove any extra spaces and normalize format
		AWS_REGION=$(echo "$AWS_REGION" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
		if [[ $AWS_REGION =~ ^[a-z]{2}-[a-z]{4,6}-[0-9]$ ]]; then
			# Verify region exists by attempting to use it
			if aws ec2 describe-regions --region "$AWS_REGION" --query "Regions[?RegionName=='$AWS_REGION'].RegionName" --output text >/dev/null 2>&1; then
				break
			fi
		fi
		log "Invalid region format or region does not exist. Please use format like 'us-west-2' or 'eu-west-1'"
	done
	INSTANCE_TYPE=$(confirm_input "Enter instance type" "${INSTANCE_TYPE:-ml.t3.large}")
	validate_instance_type "$INSTANCE_TYPE"
	VOLUME_SIZE=$(confirm_input "Enter volume size in GB" "${VOLUME_SIZE:-20}")
	INSTANCE_NAME=$(confirm_input "Enter instance name" "${INSTANCE_NAME:-sagemaker-instance}")

	fetch_vpc_and_subnet
	get_sagemaker_role
	save_terraform_config

	log "Running Terraform..."
	cd "$TERRAFORM_DIR"
	terraform init -input=false
	terraform apply -auto-approve -input=false

	log "Setup completed."
}

main "$@"
