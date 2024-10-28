# Terraform Setup for SageMaker Notebook

This directory contains the Terraform configuration files to set up an AWS SageMaker
notebook instance with autostop functionality and code-server integration.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) (v1.0.0 or later) installed
- AWS account with administrative access
- AWS CLI installed and configured
- Git (for version control)
- Basic understanding of AWS SageMaker and Terraform

Text before list.

- List item 1

## Detailed Setup Instructions

### 1. AWS Credentials Setup

```hcl
aws configure
```

Required permissions:
- AWSServiceRoleForAmazonSageMaker
- IAMFullAccess
- AmazonSageMakerFullAccess
- AmazonS3FullAccess

### 2. Repository Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd my-sagemaker-setup/terraform
   ```

2. Create a `terraform.tfvars` file:
   ```hcl
   aws_region = "eu-west-1"
   instance_type = "ml.t3.xlarge"
   instance_name = "my-notebook"
   ```

### 3. Initialize and Validate

```hcl
terraform init
terraform validate
terraform plan
```

### 4. Apply Configuration

```bash
terraform apply
```

Review the plan carefully before typing 'yes'.

### 5. Post-Installation Verification

1. Check AWS Console > SageMaker > Notebook Instances
2. Verify instance status is "InService"
3. Test code-server access:
   ```bash
   curl -k https://<instance-url>/health
   ```

## Configuration Options

### Instance Types

Available instance types:
- ml.t3.medium (2 vCPU, 4 GiB) - Development
- ml.t3.large (2 vCPU, 8 GiB) - Testing
- ml.t3.xlarge (4 vCPU, 16 GiB) - Production

Example configuration:
```hcl
instance_type = "ml.t3.xlarge"
```

### Autostop Configuration

Customize in terraform.tfvars:
```hcl
idle_timeout    = 5400  # seconds
cpu_threshold   = 5    # percentage
start_hour      = 8
end_hour        = 19
```

## Troubleshooting Guide

### Common Issues

1. **Terraform Init Fails**
   ```
   Error: Failed to get existing workspaces
   ```
   Solution:
   - Check AWS credentials
   - Verify region in provider block
   - Run: `rm -rf .terraform && terraform init`

2. **Instance Creation Fails**
   ```
   Error: Error creating SageMaker Notebook Instance
   ```
   Solutions:
   - Check IAM roles and permissions
   - Verify instance type availability in region
   - Check service quotas

3. **Code-Server Access Issues**
   - Check security group rules
   - Verify SSL certificate setup
   - Review Nginx logs:
     ```bash
     ssh instance "sudo cat /var/log/nginx/error.log"
     ```

4. **Autostop Not Working**
   - Check CloudWatch logs
   - Verify cron job setup:
     ```bash
     ssh instance "crontab -l"
     ```
   - Review autostop logs:
     ```bash
     ssh instance "sudo cat /var/log/autostop.log"
     ```

### Debug Mode

Enable detailed logging:
```hcl
debug_mode = true
```

### Health Checks

Run the built-in health check:
```bash
./health_check.sh <instance-id>
```

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

⚠️ Warning: This will delete all resources including data!

## Support and Maintenance

### Log Collection

Gather all relevant logs:
```bash
./collect_logs.sh <instance-id>
```

### Updates

1. Update Terraform:
   ```bash
   terraform init -upgrade
   ```

2. Update provider:
   ```bash
   terraform providers update
   ```

### Backup

Always backup your state file:
```bash
cp terraform.tfstate terraform.tfstate.backup
```

## Security Best Practices

1. Use AWS KMS for encryption
2. Enable VPC endpoints
3. Implement proper IAM roles
4. Regular security updates
5. Monitor CloudTrail logs

## Performance Optimization

1. Use appropriate instance types
2. Enable EBS optimization
3. Configure proper autostop thresholds
4. Monitor CloudWatch metrics

For additional support, please open an issue in the repository.
