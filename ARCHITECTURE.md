# Architecture Overview

## System Components

### AWS Resources

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                             │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    EC2 Instance                        │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │         Factorio Server (systemd service)        │  │ │
│  │  │  - Game server on UDP 34197                      │  │ │
│  │  │  - RCON on TCP 27015                             │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │         Backup Cron Job                          │  │ │
│  │  │  - Runs every N hours                            │  │ │
│  │  │  - Syncs saves to S3                             │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  │                                                        │ │
│  │  IAM Instance Profile: factorio-server-role           │ │
│  └────────────────────────────────────────────────────────┘ │
│                              │                              │
│                              │ S3 Access                    │
│                              ▼                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    S3 Bucket                           │ │
│  │                                                        │ │
│  │  server-binaries/         - Factorio server versions  │ │
│  │    ├─ backups/           - Version backups            │ │
│  │                                                        │ │
│  │  saves/                   - Current save games        │ │
│  │                                                        │ │
│  │  backups/                 - Historical save backups   │ │
│  │    ├─ YYYYMMDD_HHMMSS/   - Timestamped backups       │ │
│  │                                                        │ │
│  │  mods/                    - Mod files                 │ │
│  │                                                        │ │
│  │  Lifecycle Policy: Delete backups > 30 days           │ │
│  │  Versioning: Enabled                                  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Security Group                            │ │
│  │                                                        │ │
│  │  Inbound Rules:                                        │ │
│  │  - TCP 22 (SSH) from configured CIDR                   │ │
│  │  - UDP 34197 (Factorio) from 0.0.0.0/0                │ │
│  │  - TCP 27015 (RCON) from configured CIDR              │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Management Flow

```
┌──────────────────┐
│  Local Machine   │
└────────┬─────────┘
         │
         │ 1. Run setup-aws.sh
         │    - Creates S3 bucket
         │    - Creates IAM role
         │    - Creates Security Group
         │    - Generates SSH key
         │
         ▼
┌──────────────────┐
│   AWS Resources  │
│     Created      │
└────────┬─────────┘
         │
         │ 2. Run deploy-server.sh
         │    - Launches EC2 instance
         │    - Installs Factorio
         │    - Configures backups
         │
         ▼
┌──────────────────┐
│ Running Server   │
└────────┬─────────┘
         │
         │ 3. Use manage-factorio.sh
         │    - Deploy versions
         │    - Backup/Rollback
         │    - Manage mods
         │    - Manage saves
         │
         ▼
┌──────────────────┐
│  Server Managed  │
└──────────────────┘
```

## IAM Permissions Model

### Setup Phase (Your AWS Credentials)
Requires permissions to create:
- S3 buckets
- IAM roles and policies
- EC2 security groups
- EC2 key pairs
- EC2 instances

### Runtime Phase (EC2 Instance Profile)
Limited permissions:
- S3 read/write to specific bucket
- EC2 describe instances (for self-discovery)

This follows the principle of least privilege - the server only has access to what it needs.

## Data Flow

### Version Deployment
1. User runs `manage-factorio.sh deploy <version>`
2. Script backs up current installation to S3
3. Downloads new version from Factorio.com
4. Preserves saves and mods
5. Installs new version
6. Restarts server

### Backup Process
1. Cron job triggers backup script
2. Script creates tarball of saves
3. Uploads to S3 with timestamp
4. S3 lifecycle policy removes old backups

### Rollback Process
1. User selects backup from S3
2. Script downloads backup
3. Stops server
4. Restores backup
5. Restarts server

## Directory Structure on EC2

```
/opt/factorio/
├── bin/              # Factorio server installation
│   ├── bin/         # Server binary
│   ├── data/        # Game data
│   ├── saves/       # Save games
│   └── mods/        # Installed mods
├── config/          # Configuration files
│   └── server-settings.json
└── scripts/         # Management scripts
    └── backup.sh    # Automated backup script
```

## Scaling Considerations

### Vertical Scaling
- Increase EC2 instance type for larger games
- t3.medium → t3.large → t3.xlarge

### Performance
- Use provisioned IOPS for better disk performance
- Consider using instance storage for saves (with S3 sync)

### High Availability
- Not implemented by default (single instance)
- Could add:
  - Auto Scaling Group for instance recovery
  - CloudWatch alarms for monitoring
  - SNS notifications for failures

## Security Best Practices

1. **Network Security**
   - Restrict SSH access to known IPs
   - Use VPN for admin access
   - Keep RCON port restricted

2. **Access Management**
   - Use IAM instance profiles (no embedded credentials)
   - Rotate SSH keys regularly
   - Enable MFA on AWS account

3. **Data Protection**
   - S3 versioning enabled
   - Regular backups to S3
   - Consider S3 bucket encryption

4. **Monitoring**
   - CloudWatch logs for systemd service
   - S3 access logging
   - EC2 instance monitoring

## Cost Optimization

1. **Stop instance when not playing**
   - Use start-server.sh / stop-server.sh
   - Saves EC2 compute costs

2. **S3 Storage**
   - Lifecycle policies clean old backups
   - Use S3 Intelligent-Tiering for long-term storage

3. **Data Transfer**
   - Consider reserved instances for 24/7 operation
   - Use CloudFront if needed for global distribution
