# Troubleshooting Guide

Common issues and their solutions.

## Installation Issues

### AWS CLI Not Found

**Error:** `aws: command not found`

**Solution:**
```bash
# Install AWS CLI v2 (recommended)
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version
```

### AWS Credentials Not Configured

**Error:** `Unable to locate credentials`

**Solution:**
```bash
aws configure
# Enter your:
# - AWS Access Key ID
# - AWS Secret Access Key  
# - Default region (e.g., us-east-1)
# - Output format (json recommended)
```

### Permission Denied Errors

**Error:** `An error occurred (UnauthorizedOperation) when calling...`

**Solution:** Your AWS user needs these permissions:
- EC2: Full access or specific instance/security group permissions
- S3: Create and manage buckets
- IAM: Create roles and policies

Ask your AWS administrator to grant necessary permissions.

## Deployment Issues

### S3 Bucket Already Exists

**Error:** `A conflicting conditional operation is currently in progress`

**Solution:**
The bucket name includes your AWS account ID, so this shouldn't happen. If it does:
```bash
# List buckets
aws s3 ls | grep factorio-server

# Use existing bucket or delete and recreate
aws s3 rb s3://factorio-server-XXXXX --force
```

### Key Pair Already Exists

**Error:** `InvalidKeyPair.Duplicate: The keypair '...' already exists`

**Solution:**
```bash
# Delete existing key pair
aws ec2 delete-key-pair --key-name factorio-server-key

# Re-run setup
./scripts/setup-aws.sh
```

### Instance Launch Failure

**Error:** Various EC2 launch errors

**Common causes and solutions:**

1. **No default VPC:**
   ```bash
   # Create default VPC
   aws ec2 create-default-vpc
   ```

2. **Insufficient capacity:**
   - Try different instance type in config
   - Try different availability zone/region

3. **Service limit exceeded:**
   - Request limit increase in AWS Console
   - Or terminate unused instances

### User Data Script Failures

**Symptom:** Instance launches but Factorio doesn't install

**Debug:**
```bash
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>

# Check user data execution log
sudo cat /var/log/cloud-init-output.log

# Check for errors
sudo journalctl -xe
```

## Connection Issues

### Cannot SSH to Server

**Error:** `Connection refused` or `Permission denied`

**Solutions:**

1. **Check key permissions:**
   ```bash
   chmod 400 factorio-server-key.pem
   ```

2. **Verify security group:**
   ```bash
   aws ec2 describe-security-groups --group-ids <SG_ID>
   # Should show port 22 open for your IP
   ```

3. **Check instance is running:**
   ```bash
   ./scripts/manage-factorio.sh status
   ```

4. **Use correct username:**
   ```bash
   # Correct
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   
   # Wrong
   ssh -i factorio-server-key.pem ubuntu@<SERVER_IP>  # Wrong user
   ```

### Cannot Connect to Game Server

**Symptom:** Can SSH but can't connect in Factorio game

**Solutions:**

1. **Check server is running:**
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   sudo systemctl status factorio
   ```

2. **Verify port 34197 UDP is open:**
   ```bash
   aws ec2 describe-security-groups --group-ids <SG_ID> \
     --query 'SecurityGroups[0].IpPermissions[?ToPort==`34197`]'
   ```

3. **Check Factorio logs:**
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   sudo journalctl -u factorio -n 50
   ```

4. **Verify game version matches:**
   - Client and server versions must match
   - Check server version: `./scripts/manage-factorio.sh status`
   - Update server: `./scripts/manage-factorio.sh deploy stable`

## Server Issues

### Server Crashes on Startup

**Check logs:**
```bash
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
sudo journalctl -u factorio -n 100
```

**Common causes:**

1. **Corrupted save file:**
   ```bash
   # Restore from backup
   ./scripts/manage-factorio.sh restore-saves YYYYMMDD_HHMMSS
   ```

2. **Mod conflicts:**
   ```bash
   # Remove all mods temporarily
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   sudo mv /opt/factorio/bin/mods /opt/factorio/bin/mods.backup
   sudo mkdir /opt/factorio/bin/mods
   sudo systemctl restart factorio
   ```

3. **Out of memory:**
   - Increase instance size
   - Check with: `free -h`

### Server Running but Unresponsive

**Solutions:**

1. **Check resource usage:**
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   top
   # Look for high CPU or memory usage
   ```

2. **Restart server:**
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   sudo systemctl restart factorio
   ```

3. **Check disk space:**
   ```bash
   df -h
   # If disk is full, clean old saves
   ```

### Save Games Not Loading

**Solutions:**

