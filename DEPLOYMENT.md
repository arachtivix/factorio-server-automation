# Deployment Guide

This guide walks through deploying a Factorio server from scratch.

## Prerequisites Checklist

- [ ] AWS account with admin access
- [ ] AWS CLI installed (`aws --version`)
- [ ] AWS CLI configured (`aws configure`)
- [ ] Git installed
- [ ] SSH client available
- [ ] (Optional) jq installed for JSON processing

## Step-by-Step Deployment

### 1. Prepare Configuration

```bash
# Clone the repository
git clone https://github.com/arachtivix/factorio-server-automation.git
cd factorio-server-automation

# Copy and edit configuration
cp config/factorio-server.conf.example config/factorio-server.conf
```

Edit `config/factorio-server.conf`:

```bash
# Required settings
AWS_REGION=us-east-1                    # Your preferred AWS region
KEY_PAIR_NAME=factorio-server-key       # Name for SSH key
EC2_INSTANCE_TYPE=t3.medium            # Instance size

# Factorio settings
FACTORIO_SERVER_NAME="My Server"       # Your server name
FACTORIO_DESCRIPTION="Automated Server"
FACTORIO_MAX_PLAYERS=10

# For public multiplayer, add your Factorio credentials:
FACTORIO_USERNAME="your-username"      # From factorio.com
FACTORIO_TOKEN="your-token"            # From factorio.com profile
FACTORIO_VISIBILITY_PUBLIC=true        # Make server public
```

### 2. Run AWS Setup

```bash
./scripts/setup-aws.sh
```

**Expected Output:**
```
[INFO] Starting Factorio Server AWS Setup
[INFO] Region: us-east-1
[INFO] AWS CLI is properly configured
[INFO] Creating S3 bucket: factorio-server-123456789012
[INFO] Created S3 bucket: factorio-server-123456789012
[INFO] Enabled versioning on bucket
[INFO] Created folder structure in bucket
[INFO] Set lifecycle policy for backups (30 days retention)
[INFO] Creating IAM role: factorio-server-role
[INFO] Created IAM role: factorio-server-role
[INFO] Created IAM policy: factorio-server-policy
[INFO] Attached policy to role
[INFO] Created instance profile: factorio-server-role
[INFO] Creating security group: factorio-server-sg
[INFO] Created security group: sg-0123456789abcdef
[INFO] Added security group rules
[INFO] Creating new key pair: factorio-server-key
[INFO] Created key pair and saved to factorio-server-key.pem
[WARN] IMPORTANT: Keep this key file safe! It's required to access your server.
[INFO] Saved AWS resource configuration to config/aws-resources.conf
==========================================
[INFO] Setup completed successfully!
==========================================
[INFO] S3 Bucket: factorio-server-123456789012
[INFO] IAM Role: factorio-server-role
[INFO] Security Group: sg-0123456789abcdef
[INFO] Key Pair: factorio-server-key
```

**What was created:**
- S3 bucket with versioning enabled
- IAM role and policy for the EC2 instance
- Security group with Factorio ports open
- SSH key pair (saved as `factorio-server-key.pem`)

### 3. Deploy the Server

```bash
./scripts/deploy-server.sh
```

**Expected Output:**
```
[INFO] Starting Factorio Server Deployment
[INFO] Launching EC2 instance...
[INFO] AMI: ami-0c55b159cbfafe1f0
[INFO] Instance Type: t3.medium
[INFO] Launched instance: i-0123456789abcdef0
[INFO] Waiting for instance to start...
[INFO] Instance is running!
[INFO] Instance ID: i-0123456789abcdef0
[INFO] Public IP: 54.123.45.67
[INFO] The server is being configured. This may take several minutes.
[INFO] You can monitor the setup by connecting via SSH:
[INFO]   ssh -i factorio-server-key.pem ec2-user@54.123.45.67
[INFO]   sudo journalctl -u factorio -f
[INFO] Once setup is complete, connect to the server at: 54.123.45.67:34197
```

**Wait Time:** 5-10 minutes for full installation and server startup

### 4. Verify Server is Running

```bash
./scripts/manage-factorio.sh status
```

**Expected Output:**
```
========================================
Factorio Server Status
========================================
[INFO] Instance ID: i-0123456789abcdef0
[INFO] Public IP: 54.123.45.67

[INFO] Server Version:
1.1.90

[INFO] Service Status:
● factorio.service - Factorio Dedicated Server
   Loaded: loaded (/etc/systemd/system/factorio.service; enabled; vendor preset: disabled)
   Active: active (running) since ...
```

### 5. Connect to Your Server

