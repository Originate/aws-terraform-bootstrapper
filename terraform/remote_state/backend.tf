module "backend" {
  source = "github.com/Originate/terraform-modules//aws/s3_terraform_backend?ref=v1"

  stack = var.stack

  config_output_path              = "${path.module}/../config/backend_config.tfvars"
  profile                         = var.profile
  kms_key_deletion_window_in_days = 7
}
