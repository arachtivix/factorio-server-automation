# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-11-23

### Added

#### Core Infrastructure
- AWS setup script (`setup-aws.sh`) for automated resource provisioning
- S3 bucket creation with versioning and lifecycle policies
- IAM role and policy creation for EC2 instance
- Security group configuration with proper port access
- SSH key pair generation and management

#### Server Deployment
- Automated EC2 instance deployment (`deploy-server.sh`)
- Factorio server installation and configuration
- systemd service setup for server management
- Automated backup cron job configuration
- Support for custom server settings

#### Server Management
- Comprehensive management script (`manage-factorio.sh`) with commands:
  - `status` - Show server status and information
  - `deploy <version>` - Deploy specific Factorio versions
  - `backup` - Backup current server version
  - `rollback <file>` - Rollback to previous versions
  - `install-mods` - Install mods from configuration
  - `backup-saves` - Manual save game backups
  - `restore-saves <timestamp>` - Restore save games
  - `list-versions` - List available versions in S3

#### Instance Management
- Server start script (`start-server.sh`)
- Server stop script (`stop-server.sh`)
- Support for cost optimization by stopping unused instances

#### Configuration
- Example configuration file with all settings
- Mod list configuration (JSON format)
- IAM policy definitions
- IAM trust policy for EC2 role

#### Documentation
- Comprehensive README with features and usage
- Quick Start guide for rapid deployment
- Detailed Deployment guide with step-by-step instructions
- Architecture documentation with diagrams
- Operations runbook for common tasks
- Contributing guidelines
- MIT License

#### Security
- Least-privilege IAM permissions
- Security group with restricted access
- Support for CIDR-based access control
- S3 versioning for data protection
- Automated backups with retention policies

### Features

- **Version Management**: Deploy any Factorio version with automatic backup
- **Rollback Support**: Easy rollback to any previous version
- **Mod Management**: Install and manage mods from configuration file
- **Automated Backups**: Configurable scheduled backups to S3
- **Save Management**: Backup and restore save games on demand
- **Cost Optimization**: Start/stop instances to reduce AWS costs
- **Security**: Proper IAM roles and network security
- **Monitoring**: Built-in status checks and logging

### Technical Details

- Bash scripts with proper error handling
- AWS CLI integration for all operations
- S3 for persistent storage and backups
- systemd for service management
- CloudWatch-compatible logging
- JSON configuration files
- Automated cleanup with lifecycle policies

## [Unreleased]

### Planned Features
- Terraform modules for infrastructure as code
- CloudWatch monitoring and alerting
- SNS notifications for events
- Multi-region support
- Web-based management interface
- Docker support for local development
- Automated testing framework
- Performance metrics dashboard

---

[1.0.0]: https://github.com/arachtivix/factorio-server-automation/releases/tag/v1.0.0
