module "aws" {
  source = "github.com/Originate/terraform-modules//aws/base_global?ref=v1"

  stack = var.stack

  domain                  = var.domain
  ecr_keep_image_count    = var.ecr_keep_image_count
  ecr_preserve_image_tags = var.ecr_preserve_image_tags
  ecr_repository_names    = var.ecr_repository_names
}
