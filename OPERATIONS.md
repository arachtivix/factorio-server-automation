# Operations Runbook

Quick reference for common operational tasks.

## Daily Operations

### Check Server Health

```bash
./scripts/manage-factorio.sh status
```

**What to look for:**
- Service status: `active (running)`
- No error messages in recent logs

### View Server Logs

```bash
ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
sudo journalctl -u factorio -f
```

### Manual Backup

```bash
./scripts/manage-factorio.sh backup-saves
```

## Maintenance Tasks

### Update Server Version

**Before updating:**
1. Announce to players
2. Backup current state

```bash
# Backup first
./scripts/manage-factorio.sh backup

# Update
./scripts/manage-factorio.sh deploy stable

# Verify
./scripts/manage-factorio.sh status
```

### Rollback After Failed Update

```bash
# List available backups
aws s3 ls s3://<BUCKET_NAME>/server-binaries/backups/

# Rollback
./scripts/manage-factorio.sh rollback version-X.X.XX-TIMESTAMP.tar.gz

# Verify
./scripts/manage-factorio.sh status
```

### Install New Mods

1. Edit `config/mods.json`
2. Add mod entry:
   ```json
   {
     "name": "mod-name",
     "enabled": true
   }
   ```
3. Install:
   ```bash
   ./scripts/manage-factorio.sh install-mods
   ```

### Remove Mods

1. Edit `config/mods.json`
2. Set `"enabled": false` or remove entry
3. Reinstall:
   ```bash
   ./scripts/manage-factorio.sh install-mods
   ```

## Cost Management

### Stop Server (When Not Playing)

```bash
./scripts/stop-server.sh
```

**Savings:** ~$20-25/month if stopped 12 hours/day

### Start Server

```bash
./scripts/start-server.sh
```

**Note:** IP address may change when restarting stopped instances

## Disaster Recovery

### Restore from Backup

```bash
# List backups
aws s3 ls s3://<BUCKET_NAME>/backups/

# Restore specific backup
./scripts/manage-factorio.sh restore-saves YYYYMMDD_HHMMSS
```

### Complete Server Rebuild

If the EC2 instance is lost:

```bash
# Deploy new instance
./scripts/deploy-server.sh

# Wait for deployment to complete
# Then restore saves
./scripts/manage-factorio.sh restore-saves YYYYMMDD_HHMMSS
```

## Troubleshooting

### Server Not Responding

1. Check instance status:
   ```bash
   aws ec2 describe-instances --filters "Name=tag:Name,Values=factorio-server"
   ```

2. Check service status:
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   sudo systemctl status factorio
   ```

3. Restart if needed:
   ```bash
   sudo systemctl restart factorio
   ```

### High Latency

1. Check instance type - may need larger instance:
   ```bash
   # Stop server first
   ./scripts/stop-server.sh
   
   # Change instance type
   aws ec2 modify-instance-attribute \
     --instance-id <INSTANCE_ID> \
     --instance-type "{\"Value\": \"t3.large\"}"
   
   # Start server
   ./scripts/start-server.sh
   ```

### Disk Space Issues

1. Check disk usage:
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   df -h
   ```

2. Clean old saves:
   ```bash
   # Backup first!
   ./scripts/manage-factorio.sh backup-saves
   
   # Then on server
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   sudo find /opt/factorio/bin/saves -mtime +30 -delete
   ```

3. Or increase EBS volume size in AWS Console

### Cannot SSH

1. Verify key permissions:
   ```bash
   chmod 400 factorio-server-key.pem
   ```

2. Check security group allows your IP:
   ```bash
   # Get your IP
   curl ifconfig.me
   
   # Update security group if needed
   aws ec2 authorize-security-group-ingress \
     --group-id <SG_ID> \
     --protocol tcp --port 22 --cidr <YOUR_IP>/32
   ```

### S3 Backup Failures

1. Verify IAM role:
   ```bash
   aws iam get-role --role-name factorio-server-role
   aws iam list-attached-role-policies --role-name factorio-server-role
   ```

2. Test S3 access from instance:
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP>
   aws s3 ls s3://<BUCKET_NAME>
   ```

## Monitoring

### Set Up CloudWatch Alarm for Instance Health

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name factorio-server-health \
  --alarm-description "Alert if Factorio server instance fails" \
  --metric-name StatusCheckFailed \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID>
```

### Check Backup Status

```bash
# List recent backups
aws s3 ls s3://<BUCKET_NAME>/backups/ | tail -20

# Check backup size
aws s3 ls s3://<BUCKET_NAME>/backups/ --recursive --human-readable --summarize
```

## Security

### Rotate SSH Key

1. Create new key pair:
   ```bash
   aws ec2 create-key-pair --key-name factorio-server-key-new \
     --query 'KeyMaterial' --output text > factorio-server-key-new.pem
   chmod 400 factorio-server-key-new.pem
   ```

2. Add new public key to server:
   ```bash
   ssh -i factorio-server-key.pem ec2-user@<SERVER_IP> \
     "aws ec2 describe-key-pairs --key-names factorio-server-key-new --query 'KeyPairs[0].KeyFingerprint'"
   ```

3. Update authorized_keys and test

### Update Security Group Rules

```bash
# Remove rule
aws ec2 revoke-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

# Add restricted rule
aws ec2 authorize-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp --port 22 --cidr <YOUR_IP>/32
```

### Audit S3 Access

Enable S3 access logging:
```bash
aws s3api put-bucket-logging \
  --bucket <BUCKET_NAME> \
  --bucket-logging-status file://logging.json
```

## Performance Optimization

### Monitor Instance Metrics

```bash
# CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Optimize for Large Games

For games with many players or large factories:

1. Use larger instance: t3.large or t3.xlarge
2. Increase autosave interval in server-settings.json
3. Enable non-blocking saving
4. Consider SSD-backed instance storage

## Emergency Contacts

**AWS Support:** https://console.aws.amazon.com/support/

**Factorio Support:** https://forums.factorio.com/

**Repository Issues:** https://github.com/arachtivix/factorio-server-automation/issues
