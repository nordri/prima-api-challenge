output "irsa_role_arn" {
  description = "IAM role ARN used by the Kubernetes ServiceAccount"
  value       = var.enable_irsa ? aws_iam_role.app_irsa[0].arn : null
}
