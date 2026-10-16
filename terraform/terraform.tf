terraform {
  # State lives in the S3 bucket created by bootstrap/; settings come from backend.hcl:
  #   terraform init -backend-config=backend.hcl
  # use_lockfile (S3-native state locking) needs Terraform 1.10+
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.49"
    }
  }

  required_version = ">= 1.10"
}

