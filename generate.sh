#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo 'Usage: generate.sh <project_dir>'
  exit 1
fi

PROJECT_DIR="$(cd "$1" && pwd)"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


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

require 'jq --version' jq https://stedolan.github.io/jq/
require 'curl --version' curl https://curl.se/


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
prompt_yes_no "Initialize Terraform configurations?" INITIALIZE_TERRAFORM no


### Setup

TERRAFORM_VERSION="$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')" \

# Check that the correct version of Terraform is installed
if [ "$INITIALIZE_TERRAFORM" = true ]; then
  require 'local_version="$(terraform version -json | jq -r '.terraform_version')"' Terraform https://www.terraform.io/
  if [ "$local_version" != "$TERRAFORM_VERSION" ]; then
    echo "Wrong version of Terraform installed ($local_version). Upgrade to version $TERRAFORM_VERSION."
    exit 4
  fi
fi

AWS_PROVIDER_VERSION="$(curl -s https://registry.terraform.io/v1/providers/hashicorp/aws | jq -r '.version')" \
LOCAL_VERSION="$(curl -s https://registry.terraform.io/v1/providers/hashicorp/local | jq -r '.version')" \

mkdir -p "$TERRAFORM_DIR"
pushd "$TERRAFORM_DIR" > /dev/null

export \
  STACK \
  AWS_ACCOUNT_ID \
  AWS_PROFILE \
  AWS_REGION \
  TERRAFORM_VERSION \
  AWS_PROVIDER_VERSION \
  LOCAL_VERSION


### Generate configurations

copy_config() {
  local basename="$1"
  local destname="${2:-"$1"}"

  cp -R "$TEMPLATE_DIR/terraform/$basename" "$destname"
  find "$destname" -type f -name '*.tmpl' -exec bash -c '
    eval "echo \"$(cat "$0")\"" > "${0%.tmpl}"
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


### Append to .gitignore

if [ "$MODIFY_GITIGNORE" = true ]; then
  GITIGNORE_PATH="$PROJECT_DIR/.gitignore"

  if [ -f "$GITIGNORE_PATH" ]; then
    echo "$(awk 'NF {p=1; printf "%s",n; n=""; print; next}; p {n=n RS}' "$GITIGNORE_PATH")" > "$GITIGNORE_PATH"
    echo >> "$GITIGNORE_PATH"
  fi

  cat "$TEMPLATE_DIR/.gitignore" >> "$GITIGNORE_PATH"
fi


### Initialize Terraform configurations

if [ "$INITIALIZE_TERRAFORM" = true ]; then
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
    terraform init -input=false -backend-config="../config/backend_config.tfvars"
    popd > /dev/null
  fi

  # environment
  pushd "$ENVIRONMENT_DEST" > /dev/null
  printf "\nInitializing environment...\n"
  terraform init -input=false -backend-config="../config/backend_config.tfvars"
  popd > /dev/null
fi


### Done

printf "\nDone!\n"
