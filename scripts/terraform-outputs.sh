#!/bin/bash
#
# Common functions for reading Terraform outputs
# Source this file in other scripts to get Terraform output values
#

# Hard-coded region (matches setup-aws.sh)
AWS_REGION="${AWS_REGION:-us-east-1}"

# Initialize Terraform with S3 backend configuration
# This function retrieves the S3 bucket name from Parameter Store and initializes Terraform
init_terraform() {
    local terraform_dir="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/terraform"
    
    if [ ! -d "$terraform_dir" ]; then
        echo "Error: Terraform directory not found at $terraform_dir" >&2
        return 1
    fi
    
    # Check if terraform is already initialized
    if [ -f "$terraform_dir/.terraform/terraform.tfstate" ]; then
        return 0
    fi
    
    # Get bucket name from Parameter Store
    local param_name="factorio_server_s3_bucket"
    local bucket_name=""
    
    bucket_name=$(aws ssm get-parameter --name "$param_name" --query 'Parameter.Value' --output text --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ -z "$bucket_name" ] || [ "$bucket_name" = "None" ]; then
        echo "Error: S3 bucket name not found in Parameter Store. Run scripts/setup-aws.sh first." >&2
        return 1
    fi
    
    # Create backend configuration file
    cd "$terraform_dir" || return 1
    cat > backend.conf <<EOF
bucket = "$bucket_name"
key    = "terraform-state/terraform.tfstate"
region = "$AWS_REGION"
EOF
    
    # Initialize Terraform with backend configuration
    # Suppress stdout but preserve stderr for debugging
    terraform init -backend-config=backend.conf >/dev/null
    local init_exit_code=$?
    cd - > /dev/null || return 1
    
    if [ $init_exit_code -ne 0 ]; then
        echo "Error: Terraform initialization failed" >&2
        return 1
    fi
    
    return 0
}

# Get Terraform output value
# Usage: get_terraform_output <output_name>
get_terraform_output() {
    local output_name=$1
    local terraform_dir="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/terraform"
    
    if [ ! -d "$terraform_dir" ]; then
        echo "Error: Terraform directory not found at $terraform_dir" >&2
        return 1
    fi
    
    # Initialize terraform if needed
    init_terraform || return 1
    
    cd "$terraform_dir" || return 1
    local value
    value=$(terraform output -raw "$output_name" 2>/dev/null)
    local exit_code=$?
    cd - > /dev/null || return 1
    
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