1. **Check save file exists:**
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   ls -lh /opt/factorio/bin/saves/
   ```

2. **Restore from S3:**
   ```bash
   ./scripts/manage-factorio.sh restore-saves YYYYMMDD_HHMMSS
   ```

3. **Check file permissions:**
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   sudo chown -R factorio:factorio /opt/factorio/bin/saves
   ```

## Backup Issues

### Backups Not Running

**Check cron job:**
```bash
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
sudo crontab -u factorio -l
# Should show backup script
```

**Check backup script:**
```bash
sudo -u factorio /opt/factorio/scripts/backup.sh
# Should complete without errors
```

### Cannot Access S3

**Error:** `Unable to locate credentials` on EC2 instance

**Solution:**
```bash
# Check instance profile is attached
aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# If missing, attach it
aws ec2 associate-iam-instance-profile \
  --instance-id <INSTANCE_ID> \
  --iam-instance-profile Name=factorio-server-role
```

### S3 Upload Failures

**Check IAM permissions:**
```bash
# From EC2 instance
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
aws s3 ls s3://<BUCKET_NAME>
# Should list bucket contents
```

**Check S3 bucket exists:**
```bash
aws s3 ls | grep factorio-server
```

## Version Management Issues

### Rollback Fails

**Symptom:** Rollback completes but server won't start

**Solution:**
1. Check the backup file is valid
2. Verify logs for specific errors
3. If needed, deploy fresh version and restore saves separately:
   ```bash
   ./scripts/manage-factorio.sh deploy stable
   ./scripts/manage-factorio.sh restore-saves YYYYMMDD_HHMMSS
   ```

### Cannot Download Factorio Version

**Error:** `404 Not Found` when downloading Factorio

**Solutions:**
1. Check version number is correct
2. Use "stable" for latest stable version
3. Check Factorio.com is accessible
4. Verify wget/curl is installed on instance

## Performance Issues

### High Latency/Lag

**Solutions:**

1. **Increase instance size:**
   ```bash
   # Stop instance
   ./scripts/stop-server.sh
   
   # Change type
   aws ec2 modify-instance-attribute \
     --instance-id <INSTANCE_ID> \
     --instance-type "{\"Value\": \"t3.large\"}"
   
   # Start instance
   ./scripts/start-server.sh
   ```

2. **Check network:**
   ```bash
   # From game client
   ping <SERVER_IP>
   ```

3. **Monitor server resources:**
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   top
   iotop  # If installed
   ```

### Out of Disk Space

**Solution:**
```bash
# Check usage
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
df -h

# Clean old saves (backup first!)
./scripts/manage-factorio.sh backup-saves
sudo find /opt/factorio/bin/saves -mtime +30 -delete

# Or increase EBS volume in AWS Console
```

## Cost Issues

### Unexpected AWS Charges

**Check usage:**
```bash
# Instance hours
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE

# Instance status
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=factorio-server" \
  --query 'Reservations[0].Instances[0].State.Name'
```

**Solutions:**
1. Stop instance when not playing
2. Delete unused snapshots
3. Clean old S3 backups manually
4. Use smaller instance type
5. Set up billing alerts

## Script Issues

### Script Won't Execute

**Error:** `Permission denied`

**Solution:**
```bash
chmod +x scripts/*.sh
```

### Configuration Not Found

**Error:** `Configuration file not found`

**Solution:**
```bash
cp config/factorio-server.conf.example config/factorio-server.conf
# Edit the file with your settings
```

### Syntax Errors

**Check script syntax:**
```bash
bash -n scripts/setup-aws.sh
bash -n scripts/deploy-server.sh
bash -n scripts/manage-factorio.sh
```

## Getting Help

If you can't resolve your issue:

1. **Check logs:**
   - AWS CloudWatch logs
   - System logs: `/var/log/messages`
   - Factorio logs: `journalctl -u factorio`

2. **Gather information:**
   - Error messages (full text)
   - Steps to reproduce
   - AWS region and instance type
   - Factorio version
   - Relevant log excerpts

3. **Ask for help:**
   - Open GitHub issue with details
   - Check Factorio forums
   - AWS support (for AWS-specific issues)

## Emergency Recovery

### Complete Server Rebuild

If everything fails:

```bash
# 1. Backup data from S3 (if not already backed up)
aws s3 sync s3://<BUCKET_NAME>/saves /tmp/emergency-backup/

# 2. Terminate instance
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

# 3. Wait for termination
aws ec2 wait instance-terminated --instance-ids <INSTANCE_ID>

# 4. Deploy fresh server
./scripts/deploy-server.sh

# 5. Restore saves
./scripts/manage-factorio.sh restore-saves YYYYMMDD_HHMMSS
```

This should restore your server to working condition.
