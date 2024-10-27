#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

# Function to get value with fallback to environment variable and default
get_value() {
	local prompt="$1"
	local env_var="$2"
	local default="$3"

	# First check environment variable
	local value
	eval "value=\${$env_var:-}"

	# If not set in environment, prompt user with default
	if [ -z "$value" ]; then
		read -r -p "🔹 $prompt [$default]: " value
		value="${value:-$default}"
	fi

	echo "$value"
}

# Load default configuration
source config/defaults.env

# Use values passed from setup.sh or fall back to defaults
AWS_PROFILE=${AWS_PROFILE:-"$AWS_PROFILE"}
INSTANCE_NAME=${INSTANCE_NAME:-"${USER_NICKNAME:-default}-notebook"}
AWS_REGION=${AWS_REGION:-"$AWS_REGION"}
INSTANCE_TYPE=${INSTANCE_TYPE:-"t3.xlarge"}
IDLE_TIME=${IDLE_TIME:-"$IDLE_TIME"}
CPU_THRESHOLD=${CPU_THRESHOLD:-"$CPU_THRESHOLD"}
START_HOUR=${START_HOUR:-"$START_HOUR"}
START_MINUTE=${START_MINUTE:-"$START_MINUTE"}
END_HOUR=${END_HOUR:-"$END_HOUR"}
END_MINUTE=${END_MINUTE:-"$END_MINUTE"}
TIMEZONE=${TIMEZONE:-"$TIMEZONE"}

# Log the configuration being used
echo "📋 SageMaker Instance Configuration"
echo "=================================="
echo "🔸 Using configuration:"
echo "Instance name: ${INSTANCE_NAME:-auto-generated}"
echo "AWS profile: $AWS_PROFILE"
echo "AWS region: $AWS_REGION"
echo "Instance type: t3.medium"
echo "Idle timeout: $IDLE_TIME seconds"
echo "CPU threshold: $CPU_THRESHOLD%"
echo "Active hours: $START_HOUR:$START_MINUTE - $END_HOUR:$END_MINUTE"
echo "Timezone: $TIMEZONE"

# Source AWS helpers
source aws_helpers.sh

# Validate AWS credentials first
if ! validate_aws_credentials "$AWS_PROFILE" "$AWS_REGION"; then
	echo "❌ Failed to validate AWS credentials. Exiting."
	exit 1
fi

# Find first available VPC
echo "🌐 Looking for available VPC"
echo "=========================="

# Get first available VPC
VPC_ID=$(aws ec2 describe-vpcs \
	--query 'Vpcs[0].VpcId' \
	--output text \
	--region "$AWS_REGION" \
	--profile "$AWS_PROFILE")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
	echo "❌ No VPCs found in region $AWS_REGION"
	echo "Please create a VPC first before running this script"
	exit 1
fi

echo "✅ Using VPC: $VPC_ID"

# Get first available subnet in the VPC
SUBNET_ID=$(aws ec2 describe-subnets \
	--filters "Name=vpc-id,Values=$VPC_ID" \
	--query 'Subnets[0].SubnetId' \
	--output text \
	--region "$AWS_REGION" \
	--profile "$AWS_PROFILE")

if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
	echo "❌ No subnet found in VPC $VPC_ID"
	exit 1
fi

echo "✅ Using subnet: $SUBNET_ID"

# Save instance-specific configuration
echo "💾 Saving configuration..."
mkdir -p config
cat >config/instance_config.env <<EOF
VPC_ID="${VPC_ID}"
SUBNET_ID="${SUBNET_ID}"
AWS_PROFILE="${AWS_PROFILE}"
AWS_REGION="${AWS_REGION}"
TIMEZONE="${TIMEZONE}"
INSTANCE_NAME="${INSTANCE_NAME}"
INSTANCE_TYPE="${INSTANCE_TYPE}"
IDLE_TIME=${IDLE_TIME}
START_HOUR=${START_HOUR}
START_MINUTE=${START_MINUTE}
END_HOUR=${END_HOUR}
END_MINUTE=${END_MINUTE}
CPU_THRESHOLD=${CPU_THRESHOLD}
CRON_FREQUENCY="${CRON_FREQUENCY}"
EOF

# Write configuration to terraform.tfvars
# Write configuration to terraform.tfvars
cat >terraform/terraform.tfvars <<EOF
vpc_id = "${VPC_ID}"
subnet_id = "${SUBNET_ID}"
instance_name = "${INSTANCE_NAME}"
aws_profile = "${AWS_PROFILE}"
aws_region = "${AWS_REGION}"
instance_type = "ml.t3.large"
idle_timeout = ${IDLE_TIME}
start_hour = ${START_HOUR}
start_minute = ${START_MINUTE}
end_hour = ${END_HOUR}
end_minute = ${END_MINUTE}
timezone = "${TIMEZONE}"
cpu_threshold = ${CPU_THRESHOLD}
EOF

echo "✅ Configuration saved to terraform/terraform.tfvars"
