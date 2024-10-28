import logging
import os
import sys

import boto3
import botocore


def validate_aws_profile(profile_name: str) -> bool:
    """
    Validate if AWS profile exists and has valid credentials.

    Args:
        profile_name: Name of the AWS profile to validate

    Returns:
        bool: True if profile is valid and has working credentials
    """
    try:
        # Check if AWS credentials file exists
        credentials_file = os.path.expanduser("~/.aws/credentials")
        if not os.path.exists(credentials_file):
            logging.error("AWS credentials file not found at ~/.aws/credentials")
            return False

        # First check if profile exists
        session = boto3.Session(profile_name=profile_name)
        credentials = session.get_credentials()
        if not credentials:
            logging.error(f"AWS profile '{profile_name}' exists but has no credentials")
            return False

        # Freeze credentials to ensure they're loaded
        frozen_credentials = credentials.get_frozen_credentials()
        if not frozen_credentials.access_key or not frozen_credentials.secret_key:
            logging.error(f"AWS profile '{profile_name}' has incomplete credentials")
            return False

        # Then verify we can actually use these credentials
        sts = session.client("sts")
        try:
            response = sts.get_caller_identity()
            logging.info(f"AWS profile '{profile_name}' validated successfully (Account: {response['Account']})")
            return True
        except botocore.exceptions.ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "Unknown")
            logging.error(f"Failed to validate credentials: {error_code} - {str(e)}")
            return False

    except botocore.exceptions.ProfileNotFound:
        logging.error(f"AWS profile '{profile_name}' not found in credentials file")
        return False
    except botocore.exceptions.ClientError as e:
        logging.error(f"AWS credentials for profile '{profile_name}' are invalid: {str(e)}")
        return False
    except Exception as e:
        logging.error(f"Unexpected error validating AWS profile '{profile_name}': {str(e)}")
        return False

def find_sagemaker_roles(profile_name: str) -> list:
    """
    Find IAM roles that have SageMaker permissions.

    Args:
        profile_name: Name of the AWS profile to use

    Returns:
        list: List of role ARNs that have SageMaker permissions
    """
    try:
        session = boto3.Session(profile_name=profile_name)
        iam = session.client("iam")

        # Get all roles
        roles = []
        paginator = iam.get_paginator("list_roles")
        for page in paginator.paginate():
            roles.extend(page["Roles"])

        # Filter roles with SageMaker permissions
        sagemaker_roles = []
        required_policies = ["AmazonSageMakerFullAccess"]

        for role in roles:
            try:
                role_name = role["RoleName"]
                attached_policies = iam.list_attached_role_policies(RoleName=role_name)

                # Check for required policies
                has_required_policies = False
                for policy in attached_policies["AttachedPolicies"]:
                    if any(req_policy in policy["PolicyName"] for req_policy in required_policies):
                        has_required_policies = True
                        break

                if has_required_policies:
                    # Validate ARN format
                    arn = role["Arn"]
                    if not arn.startswith("arn:aws:iam::") or ":role/" not in arn:
                        logging.warning(f"Invalid ARN format for role {role_name}: {arn}")
                        continue

                    # Try to get the role to verify it exists and is accessible
                    iam.get_role(RoleName=role_name)

                    sagemaker_roles.append(arn)
                    logging.info(f"Found valid SageMaker role: {arn}")

            except botocore.exceptions.ClientError as e:
                error_code = e.response.get("Error", {}).get("Code", "Unknown")
                logging.warning(f"Error checking role {role.get('RoleName', 'unknown')}: {error_code}")
                continue

        if not sagemaker_roles:
            logging.warning("No roles found with SageMaker permissions")

        return sagemaker_roles

    except Exception as e:
        logging.error(f"Error finding SageMaker roles: {str(e)}")
        return []
def stop_notebook_instance(notebook_instance_name, region, profile):
    logging.info(f"Attempting to stop notebook instance: {notebook_instance_name} in region {region} using profile {profile}")

    if not validate_aws_profile(profile):
        logging.error(f"Cannot proceed - AWS profile '{profile}' validation failed")
        sys.exit(1)

    try:
        session = boto3.Session(profile_name=profile)
        client = session.client("sagemaker", region_name=region)
        client.stop_notebook_instance(NotebookInstanceName=notebook_instance_name)
        logging.info(f"Successfully initiated shutdown of notebook instance: {notebook_instance_name}")
    except botocore.exceptions.ClientError as e:
        logging.error(f"AWS API error stopping notebook instance: {str(e)}")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Unexpected error stopping notebook instance: {str(e)}")
        sys.exit(1)
