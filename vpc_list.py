import boto3


def list_all_vpcs(region_name="us-west-2", profile_name=None):
    """
    List all VPCs in the specified region using pagination
    """
    session = boto3.Session(profile_name=profile_name)
    ec2_client = session.client("ec2", region_name=region_name)

    # Create a paginator for the describe_vpcs operation
    paginator = ec2_client.get_paginator("describe_vpcs")

    # Create a PageIterator from the Paginator
    page_iterator = paginator.paginate()

    all_vpcs = []

    # Iterate through each page of results
    for page in page_iterator:
        all_vpcs.extend(page["Vpcs"])

    return all_vpcs

def main():
    # Example usage
    vpcs = list_all_vpcs()
    for vpc in vpcs:
        print(f"VPC ID: {vpc['VpcId']}")
        print(f"State: {vpc['State']}")
        print(f"CIDR: {vpc['CidrBlock']}")
        if "Tags" in vpc:
            for tag in vpc["Tags"]:
                if tag["Key"] == "Name":
                    print(f"Name: {tag['Value']}")
        print("-" * 40)

if __name__ == "__main__":
    main()
