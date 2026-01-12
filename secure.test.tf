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
}

data "aws_vpc" "default" {
  default = true
}

variable "allowed_admin_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "app_ingress_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = local.app_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
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
    appl
