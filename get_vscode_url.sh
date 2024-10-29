#!/bin/bash

# Check if AWS credentials are valid
if ! aws sts get-caller-identity --profile saml >/dev/null 2>&1; then
	echo "AWS credentials are expired or invalid."
	echo "Please authenticate using: saml2aws login"
	exit 1
fi

# Get and display numbered list of instances
echo "Available SageMaker notebook instances:"
readarray -t INSTANCES < <(aws sagemaker list-notebook-instances --profile saml --query "NotebookInstances[*].NotebookInstanceName" --output text)

if [ ${#INSTANCES[@]} -eq 0 ]; then
	echo "No instances found."
	exit 1
fi

for i in "${!INSTANCES[@]}"; do
	echo "$((i + 1)). ${INSTANCES[$i]}"
done

# Prompt user to select instance by number
echo -n "Enter the number of the instance (1-${#INSTANCES[@]}): "
read -r SELECTION

if ! [[ $SELECTION =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#INSTANCES[@]} ]; then
	echo "Invalid selection. Please enter a number between 1 and ${#INSTANCES[@]}"
	exit 1
fi

# Get selected instance name
INSTANCE_NAME="${INSTANCES[$((SELECTION - 1))]}"

# Get the URL for the selected instance and add https://
NOTEBOOK_URL="https://$(aws sagemaker describe-notebook-instance --profile saml --notebook-instance-name "$INSTANCE_NAME" --query "Url" --output text)"

# Output the result
echo "The URL for the selected notebook instance ($INSTANCE_NAME) is: $NOTEBOOK_URL"
