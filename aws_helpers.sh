#!/bin/bash

# Ensure script has proper permissions
if [ ! -x "$0" ]; then
	echo "❌ Error: Script must be executable"
	chmod +x "$0" || {
		echo "Failed to set executable permission"
		exit 1
	}
fi

# Function to validate AWS credentials
validate_aws_credentials() {
	local profile="$1"
	local region="$2"

	echo "🔑 Validating AWS credentials..."
	if ! aws sts get-caller-identity --no-cli-pager --profile "$profile" --region "$region" >/dev/null 2>&1; then
		echo "❌ AWS credentials validation failed. Please check your credentials."
		return 1
	fi

	# Display the identity being used
	aws sts get-caller-identity --no-cli-pager --profile "$profile" --region "$region" \
		--query 'Arn' --output text || true

	echo "✅ AWS credentials validated"
	return 0
}

# Function to get available VPCs
get_vpcs() {
	local profile="$1"
	local region="$2"

	echo "📡 Querying AWS EC2 API for VPCs..."

	# shellcheck disable=SC2016
	local result
	# shellcheck disable=SC2016
	if ! result=$(aws ec2 describe-vpcs \
		--no-cli-pager \
		--no-paginate \
		--profile "$profile" \
		--region "$region" \
		--query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock]' \
		--output text 2>&1); then
		echo "❌ Failed to fetch VPCs: $result" >&2
		echo "🔍 Debug info:" >&2
		echo "  Profile: $profile" >&2
		echo "  Region: $region" >&2
		echo "  Command: aws ec2 describe-vpcs" >&2
		return 1
	fi

	if [ -z "$result" ]; then
		echo "❌ No VPCs found in region $region" >&2
		echo "💡 Please ensure:" >&2
		echo "  - You have at least one VPC in region $region" >&2
		echo "  - Your AWS credentials have EC2 read permissions" >&2
		return 1
	fi

	echo "$result"
}

# Function to get available subnets for a VPC
get_subnets() {
	local profile="$1"
	local region="$2"
	local vpc_id="$3"

	# Get only public subnets (those with a route to internet gateway)
	# shellcheck disable=SC2016
	local result
	# shellcheck disable=SC2016
	if ! result=$(aws ec2 describe-route-tables \
		--no-cli-pager \
		--no-paginate \
		--profile "$profile" \
		--region "$region" \
		--filters "Name=vpc-id,Values=$vpc_id" \
		--query 'RouteTables[?Routes[?GatewayId!=`null` && GatewayId!=`local`]].Associations[].SubnetId' \
		--output text); then
		echo "❌ Failed to fetch route tables" >&2
		return 1
	fi

	# If no public subnets found
	if [ -z "$result" ]; then
		echo "❌ No public subnets found in VPC $vpc_id" >&2
		return 1
	fi

	# Get subnet details for public subnets only
	# shellcheck disable=SC2016
	aws ec2 describe-subnets \
		--no-cli-pager \
		--no-paginate \
		--profile "$profile" \
		--region "$region" \
		--filters "Name=vpc-id,Values=$vpc_id" "Name=subnet-id,Values=$result" \
		--query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
		--output text
}

# Function to select VPC interactively
select_vpc() {
	local profile="$1"
	local region="$2"

	echo "🔍 Fetching available VPCs..."
	local vpcs
	if ! vpcs=$(get_vpcs "$profile" "$region"); then
		echo "❌ VPC query failed"
		echo "💡 Try running: aws ec2 describe-vpcs --profile $profile --region $region"
		return 1
	fi

	if [ -z "$vpcs" ]; then
		echo "❌ No VPCs found in region $region"
		echo "💡 Please ensure:"
		echo "  - You have at least one VPC in region $region"
		echo "  - Your AWS credentials are correct"
		echo "  - You have permissions to list VPCs"
		return 1
	fi

	echo "📋 Available VPCs:"
	# Use regular array instead of associative array
	declare -a vpc_ids=()
	local i=1

	# Read VPCs into array and display them
	while IFS=$'\t' read -r vpc_id name cidr || [[ -n $vpc_id ]]; do
		if [[ -n $vpc_id ]]; then
			echo "$i) VPC ID: $vpc_id ${name:+(Name: $name)} (CIDR: $cidr)"
			vpc_ids+=("$vpc_id")
			((i++))
		fi
	done <<<"$vpcs"

	local selection
	while true; do
		# Use read with a timeout to prevent hanging
		if ! read -t 300 -r -p "🔹 Select VPC (1-$((i - 1)) or 'q' to quit): " selection; then
			echo -e "\n❌ Selection timed out after 5 minutes"
			return 1
		fi

		if [[ $selection == "q" ]]; then
			echo "❌ VPC selection cancelled by user"
			return 1
		fi

		if [[ ! $selection =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge "$i" ]; then
			echo "❌ Invalid selection: $selection"
			echo "💡 Please enter a number between 1 and $((i - 1))"
			continue
		fi
		break
	done

	# Arrays are 0-based, so subtract 1 from selection
	echo "${vpc_ids[$((selection - 1))]}"
}

# Function to select subnet interactively
select_subnet() {
	local profile="$1"
	local region="$2"
	local vpc_id="$3"

	echo "🔍 Fetching available subnets for VPC $vpc_id..."
	local subnets
	subnets=$(get_subnets "$profile" "$region" "$vpc_id")

	if [ -z "$subnets" ]; then
		echo "❌ No suitable subnets found in VPC $vpc_id"
		echo "Please ensure your VPC has at least one public subnet (with route to Internet Gateway)"
		return 1
	fi

	echo "📋 Available subnets:"
	# Use regular array instead of associative array
	declare -a subnet_ids=()
	local i=1

	# Read subnets into array and display them
	while IFS=$'\t' read -r subnet_id az cidr name || [[ -n $subnet_id ]]; do
		if [[ -n $subnet_id ]]; then
			echo "$i) Subnet ID: $subnet_id (AZ: $az, CIDR: $cidr${name:+, Name: $name})"
			subnet_ids+=("$subnet_id")
			((i++))
		fi
	done <<<"$subnets"

	local selection
	while true; do
		# Use read with a timeout to prevent hanging
		if ! read -t 300 -r -p "🔹 Select subnet (1-$((i - 1)) or 'q' to quit): " selection; then
			echo -e "\n❌ Selection timed out after 5 minutes"
			return 1
		fi

		if [[ $selection == "q" ]]; then
			echo "❌ Subnet selection cancelled by user"
			return 1
		fi

		if [[ ! $selection =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge "$i" ]; then
			echo "❌ Invalid subnet selection"
			echo "💡 Please enter a number between 1 and $((i - 1))"
			continue
		fi
		break
	done

	# Arrays are 0-based, so subtract 1 from selection
	echo "${subnet_ids[$((selection - 1))]}"
}
