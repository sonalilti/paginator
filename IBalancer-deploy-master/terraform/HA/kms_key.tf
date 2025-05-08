## Implementation

resource "aws_kms_key" "main" {
  description         = "Main KMS key for ${var.vpc_name}"
  enable_key_rotation = true
  multi_region        = true
  tags = {
    "env" = var.vpc_name
  }
}

data "aws_kms_key" "current" {
  key_id = aws_kms_key.main.arn
}

