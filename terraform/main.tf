provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

# Get the existing SageMaker execution role
data "aws_iam_role" "existing_sagemaker_role" {
  name = var.sagemaker_role_name
}

# Create on-create lifecycle configuration
resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "on_create" {
  name = "${var.instance_name}-on-create"
  on_create = base64encode(file("scripts/lifecycle/on-create.sh"))
}

# Create on-start lifecycle configuration
resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "on_start" {
  name = "${var.instance_name}-on-start"
  on_start = base64encode(file("scripts/lifecycle/on-start.sh"))
}

resource "aws_sagemaker_notebook_instance" "sagemaker_instance" {
  name                    = var.instance_name
  instance_type          = var.instance_type
  role_arn               = data.aws_iam_role.existing_sagemaker_role.arn
  subnet_id              = var.subnet_id
  volume_size            = var.volume_size
  direct_internet_access = "Disabled"
  security_groups        = [aws_security_group.sagemaker_sg.id]

  lifecycle_config_name  = aws_sagemaker_notebook_instance_lifecycle_configuration.on_start.name

  # Validate VPC settings
  lifecycle {
    precondition {
      condition     = var.vpc_id != "" && var.subnet_id != ""
      error_message = "VPC ID and Subnet ID must be provided for network isolation."
    }
  }
}

# Security group for SageMaker
resource "aws_security_group" "sagemaker_sg" {
  name        = "${var.instance_name}-sg"
  description = "Security group for SageMaker notebook instance"
  vpc_id      = var.vpc_id

  # Neo4j HTTP
  ingress {
    from_port   = 7474
    to_port     = 7474
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Neo4j HTTP"
  }

  # Neo4j HTTPS
  ingress {
    from_port   = 7473
    to_port     = 7473
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Neo4j HTTPS"
  }

  # Neo4j Bolt protocol
  ingress {
    from_port   = 7687
    to_port     = 7687
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Neo4j Bolt protocol"
  }

  # VS Code Server
  ingress {
    from_port   = 8080
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "VS Code Server"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTPS"
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.instance_name}-sg"
  }
}
