variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "instance_name" {
  description = "Name of the SageMaker instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for SageMaker"
  type        = string
}


variable "volume_size" {
  description = "Volume size in GB for the SageMaker instance"
  type        = number
}

variable "sagemaker_role_arn" {
  description = "ARN of the existing IAM role for SageMaker"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the notebook instance"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}
