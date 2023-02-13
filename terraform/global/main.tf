terraform {
  backend "s3" {
    key = "global/terraform.tfstate"
  }
}
