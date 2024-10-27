terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Verify VPC exists
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Verify subnet exists and belongs to the VPC
data "aws_subnet" "selected" {
  id = var.subnet_id

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Security Group
resource "aws_security_group" "notebook" {
  name        = "notebook-sg"
  description = "Security group for notebook instance"
  vpc_id      = var.vpc_id

  # HTTPS access for code-server
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ips
    description = "HTTPS for code-server"
  }

  # SSH access (optional, for troubleshooting)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ips
    description = "SSH access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name         = "notebook-sg"
    Environment  = terraform.workspace
    ManagedBy    = "terraform"
    VPC          = data.aws_vpc.selected.id
    CreatedBy    = "terraform"
    CreatedDate  = timestamp()
    Project      = "notebook"
    BusinessUnit = "research"
  }

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
  }
}

# SageMaker Notebook Instance
resource "aws_sagemaker_notebook_instance" "notebook" {
  name            = var.instance_name
  instance_type   = var.instance_type
  role_arn        = var.sagemaker_role_arn
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.notebook.id]

  lifecycle_config_name = aws_sagemaker_notebook_instance_lifecycle_configuration.notebook.name

  tags = {
    Name        = var.instance_name
    Environment = terraform.workspace
    ManagedBy   = "terraform"
  }

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
    ignore_changes = [
      tags,
      tags_all,
      instance_metadata_service_configuration
    ]
  }
}

# SageMaker Lifecycle Configuration
resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "notebook" {
  name = "${var.instance_name}-lifecycle-config"

  on_create = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Configure logging with streaming to CloudWatch
    exec 1> >(tee >(logger -s -t $(basename $0))) 2>&1

    # Create base directory
    BASE_DIR="/home/ec2-user/SageMaker/my-sagemaker-setup"
    mkdir -p "$BASE_DIR/lifecycle_configurations"

    # Copy the lifecycle scripts content directly
    cat > "$BASE_DIR/lifecycle_configurations/on-create.sh" <<'SCRIPT'
$(cat lifecycle_configurations/on-create.sh)
SCRIPT

    cat > "$BASE_DIR/lifecycle_configurations/on-start.sh" <<'SCRIPT'
$(cat lifecycle_configurations/on-start.sh)
SCRIPT

    # Make scripts executable
    chmod +x "$BASE_DIR"/lifecycle_configurations/*.sh

    # Run the on-create script
    /bin/bash "$BASE_DIR/lifecycle_configurations/on-create.sh"
  EOF
  )

  on_start = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Configure logging
    exec 1> >(logger -s -t $(basename $0)) 2>&1

    # Run the on-start script
    /bin/bash /home/ec2-user/SageMaker/my-sagemaker-setup/lifecycle_configurations/on-start.sh
  EOF
  )
}


# Outputs
output "notebook_url" {
  value       = aws_sagemaker_notebook_instance.notebook.url
  description = "URL of the SageMaker notebook instance"
}

output "notebook_name" {
  value       = aws_sagemaker_notebook_instance.notebook.name
  description = "Name of the SageMaker notebook instance"
}

output "notebook_arn" {
  value       = aws_sagemaker_notebook_instance.notebook.arn
  description = "ARN of the SageMaker notebook instance"
}
