data "terraform_remote_state" "backend" {
  backend = "local"

  config = {
    path = "${path.root}/../remote_state/tfstate/terraform.tfstate"
  }
}

# Provides outputs from the previous successful run
data "terraform_remote_state" "self" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    profile = data.terraform_remote_state.backend.outputs.profile
    region  = data.terraform_remote_state.backend.outputs.region
    bucket  = data.terraform_remote_state.backend.outputs.bucket_name

    workspace_key_prefix = "environment"
    key                  = "terraform.tfstate"
  }
}
