module "aws" {
  source = "github.com/Originate/terraform-modules//aws/base_env?ref=v1"

  env = terraform.workspace

  base_domain       = var.aws_base_domain
  use_env_subdomain = var.aws_use_env_subdomain
}
