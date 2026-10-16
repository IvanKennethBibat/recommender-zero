# Creates the S3 bucket that holds the main configuration's Terraform state. Run once per project, before the main
# `terraform init`. Its own state is local and only describes this bucket; if it's lost, the bucket can be imported.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.49"
    }
  }

  required_version = ">= 1.10"
}

variable "aws_region" {
  description = "Region for the state bucket; use the same region as the main configuration"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Same project_name as the main configuration; prefixes the bucket name and the state key"
  type        = string
  default     = "task-api"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket_prefix = "${var.project_name}-tfstate-"

  # Deleting this bucket would lose track of every resource in the main configuration
  lifecycle {
    prevent_destroy = true
  }
}

# Every state write is kept as a version, so a bad apply or a corrupted state can be rolled back
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket" {
  description = "Name of the state bucket"
  value       = aws_s3_bucket.state.bucket
}

output "backend_config" {
  description = "Contents for terraform/backend.hcl: terraform output -raw backend_config > ../backend.hcl"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "${var.project_name}/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
