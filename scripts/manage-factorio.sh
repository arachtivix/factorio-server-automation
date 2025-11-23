#!/bin/bash
#
# Factorio Server Management Script
# Manages server versions, mods, saves, and rollbacks
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

# Load configuration
if [ -f "$CONFIG_DIR/factorio-server.conf" ]; then
    source "$CONFIG_DIR/factorio-server.conf"
fi

if [ -f "$CONFIG_DIR/aws-resources.conf" ]; then
    source "$CONFIG_DIR/aws-resources.conf"
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

get_instance_id() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=factorio-server" \
        "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo ""
}

get_instance_ip() {
    local instance_id=$1
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text \
        --region "$AWS_REGION"
}

ssh_exec() {
    local instance_ip=$1
    shift
    ssh -i "$PROJECT_ROOT/${KEY_PAIR_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        ec2-user@"$instance_ip" "$@"
}

list_versions() {
    log_section "Available Factorio Versions in S3"
    
    aws s3 ls "s3://${S3_BUCKET_NAME}/server-binaries/" --region "$AWS_REGION" | grep -E "PRE|factorio" || {
        log_warn "No server versions found in S3"
        return
    }
}

backup_current_version() {
    local instance_id=$(get_instance_id)
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_error "No running Factorio server instance found"
        return 1
    fi
    
    local instance_ip=$(get_instance_ip "$instance_id")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    log_info "Backing up current server version..."
    
    # Get current version info
    local current_version=$(ssh_exec "$instance_ip" "cat /opt/factorio/bin/data/base/info.json 2>/dev/null | jq -r .version" || echo "unknown")
    
    log_info "Current version: $current_version"
    log_info "Backing up to S3..."
    
    # Create tarball of current installation
    ssh_exec "$instance_ip" "sudo tar -czf /tmp/factorio-backup-${timestamp}.tar.gz -C /opt/factorio/bin ."
    
    # Download and upload to S3
    scp -i "$PROJECT_ROOT/${KEY_PAIR_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "ec2-user@${instance_ip}:/tmp/factorio-backup-${timestamp}.tar.gz" \
        /tmp/
    
    aws s3 cp "/tmp/factorio-backup-${timestamp}.tar.gz" \
        "s3://${S3_BUCKET_NAME}/server-binaries/backups/version-${current_version}-${timestamp}.tar.gz" \
        --region "$AWS_REGION"
    
    # Cleanup
    ssh_exec "$instance_ip" "sudo rm /tmp/factorio-backup-${timestamp}.tar.gz"
    rm -f "/tmp/factorio-backup-${timestamp}.tar.gz"
    
    log_info "Backup completed: version-${current_version}-${timestamp}.tar.gz"
}

