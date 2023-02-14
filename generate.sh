#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo 'Usage: generate.sh <project_dir>'
  exit 1
fi

PROJECT_DIR="$(cd "$1" && pwd)"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDONS_DIR="$TEMPLATE_DIR/terraform/addons"


### Check required utils

require() {
  local check_command="$1"
  local name="$2"
  local install_url="${3:-}"

  if ! eval "$check_command" > /dev/null 2>&1; then
    echo "$name is required. Install it${install_url:+" ($install_url)"} and try again."
    exit 2
  fi
}

require "jq --version" jq https://stedolan.github.io/jq/
require "curl --version" curl https://curl.se/


### Check for existing ./terraform directory

if [ -d "$TERRAFORM_DIR" ] && [ -n "$(ls -A "$TERRAFORM_DIR")" ]; then
  echo "$TERRAFORM_DIR is not empty. Aborting."
  exit 3
fi


### Prompt for values

prompt() {
  local description="$1"
  local var="$2"
  local default="${3:-}"

  while :; do
    local input
    read -r -p "$description [$default]: " input
    input="${input:-$default}"

    if [ -z "$input" ]; then
      echo "$description cannot be empty"
    else
      break
    fi
  done
  export "$var"="$input"
}

prompt_yes_no() {
  local description="$1"
  local var="$2"
  local default="${3:-}"

  while :; do
    local input
    read -r -p "$description [$default]: " input
    input="${input:-$default}"
    cleaned="$(echo "$input" | awk '{gsub(/^ +| +$/,"")} {print tolower($0)}')"

    if [ "$cleaned" = "yes" ]; then
      export "$var"=true
      break
    elif [ "$cleaned" = "no" ]; then
      export "$var"=false
      break
    else
      echo "Value must be either 'yes' or 'no'"
    fi
  done
}

prompt "Stack Name" STACK "${PWD##*/}"

prompt "AWS Account ID" AWS_ACCOUNT_ID
prompt "AWS Profile" AWS_PROFILE "$STACK"
prompt "AWS Region" AWS_REGION "${AWS_REGION:-${AWS_DEFAULT_REGION:-"us-east-1"}}"

prompt_yes_no "Modify .gitignore?" MODIFY_GITIGNORE yes
prompt_yes_no "Create 'global' configuration?" CREATE_GLOBAL yes

if [ "$CREATE_GLOBAL" = true ]; then
  prompt_yes_no "Include AWS base components?" INCLUDE_AWS_BASE no

  if [ "$INCLUDE_AWS_BASE" = true ]; then
    prompt "Base Domain" BASE_DOMAIN
    export BASE_DOMAIN
  fi

  prompt_yes_no "Disable 'default' workspace in 'environment' configuration?" DISABLE_DEFAULT_WORKSPACE no
fi

prompt_yes_no "Include previous output lookup in 'environment' configuration?" INCLUDE_SELF_STATE no
prompt_yes_no "Initialize Terraform configurations?" INITIALIZE_TERRAFORM no


### Setup

get_provider_version() {
  local provider="$1"

  curl -s "https://registry.terraform.io/v1/providers/$provider" | jq -r '.version'
}

TERRAFORM_VERSION="$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')" \

# Check that the correct version of Terraform is installed
if [ "$INITIALIZE_TERRAFORM" = true ]; then
  require "local_version=\"\$(terraform version -json | jq -r '.terraform_version')\"" Terraform https://www.terraform.io/
  if [ "${local_version:?}" != "$TERRAFORM_VERSION" ]; then
    echo "Wrong version of Terraform installed ($local_version). Upgrade to version $TERRAFORM_VERSION."
    exit 4
  fi
fi

AWS_PROVIDER_VERSION="$(get_provider_version hashicorp/aws)"
LOCAL_PROVIDER_VERSION="$(get_provider_version hashicorp/local)"

mkdir -p "$TERRAFORM_DIR"
pushd "$TERRAFORM_DIR" > /dev/null

export \
  STACK \
  AWS_ACCOUNT_ID \
  AWS_PROFILE \
  AWS_REGION \
  TERRAFORM_VERSION \
  AWS_PROVIDER_VERSION \
  LOCAL_PROVIDER_VERSION


### Generate configurations

convert_template() {
  local file="$1"

  eval "echo \"$(cat "$file")\""
}

