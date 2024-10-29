#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Script Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/setup_sagemaker.log"
readonly CONFIG_DIR="${SCRIPT_DIR}/config"
readonly TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
readonly VALID_INSTANCE_TYPES=("ml.t3.medium" "ml.t3.large" "ml.t3.xlarge" "ml.t3.2xlarge" "ml.m5.large" "ml.m5.xlarge" "ml.m5.2xlarge" "ml.c5.large" "ml.c5.xlarge" "ml.c5.2xlarge")

# Initialize logging
mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"
# Initialize logging to both console and file
exec > >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}")

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Error logging and exit
error() {
    log "❌ ERROR: $*"
    exit 1
}

# Validate required tools
check_required_commands() {
    log "🔍 Checking for required tools..."
    for cmd in aws jq terraform; do
        if ! command -v "$cmd" &>/dev/null; then
            error "❌ Required command '$cmd' not found. Please install it before proceeding."
        fi
    done
    log "✅ All required tools are installed."
}

# Validate AWS credentials
validate_aws_credentials() {
    log "🔑 Validating AWS credentials..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "❌ Invalid AWS credentials for profile: $AWS_PROFILE"
    fi
    log "✅ AWS credentials validated successfully."
}

# Function to handle user input with validation
get_valid_input() {
    local prompt="$1"
    local default="$2"
    local validation_func="${3:-}"
    local value

    while true; do
        read -r -p "$prompt [$default]: " value
        value="${value:-$default}"

        # Skip validation for empty input when it matches default
        if [[ -z "$value" && -n "$default" ]]; then
            echo "$default"
            return 0
        fi

        # If no validation function provided or validation passes
        if [[ -z "${validation_func:-}" ]] || { type "$validation_func" &>/dev/null && "$validation_func" "$value"; }; then
            echo "$value"
            return 0
        fi
    done
}

# Validation for AWS profile
validate_aws_profile() {
    local profile="$1"
    local profiles

    if [ "$profile" = "q" ] || [ "$profile" = "quit" ]; then
        log "👋 Setup cancelled by user."
        exit 0
    fi

    profiles=$(aws configure list-profiles 2>/dev/null)
    if [[ -z "$profiles" ]]; then
        log "⚠️ No AWS profiles found. Please configure AWS credentials first."
        return 1
    fi

    if aws configure list --profile "$profile" &>/dev/null; then
        return 0
    else
        log "❌ Invalid profile '$profile'. Available profiles:"
        echo "$profiles" | sed 's/^/- /' >&2
        return 1
    fi
}

# Validate AWS region
validate_aws_region() {
    local region="$1"
    aws ec2 describe-regions --query "Regions[?RegionName=='$region'].RegionName" --output text | grep -q "$region"
}

# Validate SageMaker instance type
validate_instance_type() {
    local instance_type="$1"
    # Don't show options if empty (first prompt)
    if [[ -z "$instance_type" ]]; then
        return 1
    fi
    # Remove any leading/trailing whitespace
    instance_type=$(echo "$instance_type" | xargs)
    if printf '%s\n' "${VALID_INSTANCE_TYPES[@]}" | grep -Fxq "$instance_type"; then
        return 0
    else
        echo "Invalid instance type. Valid options are:" >&2
        printf '%s\n' "${VALID_INSTANCE_TYPES[@]}" | sed 's/^/- /' >&2
        return 1
    fi
}

# Validate timezone (UTC or UTC±H format)
validate_timezone() {
    local tz="$1"
    [[ $tz =~ ^UTC([+-][0-9]{1,2})?$ ]]
}

# Validate hour (24-hour format)
validate_hour() {
    [[ $1 =~ ^([01]?[0-9]|2[0-3])$ ]]
}

# Validate minute (0-59)
validate_minute() {
    [[ $1 =~ ^([0-5]?[0-9])$ ]]
}

# Load configuration from defaults
load_config() {
    log "📄 Loading configuration..."
    if [[ -f "${CONFIG_DIR}/defaults.env" ]]; then
        # shellcheck disable=SC1090
        source "${CONFIG_DIR}/defaults.env"
        log "✅ Configuration loaded successfully."
    else
        error "❌ Configuration file '${CONFIG_DIR}/defaults.env' not found."
    fi
}

