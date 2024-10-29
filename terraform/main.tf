terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

# Add random provider for unique naming
provider "random" {}

resource "random_id" "suffix" {
  byte_length = 4
}


resource "aws_security_group" "sagemaker_sg" {
  name        = "${var.instance_name}-sg-${random_id.suffix.hex}"
  description = "Security group for SageMaker notebook instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 7474
    to_port     = 7474
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 7473
    to_port     = 7473
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 7687
    to_port     = 7687
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.instance_name}-sg-${random_id.suffix.hex}"
  }
}

resource "aws_sagemaker_notebook_instance" "sagemaker_instance" {
  name                    = var.instance_name
  instance_type          = var.instance_type
  role_arn               = var.sagemaker_role_arn
  subnet_id              = var.subnet_id
  volume_size            = var.volume_size
  direct_internet_access = "Disabled"
  security_groups        = [aws_security_group.sagemaker_sg.id]


  # Validate VPC settings
  lifecycle {
    precondition {
      condition     = var.vpc_id != "" && var.subnet_id != ""
      error_message = "VPC ID and Subnet ID must be provided for network isolation."
    }
  }
}
