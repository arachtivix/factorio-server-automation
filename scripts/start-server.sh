#!/bin/bash
#
# Start Factorio Server Instance
# This script starts a stopped EC2 instance running the Factorio server
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load Terraform outputs
source "$SCRIPT_DIR/terraform-outputs.sh"
load_terraform_outputs || {
    echo "Error: Could not load Terraform outputs. Run scripts/setup-aws.sh first."
    exit 1
}

echo "Looking for stopped Factorio server instance..."

INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=factorio-server" \
    "Name=instance-state-name,Values=stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "No stopped Factorio server instance found."
    echo "Run ./scripts/deploy-server.sh to create a new instance."
    exit 0
fi

echo "Found instance: $INSTANCE_ID"
echo "Starting instance..."

aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

echo "Waiting for instance to start..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text \
    --region "$AWS_REGION")

echo "Instance started successfully!"
echo "Public IP: $PUBLIC_IP"
echo "Connect to your server at: $PUBLIC_IP:34197"
