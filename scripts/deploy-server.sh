#!/bin/bash
#
# Factorio Server Deployment Script
# This script deploys a Factorio server instance on AWS EC2
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
    echo -e "${RED}Error: Configuration file not found${NC}"
    exit 1
fi

if [ -f "$CONFIG_DIR/aws-resources.conf" ]; then
    source "$CONFIG_DIR/aws-resources.conf"
else
    echo -e "${RED}Error: AWS resources not configured. Run scripts/setup-aws.sh first.${NC}"
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

get_latest_amazon_linux_ami() {
    aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        "Name=state,Values=available" \
        --query "sort_by(Images, &CreationDate)[-1].ImageId" \
        --output text \
        --region "$AWS_REGION"
}

create_user_data_script() {
    cat > /tmp/user-data.sh <<'USERDATA'
#!/bin/bash
set -euo pipefail

# Install dependencies
yum update -y
# Install jq from EPEL for Amazon Linux 2
amazon-linux-extras install epel -y || true
yum install -y wget tar xz jq awscli

# Create factorio user
useradd -m -s /bin/bash factorio

# Set up directories
mkdir -p /opt/factorio/{bin,saves,mods,config,scripts}
chown -R factorio:factorio /opt/factorio

# Download and install Factorio server
FACTORIO_VERSION="${FACTORIO_VERSION}"
if [ "$FACTORIO_VERSION" = "stable" ]; then
    DOWNLOAD_URL="https://factorio.com/get-download/stable/headless/linux64"
else
    DOWNLOAD_URL="https://factorio.com/get-download/${FACTORIO_VERSION}/headless/linux64"
fi

cd /tmp
wget -O factorio_headless.tar.xz "$DOWNLOAD_URL"
tar -xf factorio_headless.tar.xz
cp -r factorio/* /opt/factorio/bin/
chown -R factorio:factorio /opt/factorio/bin

# Copy server configuration
cat > /opt/factorio/config/server-settings.json <<EOF
{
  "name": "${FACTORIO_SERVER_NAME}",
  "description": "${FACTORIO_DESCRIPTION}",
  "tags": ["game", "tags"],
  "_comment_max_players": "Maximum number of players allowed, admins can join even a full server. 0 means unlimited.",
  "max_players": ${FACTORIO_MAX_PLAYERS},
  "visibility": {
    "public": ${FACTORIO_VISIBILITY_PUBLIC},
    "lan": true
  },
  "username": "${FACTORIO_USERNAME}",
  "token": "${FACTORIO_TOKEN}",
  "game_password": "",
  "require_user_verification": true,
  "max_upload_in_kilobytes_per_second": 0,
  "max_upload_slots": 5,
  "minimum_latency_in_ticks": 0,
  "ignore_player_limit_for_returning_players": false,
  "allow_commands": "admins-only",
  "autosave_interval": 10,
  "autosave_slots": 5,
  "afk_autokick_interval": 0,
  "auto_pause": true,
  "only_admins_can_pause_the_game": true,
  "autosave_only_on_server": true,
  "non_blocking_saving": false
}
EOF

# Download setup scripts from S3
aws s3 cp s3://${S3_BUCKET_NAME}/scripts/ /opt/factorio/scripts/ --recursive --region ${AWS_REGION} || true

# Create systemd service
cat > /etc/systemd/system/factorio.service <<EOF
[Unit]
Description=Factorio Dedicated Server
After=network.target

[Service]
Type=simple
User=factorio
Group=factorio
WorkingDirectory=/opt/factorio/bin
ExecStart=/opt/factorio/bin/bin/x64/factorio --start-server-load-latest --server-settings /opt/factorio/config/server-settings.json
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable factorio
systemctl start factorio

# Set up backup cron job
cat > /opt/factorio/scripts/backup.sh <<'BACKUPSCRIPT'
#!/bin/bash
S3_BUCKET="${S3_BUCKET_NAME}"
AWS_REGION="${AWS_REGION}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup saves
aws s3 sync /opt/factorio/bin/saves/ s3://$S3_BUCKET/backups/$TIMESTAMP/saves/ --region $AWS_REGION

# Keep only latest save in main saves folder
aws s3 sync /opt/factorio/bin/saves/ s3://$S3_BUCKET/saves/ --region $AWS_REGION --delete
BACKUPSCRIPT

chmod +x /opt/factorio/scripts/backup.sh
chown factorio:factorio /opt/factorio/scripts/backup.sh

if [ "${AUTO_BACKUP_ENABLED}" = "true" ]; then
    echo "0 */${BACKUP_INTERVAL_HOURS} * * * /opt/factorio/scripts/backup.sh" | crontab -u factorio -
fi

echo "Factorio server installation completed"
USERDATA

    # Replace variables in user data
    sed -i "s|\${FACTORIO_VERSION}|$FACTORIO_VERSION|g" /tmp/user-data.sh
    sed -i "s|\${FACTORIO_SERVER_NAME}|$FACTORIO_SERVER_NAME|g" /tmp/user-data.sh
    sed -i "s|\${FACTORIO_DESCRIPTION}|$FACTORIO_DESCRIPTION|g" /tmp/user-data.sh
    sed -i "s|\${FACTORIO_MAX_PLAYERS}|$FACTORIO_MAX_PLAYERS|g" /tmp/user-data.sh
    sed -i "s|\${FACTORIO_VISIBILITY_PUBLIC}|$FACTORIO_VISIBILITY_PUBLIC|g" /tmp/user-data.sh
    sed -i "s|\${FACTORIO_USERNAME}|$FACTORIO_USERNAME|g" /tmp/user-data.sh
    sed -i "s|\${FACTORIO_TOKEN}|$FACTORIO_TOKEN|g" /tmp/user-data.sh
    sed -i "s|\${S3_BUCKET_NAME}|$S3_BUCKET_NAME|g" /tmp/user-data.sh
    sed -i "s|\${AWS_REGION}|$AWS_REGION|g" /tmp/user-data.sh
    sed -i "s|\${AUTO_BACKUP_ENABLED}|$AUTO_BACKUP_ENABLED|g" /tmp/user-data.sh
    sed -i "s|\${BACKUP_INTERVAL_HOURS}|$BACKUP_INTERVAL_HOURS|g" /tmp/user-data.sh
}

