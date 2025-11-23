#!/bin/bash
#
# Stop Factorio Server Instance
# This script stops the EC2 instance running the Factorio server
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"

# Load configuration
if [ -f "$CONFIG_DIR/aws-resources.conf" ]; then
    source "$CONFIG_DIR/aws-resources.conf"
else
    echo "Error: AWS resources not configured. Run scripts/setup-aws.sh first."
    exit 1
fi

echo "Looking for running Factorio server instance..."

INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=factorio-server" \
    "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "No running Factorio server instance found."
    exit 0
fi

echo "Found instance: $INSTANCE_ID"
echo "Stopping instance..."

aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"

echo "Instance is stopping. It will take a few moments to fully stop."
echo "To start it again, run: ./scripts/start-server.sh"
