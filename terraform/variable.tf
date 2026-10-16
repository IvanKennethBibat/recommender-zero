variable "aws_region" {
  description = "AWS Region Specification"
  type        = string
  default     = "eu-north-1"
}

variable "vpc_cidr" {
  description = "IP Address Range for the VPC (max 65536)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "project_name" {
  description = "Prefix for resource names, the Project tag and the SSM parameter path (/<project_name>/...)"
  type        = string
  default     = "task-api"
}

variable "instance_type" {
  description = "EC2 instance type for the server running the compose stack; must be ARM (Graviton), e.g. t4g.small"
  type        = string
  default     = "t4g.small"

  validation {
    condition     = can(regex("^[a-z]+[0-9]+g[a-z]*\\.", var.instance_type))
    error_message = "instance_type must be a Graviton (ARM) type such as t4g.small, because the AMI is arm64."
  }
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB; holds Docker images, the database and local backups"
  type        = number
  default     = 20
}

variable "repository_url" {
  description = "Git URL cloned to /opt/task-api and fetched on each deploy (use your fork; must be readable without credentials)"
  type        = string
  default     = "https://github.com/IvanKennethBibat/task-api.git"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the deploy role from its main branch"
  type        = string
  default     = "IvanKennethBibat/task-api"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider; set false if this AWS account already has one"
  type        = bool
  default     = true
}

variable "api_domain" {
  description = "Public hostname for the API and Grafana (bare hostname, managed in Cloudflare)"
  type        = string
}

variable "acme_email" {
  description = "Email address registered with Let's Encrypt"
  type        = string
}

variable "backup_retention_days" {
  description = "Days to keep backup dumps in S3 before they are deleted"
  type        = number
  default     = 30
}
