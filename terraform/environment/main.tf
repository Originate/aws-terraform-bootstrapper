terraform {
  backend "s3" {
    workspace_key_prefix = "environment"
    key                  = "terraform.tfstate"
  }
}
