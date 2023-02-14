# AWS

variable "domain" {
  description = "The base domain name for the stack"
  type        = string
}

variable "ecr_keep_image_count" {
  description = "The number of the newest images to keep in an ECR repository (older images are automatically pruned by ECR), or leave unset to disable pruning"
  type        = number
}

variable "ecr_preserve_image_tags" {
  description = "Ensures images with the matching Docker tags are kept when pruning old images (assumes no other image tags have prefixes matching the provided tag names)"
  type        = list(string)
}

variable "ecr_repository_names" {
  description = "A list of the ECR repository names"
  type        = list(string)
}
