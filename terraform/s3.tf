data "aws_caller_identity" "current" {}

# S3 Bucket for Factorio server data
resource "aws_s3_bucket" "factorio_server" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "Factorio Server Data"
    Application = "Factorio"
  }
}

resource "aws_s3_bucket_versioning" "factorio_server" {
  bucket = aws_s3_bucket.factorio_server.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "factorio_server" {
  bucket = aws_s3_bucket.factorio_server.id

  rule {
    id     = "DeleteOldBackups"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      days = var.s3_backup_retention_days
    }
  }
}

# Create folder structure (optional - S3 creates them automatically on upload)
resource "aws_s3_object" "folders" {
  for_each = toset(["server-binaries/", "saves/", "mods/", "backups/", "terraform-state/"])
  
  bucket  = aws_s3_bucket.factorio_server.id
  key     = each.value
  content = ""
}