**From Factorio Game Client:**
1. Open Factorio
2. Click "Multiplayer"
3. Click "Browse"
4. Search for your server name OR
5. Click "Direct Connect"
6. Enter: `54.123.45.67:34197`

**Via SSH (for administration):**
```bash
ssh -i factorio-server-key.pem ec2-user@54.123.45.67

# View logs
sudo journalctl -u factorio -f

# Check server status
sudo systemctl status factorio
```

## Common Post-Deployment Tasks

### Install Mods

1. Edit `config/mods.json`:
```json
{
  "mods": [
    {
      "name": "base",
      "enabled": true
    },
    {
      "name": "even-distribution",
      "enabled": true
    }
  ]
}
```

2. Install mods:
```bash
./scripts/manage-factorio.sh install-mods
```

### Backup Save Games

Manual backup:
```bash
./scripts/manage-factorio.sh backup-saves
```

Automatic backups are configured by default (every 6 hours).

### Update Server Version

```bash
# Update to latest stable
./scripts/manage-factorio.sh deploy stable

# Or specific version
./scripts/manage-factorio.sh deploy 1.1.91
```

### Stop Server (to save costs)

```bash
# Stop the instance
./scripts/stop-server.sh

# Start it later
./scripts/start-server.sh
```

## Troubleshooting

### Server Won't Start

**Check logs:**
```bash
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
sudo journalctl -u factorio -n 100 --no-pager
```

**Common issues:**
- Insufficient permissions: Check IAM role
- Network issues: Verify security group rules
- Invalid configuration: Check `/opt/factorio/config/server-settings.json`

### Can't Connect to Server

1. **Verify server is running:**
   ```bash
   ./scripts/manage-factorio.sh status
   ```

2. **Check security group:**
   - UDP port 34197 should be open to 0.0.0.0/0
   - Verify in AWS Console > EC2 > Security Groups

3. **Check game version:**
   - Client and server versions must match
   - Update client or server as needed

### SSH Connection Refused

1. **Verify key permissions:**
   ```bash
   chmod 400 factorio-server-key.pem
   ```

2. **Check security group allows your IP:**
   - SSH (port 22) must allow your IP address
   - Update `ALLOWED_CIDR_BLOCKS` in config if needed

### S3 Access Issues

**Verify IAM role:**
```bash
aws iam get-role --role-name factorio-server-role
aws iam list-attached-role-policies --role-name factorio-server-role
```

**Check instance profile:**
```bash
aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'
```

## Advanced Configuration

### Use a Different Region

1. Update `config/factorio-server.conf`:
   ```bash
   AWS_REGION=eu-west-1
   ```

2. Re-run setup:
   ```bash
   ./scripts/setup-aws.sh
   ```

### Restrict SSH Access

1. Find your IP:
   ```bash
   curl ifconfig.me
   ```

2. Update `config/factorio-server.conf`:
   ```bash
   ALLOWED_CIDR_BLOCKS=203.0.113.0/32
   ```

3. Update security group:
   ```bash
   # Remove old rule
   aws ec2 revoke-security-group-ingress \
     --group-id <SG_ID> \
     --protocol tcp --port 22 --cidr 0.0.0.0/0
   
   # Add new rule
   aws ec2 authorize-security-group-ingress \
     --group-id <SG_ID> \
     --protocol tcp --port 22 --cidr 203.0.113.0/32
   ```

### Change Instance Type

1. Stop the server:
   ```bash
   ./scripts/stop-server.sh
   ```

2. Change instance type:
   ```bash
   aws ec2 modify-instance-attribute \
     --instance-id <INSTANCE_ID> \
     --instance-type "{\"Value\": \"t3.large\"}"
   ```

3. Start the server:
   ```bash
   ./scripts/start-server.sh
   ```

### Enable CloudWatch Logs

Add to user-data.sh in deploy-server.sh:
```bash
# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure to send factorio logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/factorio/server",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
```

## Next Steps

- Set up scheduled snapshots of the EC2 instance
- Configure CloudWatch alarms for monitoring
- Set up Route53 for a custom domain name
- Implement automated testing of deployments
- Create scripts for automated world generation

## Cost Management

**Monthly Cost Estimate (us-east-1):**
- EC2 t3.medium (24/7): ~$30
- S3 storage (50GB): ~$1.15
- Data transfer (100GB): ~$9
- **Total: ~$40-50/month**

**Cost Reduction:**
- Stop instance when not playing: Save ~$20-25/month
- Use t3.small for smaller games: Save ~$15/month
- Enable S3 Intelligent-Tiering: Save on storage

## Support

If you encounter issues:
1. Check this guide's troubleshooting section
2. Review logs with `journalctl`
3. Check AWS Console for resource status
4. Open an issue on GitHub with details
