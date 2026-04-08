# =============================================================================
# AWS KMS Auto-Unseal for OpenBao
#
# Creates a KMS key and a dedicated IAM user with minimal permissions.
# The IAM user's credentials are placed on erebor as an environment file
# so OpenBao can call KMS to auto-unseal on startup.
# =============================================================================

# -----------------------------------------------------------------------------
# KMS Key
# -----------------------------------------------------------------------------

resource "aws_kms_key" "openbao_unseal" {
  description         = "OpenBao auto-unseal key"
  key_usage           = "ENCRYPT_DECRYPT"
  enable_key_rotation = true

  tags = {
    Purpose   = "openbao-auto-unseal"
    ManagedBy = "opentofu"
  }
}

resource "aws_kms_alias" "openbao_unseal" {
  name          = "alias/openbao-unseal"
  target_key_id = aws_kms_key.openbao_unseal.key_id
}

# -----------------------------------------------------------------------------
# IAM User (dedicated, minimal permissions)
# -----------------------------------------------------------------------------

resource "aws_iam_user" "openbao_unseal" {
  name = "openbao-unseal"

  tags = {
    Purpose   = "openbao-auto-unseal"
    ManagedBy = "opentofu"
  }
}

resource "aws_iam_user_policy" "openbao_unseal" {
  name = "openbao-kms-unseal"
  user = aws_iam_user.openbao_unseal.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKMSUnseal"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = [aws_kms_key.openbao_unseal.arn]
      }
    ]
  })
}

resource "aws_iam_access_key" "openbao_unseal" {
  user = aws_iam_user.openbao_unseal.name
}
