resource "aws_iam_policy" "app" {
  count = var.enable_irsa ? 1 : 0

  name        = "${local.name_prefix}-app"
  description = "Permissions required by the Prima API"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"

        Action = [
          "dynamodb:Scan",
          "dynamodb:PutItem"
        ]

        Resource = aws_dynamodb_table.users.arn
      },
      {
        Sid    = "S3Upload"
        Effect = "Allow"

        Action = [
          "s3:PutObject"
        ]

        Resource = "${aws_s3_bucket.avatars.arn}/*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "app_irsa" {
  count = var.enable_irsa ? 1 : 0

  name = "${local.name_prefix}-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = var.eks_oidc_provider_arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "${replace(var.eks_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
            "${replace(var.eks_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "app_irsa" {
  count = var.enable_irsa ? 1 : 0

  role       = aws_iam_role.app_irsa[0].name
  policy_arn = aws_iam_policy.app[0].arn
}