copy_config() {
  local basename="$1"
  local destname="${2:-"$1"}"

  cp -R "$TEMPLATE_DIR/terraform/$basename" "$destname"
  find "$destname" -type f -name '*.tmpl' -exec bash -c "$(declare -f convert_template)"'
    convert_template "$0" > "${0%.tmpl}"
    rm -f "$0"
  ' '{}' \;
}

# remote_state
copy_config remote_state

# global
if [ "$CREATE_GLOBAL" = true ]; then
  copy_config global
fi

# environment
ENVIRONMENT_DEST="$([ "$CREATE_GLOBAL" = true ] && echo "environment" || echo "${STACK//-/_}")"
copy_config environment "$ENVIRONMENT_DEST"


### Disable environment 'default' workspace

if [ "${DISABLE_DEFAULT_WORKSPACE:-false}" = true ]; then
  printf '\n%s\n' "$(cat "$ADDONS_DIR/environment/disable_default_workspace.tf")" >> "$ENVIRONMENT_DEST/main.tf"

  NULL_PROVIDER_VERSION="$(get_provider_version hashicorp/null)"
  export NULL_PROVIDER_VERSION

  printf '%s\n' "$(sed '$d' "$ENVIRONMENT_DEST/versions.tf" | sed '$d')" > "$ENVIRONMENT_DEST/versions.tf"
  convert_template "$ADDONS_DIR/environment/null_provider.tf.tmpl" | sed 's/^/    /' >> "$ENVIRONMENT_DEST/versions.tf"
  printf '  }\n}\n' >> "$ENVIRONMENT_DEST/versions.tf"
fi


### Enable Terraform state persistence

if [ "$INCLUDE_SELF_STATE" = true ]; then
  cp "$ADDONS_DIR/environment/remote_state.tf" "$ENVIRONMENT_DEST/"
fi


### Generate AWS base components

if [ "${INCLUDE_AWS_BASE:-false}" = true ]; then
  # global
  cp \
    "$ADDONS_DIR/global/aws.tf" \
    "$ADDONS_DIR/global/outputs.tf" \
    global/

  echo >> global/terraform.tfvars
  convert_template "$ADDONS_DIR/global/terraform.tfvars.tmpl" >> global/terraform.tfvars

  echo >> global/variables.tf
  cat "$ADDONS_DIR/global/variables.tf" >> global/variables.tf

  # environment
  cp "$ADDONS_DIR/environment/aws.tf" "$ENVIRONMENT_DEST/"

  echo >> "$ENVIRONMENT_DEST/terraform.tfvars"
  convert_template "$ADDONS_DIR/environment/terraform.tfvars.tmpl" >> "$ENVIRONMENT_DEST/terraform.tfvars"

  echo >> "$ENVIRONMENT_DEST/variables.tf"
  cat "$ADDONS_DIR/environment/variables.tf" >> "$ENVIRONMENT_DEST/variables.tf"
fi


### Append to .gitignore

if [ "$MODIFY_GITIGNORE" = true ]; then
  GITIGNORE_PATH="$PROJECT_DIR/.gitignore"

  if [ -f "$GITIGNORE_PATH" ]; then
    printf '%s\n\n' "$(awk 'NF {p=1; printf "%s",n; n=""; print; next}; p {n=n RS}' "$GITIGNORE_PATH")" > "$GITIGNORE_PATH"
  fi

  cat "$TEMPLATE_DIR/.gitignore" >> "$GITIGNORE_PATH"
fi


### Initialize Terraform configurations

if [ "$INITIALIZE_TERRAFORM" = true ]; then
  BACKEND_CONFIG_PATH="$TERRAFORM_DIR/config/backend_config.tfvars"

  # remote_state
  pushd remote_state > /dev/null
  printf "\nInitializing remote_state...\n"
  terraform init -input=false
  printf "\nApplying remote_state...\n"
  terraform apply -input=false -auto-approve
  popd > /dev/null

  # global
  if [ "$CREATE_GLOBAL" = true ]; then
    pushd global > /dev/null
    printf "\nInitializing global...\n"
    terraform init -input=false -backend-config="$BACKEND_CONFIG_PATH"
    popd > /dev/null
  fi

  # environment
  pushd "$ENVIRONMENT_DEST" > /dev/null
  printf "\nInitializing environment...\n"
  terraform init -input=false -backend-config="$BACKEND_CONFIG_PATH"
  popd > /dev/null
fi


### Done

printf "\nDone!\n"