deploy_version() {
    local version=$1
    local instance_id=$(get_instance_id)
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_error "No running Factorio server instance found"
        return 1
    fi
    
    local instance_ip=$(get_instance_ip "$instance_id")
    
    log_info "Deploying Factorio version: $version"
    
    # Backup current version first
    backup_current_version
    
    # Stop the server
    log_info "Stopping Factorio server..."
    ssh_exec "$instance_ip" "sudo systemctl stop factorio"
    
    # Download new version
    log_info "Downloading Factorio version $version..."
    
    if [ "$version" = "stable" ] || [ "$version" = "latest" ]; then
        DOWNLOAD_URL="https://factorio.com/get-download/stable/headless/linux64"
    else
        DOWNLOAD_URL="https://factorio.com/get-download/${version}/headless/linux64"
    fi
    
    ssh_exec "$instance_ip" "cd /tmp && wget -O factorio_headless.tar.xz '$DOWNLOAD_URL'"
    
    # Backup mods and saves
    log_info "Preserving saves and mods..."
    ssh_exec "$instance_ip" "sudo cp -r /opt/factorio/bin/saves /tmp/saves-backup"
    ssh_exec "$instance_ip" "sudo cp -r /opt/factorio/bin/mods /tmp/mods-backup"
    
    # Extract new version
    log_info "Installing new version..."
    ssh_exec "$instance_ip" "sudo rm -rf /opt/factorio/bin/*"
    ssh_exec "$instance_ip" "cd /tmp && tar -xf factorio_headless.tar.xz"
    ssh_exec "$instance_ip" "sudo cp -r /tmp/factorio/* /opt/factorio/bin/"
    
    # Restore saves and mods
    ssh_exec "$instance_ip" "sudo rm -rf /opt/factorio/bin/saves"
    ssh_exec "$instance_ip" "sudo rm -rf /opt/factorio/bin/mods"
    ssh_exec "$instance_ip" "sudo mv /tmp/saves-backup /opt/factorio/bin/saves"
    ssh_exec "$instance_ip" "sudo mv /tmp/mods-backup /opt/factorio/bin/mods"
    
    # Fix permissions
    ssh_exec "$instance_ip" "sudo chown -R factorio:factorio /opt/factorio/bin"
    
    # Cleanup
    ssh_exec "$instance_ip" "rm -f /tmp/factorio_headless.tar.xz"
    ssh_exec "$instance_ip" "rm -rf /tmp/factorio"
    
    # Start the server
    log_info "Starting Factorio server..."
    ssh_exec "$instance_ip" "sudo systemctl start factorio"
    
    # Verify version
    sleep 5
    local new_version=$(ssh_exec "$instance_ip" "cat /opt/factorio/bin/data/base/info.json | jq -r .version")
    
    log_info "Successfully deployed version: $new_version"
    log_info "Server is starting up. Check status with: sudo systemctl status factorio"
}

rollback_version() {
    local backup_file=$1
    local instance_id=$(get_instance_id)
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_error "No running Factorio server instance found"
        return 1
    fi
    
    local instance_ip=$(get_instance_ip "$instance_id")
    
    log_warn "Rolling back to backup: $backup_file"
    
    # Download backup from S3
    log_info "Downloading backup from S3..."
    aws s3 cp "s3://${S3_BUCKET_NAME}/server-binaries/backups/${backup_file}" \
        /tmp/rollback.tar.gz \
        --region "$AWS_REGION"
    
    # Upload to instance
    scp -i "$PROJECT_ROOT/${KEY_PAIR_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        /tmp/rollback.tar.gz \
        "ec2-user@${instance_ip}:/tmp/"
    
    # Stop server
    log_info "Stopping Factorio server..."
    ssh_exec "$instance_ip" "sudo systemctl stop factorio"
    
    # Restore backup
    log_info "Restoring backup..."
    ssh_exec "$instance_ip" "sudo rm -rf /opt/factorio/bin/*"
    ssh_exec "$instance_ip" "sudo tar -xzf /tmp/rollback.tar.gz -C /opt/factorio/bin"
    ssh_exec "$instance_ip" "sudo chown -R factorio:factorio /opt/factorio/bin"
    
    # Cleanup
    ssh_exec "$instance_ip" "rm /tmp/rollback.tar.gz"
    rm /tmp/rollback.tar.gz
    
    # Start server
    log_info "Starting Factorio server..."
    ssh_exec "$instance_ip" "sudo systemctl start factorio"
    
    log_info "Rollback completed successfully"
}

install_mods() {
    local instance_id=$(get_instance_id)
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_error "No running Factorio server instance found"
        return 1
    fi
    
    local instance_ip=$(get_instance_ip "$instance_id")
    
    log_info "Installing mods from $MOD_LIST_FILE..."
    
    if [ ! -f "$PROJECT_ROOT/$MOD_LIST_FILE" ]; then
        log_error "Mod list file not found: $MOD_LIST_FILE"
        return 1
    fi
    
    # Copy mod list to server
    scp -i "$PROJECT_ROOT/${KEY_PAIR_NAME}.pem" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$PROJECT_ROOT/$MOD_LIST_FILE" \
        "ec2-user@${instance_ip}:/tmp/mod-list.json"
    
    # Install mod list
    ssh_exec "$instance_ip" "sudo cp /tmp/mod-list.json /opt/factorio/bin/mods/mod-list.json"
    ssh_exec "$instance_ip" "sudo chown factorio:factorio /opt/factorio/bin/mods/mod-list.json"
    
    log_info "Mod list installed. Restart the server to apply changes."
    
    read -p "Do you want to restart the server now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ssh_exec "$instance_ip" "sudo systemctl restart factorio"
        log_info "Server restarted"
    fi
}

