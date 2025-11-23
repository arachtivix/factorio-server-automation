# Factorio Server Automation on AWS EC2

This repository provides automation scripts to deploy and manage a Factorio dedicated server on AWS EC2. It includes features for version management, automated backups, mod installation, and easy rollback capabilities.

## Features

- **Automated AWS Setup**: One-command setup of all required AWS resources (S3, IAM roles, Security Groups)
- **Version Management**: Easy deployment of specific Factorio server versions
- **Rollback Capability**: Backup and rollback to previous server versions
- **Mod Management**: Install and manage mods from a configuration file
- **Automated Backups**: Automatic save game backups to S3 with configurable retention
- **Save Game Management**: Backup and restore save games
- **Security**: Proper IAM roles with least-privilege access

## Architecture

The automation uses the following AWS resources:

- **EC2 Instance**: Runs the Factorio server (default: t3.medium)
- **S3 Bucket**: Stores server binaries, backups, saves, and mods
- **IAM Role**: Provides EC2 instance access to S3 for backups and version management
- **Security Group**: Controls network access (SSH, Factorio game port, RCON)

## Prerequisites

1. **AWS Account** with appropriate permissions to create:
   - EC2 instances
   - S3 buckets
   - IAM roles and policies
   - Security groups

2. **AWS CLI** installed and configured with credentials:
   ```bash
   aws configure
   ```

3. **SSH client** for connecting to the server

4. **jq** (for JSON processing - optional but recommended)

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/arachtivix/factorio-server-automation.git
cd factorio-server-automation
```

### 2. Run Pre-flight Check (Optional)

Verify your environment has all prerequisites:

```bash
./scripts/preflight-check.sh
```

This checks for AWS CLI, credentials, and other requirements.

### 3. Configure the Server

Copy the example configuration and edit it with your preferences:

```bash
cp config/factorio-server.conf.example config/factorio-server.conf
nano config/factorio-server.conf
```

Key configuration options:
- `AWS_REGION`: AWS region for deployment
- `EC2_INSTANCE_TYPE`: Instance size (t3.medium recommended)
- `FACTORIO_SERVER_NAME`: Your server name
- `FACTORIO_USERNAME` and `FACTORIO_TOKEN`: Your Factorio credentials (for multiplayer)

### 4. Run AWS Setup

This creates all necessary AWS resources:

```bash
./scripts/setup-aws.sh
```

This script will:
- Create an S3 bucket for storing server data
- Create IAM roles and policies
- Create a security group
- Generate an SSH key pair

**Important**: The SSH key (`.pem` file) will be saved in the project root. Keep it safe!

### 5. Deploy the Server

```bash
./scripts/deploy-server.sh
```

This will:
- Launch an EC2 instance
- Install Factorio server
- Configure automatic backups
- Start the server

The deployment takes several minutes. You'll see the server's IP address when complete.

### 6. Connect to Your Server

Use the Factorio game client to connect to: `<SERVER_IP>:34197`

## Server Management

### Check Server Status

```bash
./scripts/manage-factorio.sh status
```

Shows:
- Instance information
- Server version
- Service status
- Recent logs

### Deploy a Different Version

Deploy the latest stable version:
```bash
./scripts/manage-factorio.sh deploy stable
```

Deploy a specific version:
```bash
./scripts/manage-factorio.sh deploy 1.1.90
```

The script will:
- Backup the current version
- Download and install the new version
- Preserve saves and mods
- Restart the server

### Backup Current Version

```bash
./scripts/manage-factorio.sh backup
```

Creates a backup of the current server installation in S3.

### Rollback to Previous Version

List available backups:
```bash
./scripts/manage-factorio.sh list-versions
```

Rollback to a specific backup:
```bash
./scripts/manage-factorio.sh rollback version-1.1.90-20231115_120000.tar.gz
```

### Manage Mods

1. Edit `config/mods.json` to list your desired mods
2. Install mods:
   ```bash
   ./scripts/manage-factorio.sh install-mods
   ```

Example mod list:
```json
{
  "mods": [
    {
      "name": "base",
      "enabled": true
    },
    {
      "name": "your-mod-name",
      "enabled": true
    }
  ]
}
```

### Backup Save Games

Manual backup:
```bash
./scripts/manage-factorio.sh backup-saves
```

Automatic backups are configured to run every 6 hours (configurable in `factorio-server.conf`).

### Restore Save Games

List available backups in S3, then restore:
```bash
./scripts/manage-factorio.sh restore-saves 20231115_120000
```

### SSH Access

Connect to the server:
```bash
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
```

View server logs:
```bash
sudo journalctl -u factorio -f
```

## Configuration Files

### config/factorio-server.conf

Main configuration file with AWS and Factorio settings.

### config/mods.json

List of mods to install on the server.

### config/aws-resources.conf

Auto-generated file containing AWS resource IDs (created by setup-aws.sh).

### config/iam-policy-server-role.json

IAM policy defining permissions for the EC2 instance.

## Cost Estimation

Approximate AWS costs (us-east-1, as of 2024):

- **EC2 t3.medium**: ~$30/month (24/7 operation)
- **S3 Storage**: ~$0.023/GB/month
- **Data Transfer**: Variable based on usage

To reduce costs:
- Stop the instance when not playing (remember to back up first)
- Use smaller instance types for smaller games
- Adjust S3 lifecycle policies

## Troubleshooting

### Server won't start

Check logs:
```bash
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
sudo journalctl -u factorio -n 50
```

### Can't connect to server

1. Verify security group allows UDP port 34197
2. Check server is running: `./scripts/manage-factorio.sh status`
3. Verify your public IP hasn't changed if you restricted SSH access

### Backup fails

Verify IAM role has S3 permissions:
```bash
aws iam get-role --role-name factorio-server-role
```

## Security Considerations

1. **SSH Access**: The default configuration allows SSH from anywhere. Restrict `ALLOWED_CIDR_BLOCKS` in config to your IP range.

2. **Key Management**: Keep your `.pem` file secure and never commit it to version control.

3. **Factorio Credentials**: Store your Factorio username/token securely. Consider using AWS Secrets Manager for production.

4. **Updates**: Regularly update the server and OS packages.

## Cleanup

To completely remove all AWS resources:

```bash
# Terminate the EC2 instance
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

# Delete the S3 bucket (after backing up any data you need)
aws s3 rb s3://<BUCKET_NAME> --force

# Delete the security group
aws ec2 delete-security-group --group-id <SG_ID>

# Delete IAM resources
aws iam detach-role-policy --role-name factorio-server-role --policy-arn <POLICY_ARN>
aws iam remove-role-from-instance-profile --instance-profile-name factorio-server-role --role-name factorio-server-role
aws iam delete-instance-profile --instance-profile-name factorio-server-role
aws iam delete-role --role-name factorio-server-role
aws iam delete-policy --policy-arn <POLICY_ARN>

# Delete the key pair
aws ec2 delete-key-pair --key-name factorio-server-key
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is open source and available under the MIT License.

## Acknowledgments

- Factorio by Wube Software
- AWS for cloud infrastructure

## Support

For issues and questions:
- Open an issue on GitHub
- Check Factorio server documentation: https://wiki.factorio.com/Multiplayer