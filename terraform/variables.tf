variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  description = "Instance type for the SageMaker notebook"
  type        = string
}

variable "sagemaker_role_arn" {
  description = "ARN of the SageMaker execution role"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the SageMaker notebook"
  type        = string
}



variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "instance_name" {
  description = "Instance name for resources"
  type        = string
}

variable "aws_profile" {
  description = "AWS profile name"
  type        = string
}

variable "allowed_ips" {
  description = "List of allowed IP addresses in CIDR notation"
  type        = list(string)
  default     = ["0.0.0.0/0"] # WARNING: Change this to your specific IPs in production
}

variable "idle_timeout" {
  description = "Idle time threshold in seconds"
  type        = number
}

variable "start_hour" {
  description = "Start hour for active hours (24h format)"
  type        = number
}

variable "start_minute" {
  description = "Start minute for active hours"
  type        = number
}

variable "end_hour" {
  description = "End hour for active hours (24h format)"
  type        = number
}

variable "end_minute" {
  description = "End minute for active hours"
  type        = number
}

variable "timezone" {
  description = "Timezone for the active hours"
  type        = string
}

variable "cpu_threshold" {
  description = "CPU usage threshold percentage"
  type        = number
}