launch_instance() {
    local ami_id=$(get_latest_amazon_linux_ami)
    
    log_info "Launching EC2 instance..."
    log_info "AMI: $ami_id"
    log_info "Instance Type: $EC2_INSTANCE_TYPE"
    
    create_user_data_script
    
    local instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$EC2_INSTANCE_TYPE" \
        --key-name "$KEY_PAIR_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --iam-instance-profile "Name=$IAM_INSTANCE_PROFILE" \
        --user-data file:///tmp/user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=factorio-server},{Key=Application,Value=Factorio}]" \
        --region "$AWS_REGION" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    log_info "Launched instance: $instance_id"
    
    # Wait for instance to be running
    log_info "Waiting for instance to start..."
    aws ec2 wait instance-running --instance-ids "$instance_id" --region "$AWS_REGION"
    
    # Get public IP
    local public_ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION")
    
    log_info "Instance is running!"
    log_info "Instance ID: $instance_id"
    log_info "Public IP: $public_ip"
    log_info ""
    log_info "The server is being configured. This may take several minutes."
    log_info "You can monitor the setup by connecting via SSH:"
    log_info "  ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$public_ip"
    log_info "  sudo journalctl -u factorio -f"
    log_info ""
    log_info "Once setup is complete, connect to the server at: $public_ip:34197"
}

main() {
    log_info "Starting Factorio Server Deployment"
    
    # Check if instance already exists
    local existing_instance=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=factorio-server" \
        "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [ "$existing_instance" != "" ] && [ "$existing_instance" != "None" ]; then
        log_warn "A Factorio server instance already exists: $existing_instance"
        read -p "Do you want to terminate it and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Terminating existing instance..."
            aws ec2 terminate-instances --instance-ids "$existing_instance" --region "$AWS_REGION"
            aws ec2 wait instance-terminated --instance-ids "$existing_instance" --region "$AWS_REGION"
            log_info "Instance terminated"
        else
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    launch_instance
}

main "$@"
