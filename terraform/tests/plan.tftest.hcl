# Plan-level checks against a mocked AWS provider: no credentials or real resources needed. Run with: terraform test
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-north-1a"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_ssm_document" {
    defaults = { arn = "arn:aws:ssm:eu-north-1:123456789012:document/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::task-api-backups-mock", bucket = "task-api-backups-mock" }
  }
  mock_resource "aws_instance" {
    defaults = { arn = "arn:aws:ec2:eu-north-1:123456789012:instance/i-mock", id = "i-mock" }
  }
}

variables {
  api_domain        = "api.example.com"
  acme_email        = "ops@example.com"
  repository_url    = "https://github.com/my-org/my-app.git"
  github_repository = "my-org/my-app"
}

run "creates_oidc_provider" {
  command = apply
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "OIDC provider should be created by default"
  }
  assert {
    condition     = jsondecode(aws_iam_role.github_deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:my-org/my-app:ref:refs/heads/main"
    error_message = "Deploy role must only trust main of the configured repo"
  }
  assert {
    condition     = jsondecode(aws_ssm_document.deploy.content).parameters.commit.allowedPattern == "^[0-9a-f]{40}$"
    error_message = "Deploy document must only accept a full commit SHA"
  }
  assert {
    condition     = strcontains(aws_instance.app.user_data, "BACKUP_S3_BUCKET=task-api-backups-mock") && strcontains(aws_instance.app.user_data, "SSM_PARAMETER_PREFIX=/task-api") && strcontains(aws_instance.app.user_data, "DOMAIN=api.example.com")
    error_message = "user_data must carry the deploy settings"
  }
  assert {
    condition     = output.ssm_parameter_names[3] == "/task-api/cloudflare-dns-api-token"
    error_message = "Parameter names should use the project prefix"
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.app_parameters.policy).Statement[0].Resource == "arn:aws:ssm:eu-north-1:123456789012:parameter/task-api/*"
    error_message = "Instance may only read its own parameters"
  }
  assert {
    condition     = aws_instance.app.metadata_options[0].http_put_response_hop_limit == 2 && aws_instance.app.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 with hop limit 2 is required for containers"
  }
}

run "reuses_existing_oidc_provider" {
  command = apply
  variables {
    create_github_oidc_provider = false
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "Should not create a provider when reusing"
  }
}

run "rejects_x86_instance" {
  command = plan
  variables {
    instance_type = "t3.small"
  }
  expect_failures = [var.instance_type]
}

run "rejects_url_as_github_repository" {
  command = plan
  variables {
    github_repository = "https://github.com/my-org/my-app.git"
  }
  expect_failures = [var.github_repository]
}