backup_saves() {
    local instance_id=$(get_instance_id)
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_error "No running Factorio server instance found"
        return 1
    fi
    
    local instance_ip=$(get_instance_ip "$instance_id")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    log_info "Backing up save games..."
    
    # Run backup script on server
    ssh_exec "$instance_ip" "sudo -u factorio /opt/factorio/scripts/backup.sh"
    
    log_info "Save games backed up to S3: backups/${timestamp}/saves/"
}

restore_saves() {
    local backup_timestamp=$1
    local instance_id=$(get_instance_id)
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_error "No running Factorio server instance found"
        return 1
    fi
    
    local instance_ip=$(get_instance_ip "$instance_id")
    
    log_info "Restoring saves from backup: $backup_timestamp"
    
    # Stop server
    ssh_exec "$instance_ip" "sudo systemctl stop factorio"
    
    # Download and restore saves
    ssh_exec "$instance_ip" "sudo rm -rf /opt/factorio/bin/saves/*"
    ssh_exec "$instance_ip" "aws s3 sync s3://${S3_BUCKET_NAME}/backups/${backup_timestamp}/saves/ /opt/factorio/bin/saves/ --region ${AWS_REGION}"
    ssh_exec "$instance_ip" "sudo chown -R factorio:factorio /opt/factorio/bin/saves"
    
    # Start server
    ssh_exec "$instance_ip" "sudo systemctl start factorio"
    
    log_info "Saves restored successfully"
}

show_status() {
    local instance_id=$(get_instance_id)
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_warn "No running Factorio server instance found"
        return
    fi
    
    local instance_ip=$(get_instance_ip "$instance_id")
    
    log_section "Factorio Server Status"
    log_info "Instance ID: $instance_id"
    log_info "Public IP: $instance_ip"
    
    echo ""
    log_info "Server Version:"
    ssh_exec "$instance_ip" "cat /opt/factorio/bin/data/base/info.json 2>/dev/null | jq -r .version" || log_warn "Could not determine version"
    
    echo ""
    log_info "Service Status:"
    ssh_exec "$instance_ip" "sudo systemctl status factorio --no-pager" || true
    
    echo ""
    log_info "Recent Logs:"
    ssh_exec "$instance_ip" "sudo journalctl -u factorio -n 20 --no-pager" || true
}

show_help() {
    cat <<EOF
Factorio Server Management Script

Usage: $0 <command> [options]

Commands:
    status              Show server status and information
    list-versions       List available server versions in S3
    deploy <version>    Deploy a specific Factorio version (e.g., "1.1.90" or "stable")
    backup              Backup current server version
    rollback <file>     Rollback to a previous backup
    install-mods        Install mods from mod list file
    backup-saves        Backup current save games to S3
    restore-saves <ts>  Restore saves from backup timestamp
    help                Show this help message

Examples:
    $0 status
    $0 deploy stable
    $0 deploy 1.1.90
    $0 backup
    $0 rollback version-1.1.90-20231115_120000.tar.gz
    $0 install-mods
    $0 backup-saves
    $0 restore-saves 20231115_120000

EOF
}

main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    local command=$1
    shift
    
    case "$command" in
        status)
            show_status
            ;;
        list-versions)
            list_versions
            ;;
        deploy)
            if [ $# -eq 0 ]; then
                log_error "Version required. Usage: $0 deploy <version>"
                exit 1
            fi
            deploy_version "$1"
            ;;
        backup)
            backup_current_version
            ;;
        rollback)
            if [ $# -eq 0 ]; then
                log_error "Backup file required. Usage: $0 rollback <backup-file>"
                exit 1
            fi
            rollback_version "$1"
            ;;
        install-mods)
            install_mods
            ;;
        backup-saves)
            backup_saves
            ;;
        restore-saves)
            if [ $# -eq 0 ]; then
                log_error "Timestamp required. Usage: $0 restore-saves <timestamp>"
                exit 1
            fi
            restore_saves "$1"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
