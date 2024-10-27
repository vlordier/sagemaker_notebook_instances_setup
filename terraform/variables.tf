variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "allowed_ips" {
  description = "List of allowed IP addresses in CIDR notation"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Change this to your specific IPs in production
}

variable "vpc_id" {
  description = "ID of the VPC to use"
  type        = string
  validation {
    condition     = can(regex("^vpc-[a-f0-9]{8,}$", var.vpc_id))
    error_message = "VPC ID must be a valid vpc-* identifier"
  }
}

variable "subnet_id" {
  description = "ID of the subnet to use"
  type        = string
  validation {
    condition     = can(regex("^subnet-[a-f0-9]{8,}$", var.subnet_id))
    error_message = "Subnet ID must be a valid subnet-* identifier"
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days"
  }
}

variable "user_nickname" {
  description = "User nickname for the instance name"
  type        = string
  default     = "default"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "sagemaker-notebook"
}

variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
  default     = "saml"
}

variable "instance_type" {
  description = "SageMaker notebook instance type"
  type        = string
  default     = "ml.t3.large"
  validation {
    condition     = can(regex("^ml\\.[a-z][1-9][.][a-z0-9]+$", var.instance_type))
    error_message = "Instance type must be a valid SageMaker instance type (e.g., ml.t3.large)"
  }
}

variable "idle_timeout" {
  description = "Idle time threshold in seconds"
  type        = number
  default     = 5400
}

variable "start_hour" {
  description = "Start hour for active hours (0-23)"
  type        = number
  default     = 8
}

variable "start_minute" {
  description = "Start minute for active hours (0-59)"
  type        = number
  default     = 0
}

variable "end_hour" {
  description = "End hour for active hours (0-23)"
  type        = number
  default     = 19
}

variable "end_minute" {
  description = "End minute for active hours (0-59)"
  type        = number
  default     = 30
}

variable "timezone" {
  description = "Timezone for the instance"
  type        = string
  default     = "Europe/Paris"
}

variable "cpu_threshold" {
  description = "CPU usage threshold for auto-stop script"
  type        = number
  default     = 10
}

variable "sagemaker_role_arn" {
  description = "ARN of the IAM role for SageMaker execution"
  type        = string
}
