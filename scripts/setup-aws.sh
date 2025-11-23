#!/bin/bash
#
# Factorio Server AWS Setup Script
# This script sets up all required AWS resources for running a Factorio server
# Requirements: AWS CLI configured with appropriate credentials
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"

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

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    log_info "AWS CLI is properly configured"
}

create_s3_bucket() {
    local bucket_name="${S3_BUCKET_PREFIX}-$(aws sts get-caller-identity --query Account --output text)"
    
    log_info "Creating S3 bucket: $bucket_name"
    
    # Check if bucket exists
    if aws s3 ls "s3://$bucket_name" 2>/dev/null; then
        log_warn "S3 bucket $bucket_name already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://$bucket_name" --region "$AWS_REGION"
        else
            aws s3 mb "s3://$bucket_name" --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        log_info "Created S3 bucket: $bucket_name"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled
    log_info "Enabled versioning on bucket: $bucket_name"
    
    # Create folder structure
    for folder in "server-binaries" "saves" "mods" "backups"; do
        aws s3api put-object --bucket "$bucket_name" --key "$folder/" --content-length 0 || true
    done
    log_info "Created folder structure in bucket"
    
    # Set lifecycle policy for backups
    cat > /tmp/lifecycle-policy.json <<EOF
{
    "Rules": [
        {
            "Id": "DeleteOldBackups",
            "Filter": {
                "Prefix": "backups/"
            },
            "Status": "Enabled",
            "Expiration": {
                "Days": ${S3_BACKUP_RETENTION_DAYS}
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    log_info "Set lifecycle policy for backups (${S3_BACKUP_RETENTION_DAYS} days retention)"
    
    echo "$bucket_name"
}

create_iam_role() {
    local role_name="factorio-server-role"
    
    log_info "Creating IAM role: $role_name"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "IAM role $role_name already exists"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "file://$CONFIG_DIR/iam-trust-policy.json" \
            --description "Role for Factorio server EC2 instance"
        log_info "Created IAM role: $role_name"
    fi
    
    # Attach policy
    local policy_name="factorio-server-policy"
    
    # Check if policy exists
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_warn "IAM policy $policy_name already exists"
        
        # Update policy with new version
        aws iam create-policy-version \
            --policy-arn "$policy_arn" \
            --policy-document "file://$CONFIG_DIR/iam-policy-server-role.json" \
            --set-as-default
        log_info "Updated IAM policy: $policy_name"
    else
        aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "file://$CONFIG_DIR/iam-policy-server-role.json" \
            --description "Policy for Factorio server operations"
        log_info "Created IAM policy: $policy_name"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "$policy_arn" || true
    log_info "Attached policy to role"
    
    # Create instance profile if it doesn't exist
    if aws iam get-instance-profile --instance-profile-name "$role_name" &> /dev/null; then
        log_warn "Instance profile $role_name already exists"
    else
        aws iam create-instance-profile --instance-profile-name "$role_name"
        aws iam add-role-to-instance-profile \
            --instance-profile-name "$role_name" \
            --role-name "$role_name"
        log_info "Created instance profile: $role_name"
    fi
    
    echo "$role_name"
}

create_security_group() {
    local sg_name="factorio-server-sg"
    local vpc_id=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION")
    
    log_info "Creating security group: $sg_name"
    
    # Check if security group exists
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$vpc_id" \
        --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ "$sg_id" != "" ] && [ "$sg_id" != "None" ]; then
        log_warn "Security group $sg_name already exists with ID: $sg_id"
    else
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "Security group for Factorio server" \
            --vpc-id "$vpc_id" \
            --region "$AWS_REGION" \
            --query "GroupId" --output text)
        log_info "Created security group: $sg_id"
        
        # Add rules
        # SSH access
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 22 \
            --cidr "$ALLOWED_CIDR_BLOCKS" \
            --region "$AWS_REGION"
        
        # Factorio game port (UDP)
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol udp \
            --port 34197 \
            --cidr 0.0.0.0/0 \
            --region "$AWS_REGION"
        
        # Factorio RCON port (TCP) - for admin access
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 27015 \
            --cidr "$ALLOWED_CIDR_BLOCKS" \
            --region "$AWS_REGION"
        
        log_info "Added security group rules"
    fi
    
    echo "$sg_id"
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

save_setup_config() {
    local bucket_name=$1
    local role_name=$2
    local sg_id=$3
    
    cat > "$CONFIG_DIR/aws-resources.conf" <<EOF
# Auto-generated AWS resource configuration
# Generated on: $(date)

S3_BUCKET_NAME=$bucket_name
IAM_ROLE_NAME=$role_name
IAM_INSTANCE_PROFILE=$role_name
SECURITY_GROUP_ID=$sg_id
AWS_REGION=$AWS_REGION
KEY_PAIR_NAME=$KEY_PAIR_NAME
EOF
    
    log_info "Saved AWS resource configuration to $CONFIG_DIR/aws-resources.conf"
}

main() {
    log_info "Starting Factorio Server AWS Setup"
    log_info "Region: $AWS_REGION"
    
    # Check prerequisites
    check_aws_cli
    
    # Create resources
    BUCKET_NAME=$(create_s3_bucket)
    ROLE_NAME=$(create_iam_role)
    SG_ID=$(create_security_group)
    generate_key_pair
    
    # Save configuration
    save_setup_config "$BUCKET_NAME" "$ROLE_NAME" "$SG_ID"
    
    log_info "=========================================="
    log_info "Setup completed successfully!"
    log_info "=========================================="
    log_info "S3 Bucket: $BUCKET_NAME"
    log_info "IAM Role: $ROLE_NAME"
    log_info "Security Group: $SG_ID"
    log_info "Key Pair: $KEY_PAIR_NAME"
    log_info ""
    log_info "Next steps:"
    log_info "1. Review the configuration in config/aws-resources.conf"
    log_info "2. Use scripts/deploy-server.sh to launch your Factorio server"
    log_info "3. Use scripts/manage-factorio.sh to manage server versions and mods"
}

main "$@"
