variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "fede-diaz-tech-challenge"
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL for AWS services"
  type        = string
  default     = "http://localhost:4566"
}

variable "use_localstack" {
  description = "Flag to determine whether to use LocalStack for AWS services"
  type        = bool
  default     = true
}

variable "aws_access_key" {
  description = "AWS access key for authentication"
  type        = string
  default     = "test"
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key for authentication"
  type        = string
  default     = "test"
  sensitive   = true
}

variable "aws_session_token" {
  description = "AWS session token for temporary credentials"
  type        = string
  default     = null
  sensitive   = true
}