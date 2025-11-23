#!/bin/bash
#
# Factorio Server AWS Setup Script (Terraform-based)
# This script sets up all required AWS resources for running a Factorio server using Terraform
# Requirements: AWS CLI and Terraform configured with appropriate credentials
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Load configuration
if [ -f "$CONFIG_DIR/factorio-server.conf" ]; then
    source "$CONFIG_DIR/factorio-server.conf"
else
    echo -e "${RED}Error: Configuration file not found at $CONFIG_DIR/factorio-server.conf${NC}"
    echo "Please copy config/factorio-server.conf.example to config/factorio-server.conf and configure it."
    exit 1
fi

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    log_info "✓ AWS CLI is properly configured"
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        log_error "Visit: https://www.terraform.io/downloads"
        exit 1
    fi
    
    local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | awk '{print $2}' | sed 's/v//')
    log_info "✓ Terraform is installed (version $tf_version)"
}

select_vpc() {
    log_info "Selecting VPC for Factorio server..."
    
    # Get all VPCs in the region
    local vpc_count=$(aws ec2 describe-vpcs \
        --query "length(Vpcs)" --output text --region "$AWS_REGION")
    
    if [ "$vpc_count" -eq 0 ]; then
        log_error "No VPCs found in region $AWS_REGION"
        exit 1
    fi
    
    # If there's only one VPC, use it automatically
    if [ "$vpc_count" -eq 1 ]; then
        local vpc_id=$(aws ec2 describe-vpcs \
            --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION")
        local vpc_name=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query "Vpcs[0].Tags[?Key=='Name'].Value | [0]" --output text --region "$AWS_REGION" 2>/dev/null || echo "")
        log_info "Using VPC: $vpc_id $([ -n "$vpc_name" ] && [ "$vpc_name" != "None" ] && echo "($vpc_name)" || echo "")"
        echo "$vpc_id"
        return
    fi
    
    # Multiple VPCs - let user choose
    log_info "Found $vpc_count VPCs in region $AWS_REGION"
    echo ""
    
    # Get VPC details and display them
    local vpc_ids=($(aws ec2 describe-vpcs \
        --query "Vpcs[*].VpcId" --output text --region "$AWS_REGION"))
    
    local index=1
    for vpc_id in "${vpc_ids[@]}"; do
        local vpc_name=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query "Vpcs[0].Tags[?Key=='Name'].Value | [0]" --output text --region "$AWS_REGION" 2>/dev/null || echo "")
        local is_default=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query "Vpcs[0].IsDefault" --output text --region "$AWS_REGION")
        local cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
            --query "Vpcs[0].CidrBlock" --output text --region "$AWS_REGION")
        
        echo -n "  $index) $vpc_id - $cidr"
        [ "$is_default" = "true" ] && echo -n " (default)"
        [ -n "$vpc_name" ] && [ "$vpc_name" != "None" ] && echo -n " - $vpc_name"
        echo ""
        ((index++))
    done
    
    echo ""
    read -p "Select VPC (1-$vpc_count): " selection
    
    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$vpc_count" ]; then
        log_error "Invalid selection. Please enter a number between 1 and $vpc_count"
        exit 1
    fi
    
    # Return selected VPC ID
    local selected_vpc="${vpc_ids[$((selection-1))]}"
    log_info "Selected VPC: $selected_vpc"
    echo "$selected_vpc"
}

setup_s3_backend() {
    local bucket_name="${S3_BUCKET_PREFIX}-$(aws sts get-caller-identity --query Account --output text)"
    
    log_section "Setting up S3 Backend for Terraform"
    
    # Check if bucket exists
    if aws s3 ls "s3://$bucket_name" 2>/dev/null; then
        log_info "S3 bucket $bucket_name already exists"
    else
        log_info "Creating S3 bucket: $bucket_name"
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://$bucket_name" --region "$AWS_REGION"
        else
            aws s3 mb "s3://$bucket_name" --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        log_info "Created S3 bucket: $bucket_name"
    fi
    
    # Enable versioning on the bucket (for Terraform state)
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION"
    log_info "Enabled versioning on bucket: $bucket_name"
    
    echo "$bucket_name"
}

generate_key_pair() {
    log_info "Checking for SSH key pair: $KEY_PAIR_NAME"
    
    # Check if key pair exists
    if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" &> /dev/null; then
        log_warn "Key pair $KEY_PAIR_NAME already exists"
    else
        log_info "Creating new key pair: $KEY_PAIR_NAME"
        aws ec2 create-key-pair \
            --key-name "$KEY_PAIR_NAME" \
            --query 'KeyMaterial' \
            --output text \
            --region "$AWS_REGION" > "$PROJECT_ROOT/${KEY_PAIR_NAME}.pem"
        
        chmod 400 "$PROJECT_ROOT/${KEY_PAIR_NAME}.pem"
        log_info "Created key pair and saved to ${KEY_PAIR_NAME}.pem"
        log_warn "IMPORTANT: Keep this key file safe! It's required to access your server."
    fi
}

run_terraform() {
    local vpc_id=$1
    local bucket_name=$2
    
    log_section "Running Terraform"
    
    cd "$TERRAFORM_DIR"
    
    # Create tfvars file
    cat > terraform.tfvars <<EOF
aws_region               = "$AWS_REGION"
s3_bucket_prefix         = "$S3_BUCKET_PREFIX"
s3_backup_retention_days = $S3_BACKUP_RETENTION_DAYS
key_pair_name            = "$KEY_PAIR_NAME"
allowed_cidr_blocks      = "$ALLOWED_CIDR_BLOCKS"
vpc_id                   = "$vpc_id"
EOF
    
    # Create backend configuration file
    cat > backend.conf <<EOF
bucket = "$bucket_name"
key    = "terraform-state/terraform.tfstate"
region = "$AWS_REGION"
EOF
    
    log_info "Initializing Terraform..."
    terraform init -backend-config=backend.conf
    
    log_info "Planning Terraform changes..."
    terraform plan -out=tfplan
    
    echo ""
    read -p "Apply Terraform plan? (yes/no): " apply_confirm
    
    if [ "$apply_confirm" = "yes" ]; then
        log_info "Applying Terraform configuration..."
        terraform apply tfplan
        rm -f tfplan
        
        log_info "Terraform applied successfully!"
    else
        log_warn "Terraform apply cancelled"
        rm -f tfplan
        exit 0
    fi
    
    cd "$PROJECT_ROOT"
}

main() {
    log_section "Factorio Server AWS Setup (Terraform)"
    log_info "Region: $AWS_REGION"
    
    # Check prerequisites
    check_prerequisites
    
    # Select VPC
    VPC_ID=$(select_vpc)
    
    # Setup S3 backend
    BUCKET_NAME=$(setup_s3_backend)
    
    # Generate SSH key pair
    generate_key_pair
    
    # Run Terraform
    run_terraform "$VPC_ID" "$BUCKET_NAME"
    
    log_section "Setup Completed Successfully!"
    log_info "S3 Bucket: $BUCKET_NAME"
    log_info "VPC: $VPC_ID"
    log_info "Key Pair: $KEY_PAIR_NAME"
    log_info ""
    log_info "Terraform state is stored in S3 at: s3://$BUCKET_NAME/terraform-state/terraform.tfstate"
    log_info ""
    log_info "Next steps:"
    log_info "1. Use scripts/deploy-server.sh to launch your Factorio server"
    log_info "2. Use scripts/manage-factorio.sh to manage server versions and mods"
}

main "$@"
