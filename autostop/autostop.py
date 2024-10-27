#!/usr/bin/env python3

import argparse
import json
import logging
import os
import socket
import sys
import time
from datetime import datetime

# Check if running in virtualenv
if not hasattr(sys, "real_prefix") and not (hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix):
    print("This script should be run within its virtual environment.")
    print("Please run: source venv/bin/activate")
    sys.exit(1)

try:
    import boto3
    import botocore
    import petname
    import psutil
    import pytz
    import requests
    import urllib3
except ImportError as e:
    print(f"Required package missing: {e}")
    print("Please run: pip install -r requirements.txt")
    sys.exit(1)

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def generate_instance_name() -> str:
    """Generate a unique, human-readable name for the instance.

    Returns:
        str: A randomly generated three-word name separated by hyphens
    """
    return petname.generate(words=3, separator="-")

def load_config():
    """Load configuration from environment file."""
    config = {}
    config_file = os.path.join(os.path.dirname(__file__), "autostop_config.env")

    if os.path.exists(config_file):
        with open(config_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    config[key.strip()] = value.strip().strip('"')
    return config

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

def parse_arguments():
    """
    Parse and validate command line arguments.

    Returns:
        argparse.Namespace: Parsed command line arguments
    """
    config = load_config()
    parser = argparse.ArgumentParser(
        description="Autostop SageMaker Notebook Instance when idle."
    )
    parser.add_argument(
        "--name",
        type=str,
        help="Name for the notebook instance. If not provided, generates a random name.",
    )
    parser.add_argument(
        "--profile",
        type=str,
        default=config.get("AWS_PROFILE", "saml"),
        help="AWS profile to use for authentication.",
    )
    parser.add_argument(
        "--region",
        type=str,
        default=config.get("AWS_REGION", "eu-west-1"),
        help="AWS region for the notebook instance.",
    )
    parser.add_argument(
        "--time",
        type=int,
        default=int(config.get("IDLE_TIME", "5400")),
        help="Idle time in seconds before stopping the instance.",
    )
    parser.add_argument("--port", type=str, default="8443", help="Jupyter server port.")
    parser.add_argument(
        "--ignore-connections",
        action="store_true",
        help="Ignore active client connections.",
    )
    parser.add_argument(
        "--start", type=int, default=0, help="Hour to start the active hours (0-23)."
    )
    parser.add_argument(
        "--end", type=int, default=0, help="Hour to end the active hours (0-23)."
    )
    parser.add_argument(
        "--start-min",
        type=int,
        default=0,
        help="Minute to start the active hours (0-59).",
    )
    parser.add_argument(
        "--end-min", type=int, default=0, help="Minute to end the active hours (0-59)."
    )
    parser.add_argument(
        "--timezone",
        type=str,
        default=config.get("TIMEZONE", "UTC"),
        help="Timezone for active hours."
    )
    parser.add_argument(
        "--active-days",
        nargs="*",
        default=["1", "2", "3", "4", "5"],
        help="Active days of the week (1=Monday, 7=Sunday).",
    )
    parser.add_argument(
        "--cpu-threshold",
        type=float,
        default=None,
        help=(
            "CPU usage threshold (in percent) below which the instance is "
            "considered idle."
        ),
    )
    parser.add_argument(
        "--cpu-check-duration",
        type=int,
        default=60,
        help="Duration in seconds over which to check CPU usage.",
    )
    return parser.parse_args()


def is_within_active_hours(args):
    tz = pytz.timezone(args.timezone)
    now = datetime.now(tz)
    current_day = str(now.isoweekday())  # '1' = Monday, '7' = Sunday
    current_time_minutes = now.hour * 60 + now.minute
    start_time_minutes = args.start * 60 + args.start_min
    end_time_minutes = args.end * 60 + args.end_min

    # Check if today is within active days
    if current_day not in args.active_days:
        print(f"Today ({current_day}) is not within active days ({args.active_days}).")
        return False

    # Check if current time is within active hours
    if start_time_minutes <= current_time_minutes < end_time_minutes:
        print(f"Current time ({now.strftime('%H:%M')}) is within active hours.")
        return True
    else:
        print(f"Current time ({now.strftime('%H:%M')}) is outside active hours.")
        return False


def get_notebook_name():
    """Get the notebook instance name from metadata or EC2 tags."""
    log_path = "/opt/ml/metadata/resource-metadata.json"
    try:
        # First try SageMaker metadata
        if os.path.exists(log_path):
            with open(log_path, "r") as f:
                data = json.load(f)
                if "ResourceName" in data:
                    return data["ResourceName"]
                logging.warning("ResourceName not found in metadata")
        else:
            logging.warning(f"Metadata file not found at {log_path}")
    except Exception as e:
        logging.warning(f"Unable to get name from SageMaker metadata: {e}")
        try:
            # Fallback to EC2 metadata
            response = requests.get(
                "http://169.254.169.254/latest/meta-data/tags/instance/Name",
                timeout=2
            )
            if response.status_code == 200:
                return response.text
        except Exception as e:
            logging.error(f"Unable to get name from EC2 metadata: {e}")

        # Final fallback to hostname
        try:
            return socket.gethostname()
        except Exception as e:
            logging.error(f"Unable to get hostname: {e}")
            sys.exit(1)


def get_last_activity_time(args) -> datetime:
    """Get the timestamp of the last notebook activity.

    Args:
        args: Parsed command line arguments

    Returns:
        datetime: The timestamp of the last activity

    Raises:
        SystemExit: If unable to fetch activity time
    """
    try:
        response = requests.get(
            f"https://127.0.0.1:{args.port}/api/sessions",
            timeout=10,
            verify=False  # Already disabled warnings globally
        )
        response.raise_for_status()
        data = json.loads(response.content.decode("utf-8"))
        last_activity = None
        for notebook in data:
            if "kernel" in notebook and "last_activity" in notebook["kernel"]:
                activity = datetime.strptime(
                    notebook["kernel"]["last_activity"], "%Y-%m-%dT%H:%M:%S.%fZ"
                )
                if not last_activity or activity > last_activity:
                    last_activity = activity
        return last_activity
    except Exception as e:
        print(f"Error fetching last activity time: {e}")
        sys.exit(1)


def are_connections_active(args):
    try:
        response = requests.get(
            f"https://127.0.0.1:{args.port}/api/kernels", timeout=10
        )
        data = json.loads(response.content.decode("utf-8"))
        for kernel in data:
            if kernel.get("connections", 0) > 0:
                print(f"Active connections found: {kernel['connections']}")
                return True
        print("No active connections.")
        return False
    except Exception as e:
        print(f"Error checking active connections: {e}")
        sys.exit(1)


def is_cpu_idle(threshold, check_duration):
    print(f"Checking CPU usage over {check_duration} seconds...")
    cpu_usage_samples = []
    interval = 5  # seconds
    total_samples = max(1, check_duration // interval)
    for _ in range(total_samples):
        usage = psutil.cpu_percent(interval=None)
        cpu_usage_samples.append(usage)
        print(f"CPU usage: {usage}%")
        time.sleep(interval)
    average_cpu = sum(cpu_usage_samples) / len(cpu_usage_samples)
    print(f"Average CPU usage over {check_duration} seconds: {average_cpu}%")
    return average_cpu < threshold


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


def setup_logging():
    """Configure logging with timestamps and levels from config."""
    config = load_config()
    log_level = getattr(logging, config.get("LOG_LEVEL", "INFO").upper())
    log_file = config.get("LOG_FILE", "/var/log/autostop.log")

    # Ensure log directory exists
    os.makedirs(os.path.dirname(log_file), exist_ok=True)

    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )

    # Log startup information
    logging.info("Autostop logging initialized")
    logging.debug("Log level set to: %s", log_level)

def main():
    setup_logging()
    args = parse_arguments()
    logging.info("Starting autostop with arguments: %s", vars(args))

    # Validate AWS profile early and find SageMaker roles
    if not validate_aws_profile(args.profile):
        logging.error("Failed to validate AWS profile. Exiting.")
        sys.exit(1)

    # Find and display available SageMaker roles
    sagemaker_roles = find_sagemaker_roles(args.profile)
    if sagemaker_roles:
        logging.info("Found SageMaker roles:")
        for role in sagemaker_roles:
            logging.info(f"  - {role}")
    else:
        logging.warning("No SageMaker roles found in account")

    # Generate instance name if not provided
    if not args.name:
        args.name = generate_instance_name()
        print(f"Generated instance name: {args.name}")

    # Check if within active hours
    if is_within_active_hours(args):
        print("Notebook is within active hours. Skipping shutdown.")
        sys.exit(0)
    else:
        print("Notebook is outside active hours. Proceeding with idle check.")

    # Check CPU usage if CPU threshold is set
    if args.cpu_threshold is not None:
        if is_cpu_idle(args.cpu_threshold, args.cpu_check_duration):
            print(f"CPU usage is below threshold ({args.cpu_threshold}%).")
        else:
            print(
                f"CPU usage is above threshold ({args.cpu_threshold}%). "
                "Notebook is active."
            )
            sys.exit(0)
    else:
        print("No CPU threshold set. Skipping CPU usage check.")

    last_activity = get_last_activity_time(args)
    if not last_activity:
        print("No activity detected. Considering as idle.")
        idle_time = args.time + 1  # Ensure it's greater than the threshold
    else:
        idle_time = (datetime.utcnow() - last_activity).total_seconds()
        print(f"Last activity was {idle_time} seconds ago.")

    if idle_time > args.time:
        print(
            f"Notebook has been idle for {idle_time} seconds, exceeding the "
            f"threshold of {args.time} seconds."
        )
        if args.ignore_connections or not are_connections_active(args):
            notebook_instance_name = get_notebook_name()
            stop_notebook_instance(notebook_instance_name, args.region, args.profile)
        else:
            print("Active connections detected. Notebook will not be stopped.")
    else:
        print("Notebook is not idle based on activity. No action required.")


if __name__ == "__main__":
    main()