# Fetch available VPC and Subnet
fetch_vpc_and_subnet() {
    log "🔍 Finding available VPC and Subnet..."
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=state,Values=available" --query 'Vpcs[0].VpcId' --output text) || error "❌ Failed to query VPCs."
    [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]] && error "⚠️ No available VPC found."

    SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --query 'Subnets[0].SubnetId' --output text) || error "❌ Failed to query Subnets."
    [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]] && error "⚠️ No available Subnet found."
    
    log "✅ Found VPC: $VPC_ID, Subnet: $SUBNET_ID"
}

# Save Terraform configuration to file
save_terraform_config() {
    log "📄 Saving Terraform configuration..."
    local tfvars_file="${TERRAFORM_DIR}/terraform.tfvars"
    
    mkdir -p "${TERRAFORM_DIR}"
    cat >"${tfvars_file}" <<EOF
vpc_id         = "${VPC_ID}"
subnet_id      = "${SUBNET_ID}"
aws_profile    = "${AWS_PROFILE}"
aws_region     = "${AWS_REGION}"
instance_name  = "${USER_NICKNAME:-default}-notebook"
instance_type  = "${INSTANCE_TYPE}"
idle_timeout   = ${IDLE_TIME}
start_hour     = ${START_HOUR}
start_minute   = ${START_MINUTE}
end_hour       = ${END_HOUR}
end_minute     = ${END_MINUTE}
timezone       = "${TIMEZONE}"
EOF
    log "✅ Terraform configuration saved to ${tfvars_file}"
}

# Run Terraform
run_terraform() {
    log "🚀 Initializing and applying Terraform..."
    cd "${TERRAFORM_DIR}" || error "❌ Failed to change to Terraform directory."

    terraform init || error "❌ Terraform initialization failed."
    terraform apply -auto-approve || error "❌ Terraform apply failed."

    log "✅ SageMaker instance setup completed successfully!"
}

# Main script
main() {
    log "📋 Starting SageMaker setup..."
    check_required_commands
    load_config

    # Get user input with validation
    # Set defaults if not already set
    AWS_PROFILE=${AWS_PROFILE:-"default"}
    AWS_REGION=${AWS_REGION:-"us-east-1"}
    INSTANCE_TYPE=${INSTANCE_TYPE:-"ml.t3.large"}
    TIMEZONE=${TIMEZONE:-"UTC"}
    START_HOUR=${START_HOUR:-"9"}
    START_MINUTE=${START_MINUTE:-"0"}
    END_HOUR=${END_HOUR:-"17"}
    END_MINUTE=${END_MINUTE:-"0"}
    IDLE_TIME=${IDLE_TIME:-"3600"}
    USER_NICKNAME=${USER_NICKNAME:-"$(whoami)"}

    # Get user input with validation
    AWS_PROFILE=$(get_valid_input "Enter AWS profile" "$AWS_PROFILE" validate_aws_profile)
    AWS_REGION=$(get_valid_input "Enter AWS region" "$AWS_REGION" validate_aws_region)
    INSTANCE_TYPE=$(get_valid_input "Enter SageMaker instance type" "$INSTANCE_TYPE" validate_instance_type)
    TIMEZONE=$(get_valid_input "Enter Timezone" "$TIMEZONE" validate_timezone)
    START_HOUR=$(get_valid_input "Enter start hour (24h format)" "$START_HOUR" validate_hour)
    START_MINUTE=$(get_valid_input "Enter start minute" "$START_MINUTE" validate_minute)
    END_HOUR=$(get_valid_input "Enter end hour (24h format)" "$END_HOUR" validate_hour)
    END_MINUTE=$(get_valid_input "Enter end minute" "$END_MINUTE" validate_minute)
    IDLE_TIME=$(get_valid_input "Enter idle time in seconds" "$IDLE_TIME")

    log "🔧 Using AWS profile: $AWS_PROFILE, region: $AWS_REGION, instance type: $INSTANCE_TYPE"
    
    validate_aws_credentials
    fetch_vpc_and_subnet
    save_terraform_config
    run_terraform

    log "📜 Setup log available at: ${LOG_FILE}"
}

main "$@"
