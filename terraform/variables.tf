variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Factorio server data"
  type        = string
}

variable "s3_backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "key_pair_name" {
  description = "Name for the SSH key pair"
  type        = string
  default     = "factorio-server-key"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access SSH"
  type        = string
  default     = "0.0.0.0/0"
}

variable "vpc_id" {
  description = "VPC ID to use for resources"
  type        = string
}
