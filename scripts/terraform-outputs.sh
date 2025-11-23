#!/bin/bash
#
# Common functions for reading Terraform outputs
# Source this file in other scripts to get Terraform output values
#

# Get Terraform output value
# Usage: get_terraform_output <output_name>
get_terraform_output() {
    local output_name=$1
    local terraform_dir="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/terraform"
    
    if [ ! -d "$terraform_dir" ]; then
        echo "Error: Terraform directory not found at $terraform_dir" >&2
        return 1
    fi
    
    cd "$terraform_dir"
    local value=$(terraform output -raw "$output_name" 2>/dev/null)
    local exit_code=$?
    cd - > /dev/null
    
    if [ $exit_code -ne 0 ]; then
        echo "Error: Could not read Terraform output '$output_name'. Has setup-aws.sh been run?" >&2
        return 1
    fi
    
    echo "$value"
}

# Load all Terraform outputs into variables
# This sets: S3_BUCKET_NAME, IAM_ROLE_NAME, IAM_INSTANCE_PROFILE, SECURITY_GROUP_ID, VPC_ID, AWS_REGION, KEY_PAIR_NAME
load_terraform_outputs() {
    S3_BUCKET_NAME=$(get_terraform_output s3_bucket_name) || return 1
    IAM_ROLE_NAME=$(get_terraform_output iam_role_name) || return 1
    IAM_INSTANCE_PROFILE=$(get_terraform_output iam_instance_profile) || return 1
    SECURITY_GROUP_ID=$(get_terraform_output security_group_id) || return 1
    VPC_ID=$(get_terraform_output vpc_id) || return 1
    AWS_REGION=$(get_terraform_output aws_region) || return 1
    KEY_PAIR_NAME=$(get_terraform_output key_pair_name) || return 1
    
    export S3_BUCKET_NAME IAM_ROLE_NAME IAM_INSTANCE_PROFILE SECURITY_GROUP_ID VPC_ID AWS_REGION KEY_PAIR_NAME
}
