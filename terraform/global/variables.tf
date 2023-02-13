variable "account_id" {
  description = "The ID of the AWS account in which resources are created"
  type        = string
}

variable "profile" {
  description = "The profile to use for accessing the AWS account"
  type        = string
}

variable "region" {
  description = "The AWS region"
  type        = string
}

variable "stack" {
  description = "The name of the stack"
  type        = string
}
