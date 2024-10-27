#!/bin/bash
set -euo pipefail

# Configure logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Set proper permissions for Terraform files
echo "Setting proper file permissions..."
chmod 644 ./*.tf ./*.tfvars 2>/dev/null || true
chmod 755 ./tf_apply.sh 2>/dev/null || true

# Verify permissions
check_permissions() {
	local file=$1
	local expected_perms=$2
	local actual_perms=$(stat -f "%Lp" "$file")

	if [ "$actual_perms" != "$expected_perms" ]; then
		log_warning "Incorrect permissions on $file: $actual_perms (expected $expected_perms)"
		return 1
	fi
	return 0
}

# Check all .tf and .tfvars files
for file in ./*.tf ./*.tfvars; do
	if [ -f "$file" ]; then
		check_permissions "$file" "644" || chmod 644 "$file"
	fi
done

# Check script permissions
check_permissions "./tf_apply.sh" "755" || chmod 755 "./tf_apply.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_error() {
	echo -e "${RED}ERROR: $1${NC}" >&2
}

log_success() {
	echo -e "${GREEN}SUCCESS: $1${NC}"
}

log_warning() {
	echo -e "${YELLOW}WARNING: $1${NC}"
}

# Function to check if command exists
check_command() {
	if ! command -v "$1" &>/dev/null; then
		log_error "Required command '$1' not found. Please install it first."
		exit 1
	fi
}

# Check for terraform installation
check_command terraform

# Initialize Terraform
echo "Initializing Terraform..."
if ! terraform init; then
	log_error "Terraform initialization failed"
	log_error "Please check your provider configuration and credentials"
	exit 1
fi
log_success "Terraform initialized successfully"

# Validate Terraform configuration
echo "Validating Terraform configuration..."
if ! terraform validate; then
	log_error "Terraform validation failed"
	log_error "Please check your configuration files for syntax errors"
	exit 1
fi
log_success "Terraform configuration is valid"

# Run Terraform plan
echo "Running Terraform plan..."
if ! terraform plan -out=tfplan; then
	log_error "Terraform plan failed"
	log_error "Please review the error messages above"
	exit 1
fi
log_success "Terraform plan created successfully"

# Prompt for confirmation
read -p "Do you want to apply these changes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	echo "Applying Terraform changes..."
	if ! terraform apply tfplan; then
		log_error "Terraform apply failed"
		log_error "Please review the error messages above"
		rm -f tfplan
		exit 1
	fi
	log_success "Terraform changes applied successfully"
	rm -f tfplan
else
	log_warning "Operation cancelled by user"
	rm -f tfplan
	exit 0
fi
