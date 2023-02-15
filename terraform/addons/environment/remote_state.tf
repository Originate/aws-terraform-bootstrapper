locals {
  # Provides outputs from the previous successful run
  previous_outputs = try(data.terraform_remote_state.self[0].outputs, {})

  tfstate_workspace_prefix = "environment"
  tfstate_key              = "terraform.tfstate"
}

data "terraform_remote_state" "backend" {
  backend = "local"

  config = {
    path = "${path.root}/../remote_state/tfstate/terraform.tfstate"
  }
}

data "aws_s3_objects" "tfstate" {
  bucket = data.terraform_remote_state.backend.outputs.bucket_name
  prefix = terraform.workspace == "default" ? local.tfstate_key : "${local.tfstate_workspace_prefix}/${terraform.workspace}/${local.tfstate_key}"
}

data "terraform_remote_state" "self" {
  count = length(data.aws_s3_objects.tfstate.keys) > 0 ? 1 : 0

  backend   = "s3"
  workspace = terraform.workspace

  config = {
    profile = data.terraform_remote_state.backend.outputs.profile
    region  = data.terraform_remote_state.backend.outputs.region
    bucket  = data.terraform_remote_state.backend.outputs.bucket_name

    workspace_key_prefix = local.tfstate_workspace_prefix
    key                  = local.tfstate_key
  }
}
