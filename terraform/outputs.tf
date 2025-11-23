output "s3_bucket_name" {
  description = "Name of the S3 bucket for Factorio server data"
  value       = aws_s3_bucket.factorio_server.id
}

output "iam_role_name" {
  description = "Name of the IAM role for EC2 instance"
  value       = aws_iam_role.factorio_server.name
}

output "iam_instance_profile" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.factorio_server.name
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.factorio_server.id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = var.key_pair_name
}

output "vpc_id" {
  description = "VPC ID used for resources"
  value       = var.vpc_id
}
