terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  app_bucket_name   = "secure-app-bucket-${random_id.suffix.hex}"
  trail_bucket_name = "secure-cloudtrail-logs-${random_id.suffix.hex}"
  logs_bucket_name  = "secure-access-logs-${random_id.suffix.hex}"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_caller_identity" "current" {}

variable "allowed_admin_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "app_ingress_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "egress_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# ---------------- KMS ----------------
resource "aws_kms_key" "security_key" {
  description             = "CMK for S3 and CloudTrail encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "security_key" {
  name          = "alias/security-key"
  target_key_id = aws_kms_key.security_key.key_id
}

# ---------------- S3 Access Logs Bucket ----------------
resource "aws_s3_bucket" "access_logs" {
  bucket = local.logs_bucket_name
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.security_key.arn
    }
  }
}

# ---------------- App Bucket ----------------
resource "aws_s3_bucket" "app_bucket" {
  bucket = local.app_bucket_name
}

resource "aws_s3_bucket_public_access_block" "app_bucket" {
  bucket                  = aws_s3_bucket.app_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.security_key.arn
    }
  }
}

resource "aws_s3_bucket_logging" "app_bucket" {
  bucket        = aws_s3_bucket.app_bucket.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "app/"
}

# ---------------- CloudTrail Bucket ----------------
resource "aws_s3_bucket" "trail_bucket" {
  bucket = local.trail_bucket_name
}

resource "aws_s3_bucket_public_access_block" "trail_bucket" {
  bucket                  = aws_s3_bucket.trail_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail_bucket" {
  bucket = aws_s3_bucket.trail_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.security_key.arn
    }
  }
}

resource "aws_s3_bucket_logging" "trail_bucket" {
  bucket        = aws_s3_bucket.trail_bucket.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "trail/"
}

# ---------------- CloudWatch Logs ----------------
resource "aws_cloudwatch_log_group" "trail_logs" {
  name              = "/aws/cloudtrail/secure"
  retention_in_days = 90
}

data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_role" {
  name               = "cloudtrail-cloudwatch-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume.json
}

resource "aws_iam_role_policy" "cloudtrail_policy" {
  role = aws_iam_role.cloudtrail_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail_logs.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "trail" {
  name                          = "secure-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.trail_bucket.id
  enable_logging                = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.security_key.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail_logs.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_role.arn
}

# ---------------- Security Group ----------------
resource "aws_security_group" "secure_sg" {
  name   = "secure-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "HTTPS from approved CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.app_ingress_cidr]
  }

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  egress {
    description = "Outbound HTTPS to internal CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.egress_cidr]
  }
}
