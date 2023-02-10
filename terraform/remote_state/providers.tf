provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  profile             = var.profile

  default_tags {
    tags = {
      Terraform   = "true"
      Stack       = var.stack
      Environment = var.env
    }
  }
}
