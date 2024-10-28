import logging
import os
from pathlib import Path
from typing import Dict, List, Optional

import boto3
from botocore.exceptions import ClientError

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_script_dir() -> Path:
    """
    Get absolute path to the directory containing this script.

    Returns:
        Path object for the script's directory
    """
    return Path(os.path.dirname(os.path.abspath(__file__)))

def ensure_directory_exists(path: str | Path) -> Path:
    """
    Ensure the directory exists, create it if it doesn't.

    Args:
        path: Path to check/create (will be converted to absolute)

    Returns:
        Path object with absolute path that was created
    """
    abs_path = Path(path).resolve()
    abs_path.parent.mkdir(parents=True, exist_ok=True)
    return abs_path

def list_all_vpcs(region_name: str = "us-west-2",
                  profile_name: Optional[str] = None) -> List[Dict]:
    """
    List all VPCs in the specified region using pagination.

    Args:
        region_name: AWS region name
        profile_name: AWS profile name to use

    Returns:
        List of VPC dictionaries containing VPC information

    Raises:
        ClientError: If AWS API call fails
    """
    try:
        session = boto3.Session(profile_name=profile_name)
        ec2_client = session.client("ec2", region_name=region_name)

        paginator = ec2_client.get_paginator("describe_vpcs")
        page_iterator = paginator.paginate()

        all_vpcs = []
        for page in page_iterator:
            all_vpcs.extend(page["Vpcs"])

        return all_vpcs

    except ClientError as e:
        logger.error(f"Failed to list VPCs: {str(e)}")
        raise

def main() -> None:
    """Main function to demonstrate VPC listing functionality."""
    try:
        vpcs = list_all_vpcs()
        for vpc in vpcs:
            logger.info(f"VPC ID: {vpc['VpcId']}")
            logger.info(f"State: {vpc['State']}")
            logger.info(f"CIDR: {vpc['CidrBlock']}")
            if "Tags" in vpc:
                for tag in vpc["Tags"]:
                    if tag["Key"] == "Name":
                        logger.info(f"Name: {tag['Value']}")
            logger.info("-" * 40)

    except Exception as e:
        logger.error(f"Error in main: {str(e)}")
        raise

if __name__ == "__main__":
    main()
