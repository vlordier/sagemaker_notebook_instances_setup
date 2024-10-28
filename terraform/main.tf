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
  region  = var.aws_region
  profile = var.aws_profile
}


# Verify subnet exists and belongs to the VPC
# data "aws_subnet" "selected" {
#   id = var.subnet_id

#   filter {
#     name   = "vpc-id"
#     values = [var.vpc_id]
#   }
# }

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
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for code-server"
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Restrict outbound traffic to necessary services
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound to internet"
  }

  tags = {
    Name         = "notebook-sg"
    Environment  = terraform.workspace
    ManagedBy    = "terraform"
    VPC          = var.vpc_id
    CreatedBy    = "terraform"
    CreatedDate  = timestamp()
    Project      = "notebook"
    BusinessUnit = "research"
  }

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true # Keep SG protected
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
    prevent_destroy = false
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
set -ex

# Basic setup only
echo "Starting basic setup..."
sudo yum update -y
sudo yum install -y git wget

echo "Setup complete"
EOF
  )

  on_start = base64encode(<<-EOF
#!/bin/bash
set -ex

echo "Starting instance..."
date > /home/ec2-user/startup.log

echo "Startup complete"
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
