# Quick Start Guide

Get your Factorio server running in 5 minutes!

## Prerequisites

- AWS account
- AWS CLI installed and configured (`aws configure`)

## Steps

### 1. Get the Code

```bash
git clone https://github.com/arachtivix/factorio-server-automation.git
cd factorio-server-automation
```

### 2. Configure

```bash
cp config/factorio-server.conf.example config/factorio-server.conf
# Edit config/factorio-server.conf with your preferred settings
# At minimum, update AWS_REGION and FACTORIO_SERVER_NAME
```

### 3. Setup AWS Resources

```bash
./scripts/setup-aws.sh
```

This creates:
- S3 bucket for saves and backups
- IAM role for the server
- Security group for network access
- SSH key pair

**Save the SSH key!** It's saved as `factorio-server-key.pem`

### 4. Deploy Server

```bash
./scripts/deploy-server.sh
```

Wait 5-10 minutes for installation to complete.

### 5. Connect

The script will output your server IP. Connect in Factorio at:
```
<SERVER_IP>:34197
```

## That's It!

Your server is now running.

## Common Commands

```bash
# Check server status
./scripts/manage-factorio.sh status

# Update to latest version
./scripts/manage-factorio.sh deploy stable

# Stop server (save money)
./scripts/stop-server.sh

# Start server again
./scripts/start-server.sh

# Backup saves
./scripts/manage-factorio.sh backup-saves
```

## Need More Help?

- Full documentation: [README.md](README.md)
- Deployment guide: [DEPLOYMENT.md](DEPLOYMENT.md)
- Architecture details: [ARCHITECTURE.md](ARCHITECTURE.md)

## Costs

Expect ~$30-50/month for 24/7 operation.

Stop the server when not playing to reduce costs significantly!
