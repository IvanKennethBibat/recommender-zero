output "public_ip" {
  description = "Elastic IP of the server; point the api_domain record in Cloudflare here"
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "EC2 instance ID; set as the DEPLOY_INSTANCE_ID repository variable"
  value       = aws_instance.app.id
}

output "ssm_session_command" {
  description = "Opens a root-capable shell on the server (needs the AWS CLI and Session Manager plugin)"
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.app.id}"
}

output "aws_region" {
  description = "Set as the AWS_REGION repository variable"
  value       = var.aws_region
}

output "backup_bucket" {
  description = "S3 bucket receiving database backups"
  value       = aws_s3_bucket.backups.bucket
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repository variable"
  value       = aws_iam_role.github_deploy.arn
}

output "deploy_document_name" {
  description = "Set as the DEPLOY_DOCUMENT_NAME repository variable"
  value       = aws_ssm_document.deploy.name
}

output "ssm_parameter_names" {
  description = "SecureString parameters to create before the first deploy"
  value = [
    for name in ["secret-key", "postgres-password", "grafana-admin-password", "cloudflare-dns-api-token"] :
    "${local.ssm_parameter_prefix}/${name}"
  ]
}
