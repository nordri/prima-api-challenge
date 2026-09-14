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

variable "enable_irsa" {
  description = "Create IAM resources required for IRSA"
  type        = bool
  default     = false
}

variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
  default     = null
}

variable "eks_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster"
  type        = string
  default     = null
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace used by the application"
  type        = string
  default     = "default"
}

variable "kubernetes_service_account" {
  description = "Kubernetes ServiceAccount used by the application"
  type        = string
  default     = "prima"
}
