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

variable "idle_timeout" {
  description = "Idle timeout in seconds"
  type        = number
}

variable "start_hour" {
  description = "Hour to start the instance (24h format)"
  type        = number
}

variable "start_minute" {
  description = "Minute to start the instance"
  type        = number
}

variable "end_hour" {
  description = "Hour to stop the instance (24h format)"
  type        = number
}

variable "end_minute" {
  description = "Minute to stop the instance"
  type        = number
}

variable "timezone" {
  description = "Timezone for scheduling"
  type        = string
}
