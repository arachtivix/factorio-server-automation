# Terraform Configuration for Factorio Server

This directory contains Terraform configuration files to provision AWS infrastructure for the Factorio server.

## Files

- `main.tf` - Main Terraform configuration with provider and backend setup
- `variables.tf` - Input variables for the Terraform configuration
- `outputs.tf` - Output values after Terraform apply
- `s3.tf` - S3 bucket configuration for server data and backups
- `iam.tf` - IAM roles and policies for EC2 instance
- `security_group.tf` - Security group for network access

## Terraform Backend

The Terraform state is stored in an S3 bucket with versioning enabled. The backend configuration is generated dynamically by the `setup-aws.sh` script and stored in `backend.conf` (git-ignored).

## Usage

**Do not run Terraform commands directly.** Use the `scripts/setup-aws.sh` script instead, which handles:
- S3 bucket creation for backend
- VPC selection
- SSH key pair generation
- Terraform initialization and apply
- Saving outputs to config files

## Manual Terraform Commands (Advanced)

If you need to run Terraform commands directly:

```bash
cd terraform

# Initialize with backend config
terraform init -backend-config=backend.conf

# Plan changes
terraform plan

# Apply changes
terraform apply

# View outputs
terraform output

# Destroy resources
terraform destroy
```

## Generated Files (Git-ignored)

- `terraform.tfvars` - Variable values from factorio-server.conf
- `backend.conf` - S3 backend configuration
- `.terraform/` - Terraform provider plugins
- `.terraform.lock.hcl` - Provider version lock file
- `tfplan` - Saved Terraform plan (temporary)

## Resources Created

1. **S3 Bucket** - Stores server binaries, saves, mods, backups, and Terraform state
2. **IAM Role** - Allows EC2 instance to access S3
3. **IAM Policy** - Defines S3 and EC2 permissions
4. **IAM Instance Profile** - Attaches role to EC2 instance
5. **Security Group** - Controls network access (SSH, Factorio game port, RCON)
