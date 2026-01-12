terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_policy" "admin_policy" {
  name = "admin-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}

resource "aws_s3_bucket" "public_bucket" {
  bucket = "public-unencrypted-bucket"
  acl    = "public-read"
}

resource "aws_cloudtrail" "trail" {
  name                          = "no-logging-trail"
  s3_bucket_name                = "public-unencrypted-bucket"
  include_global_service_events = false
  is_multi_region_trail         = false
  enable_logging                = false
}

resource "aws_security_group" "weak_sg" {
  name        = "weak-sg"
  description = "Open to the world"
  vpc_id      = "vpc-123456"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
