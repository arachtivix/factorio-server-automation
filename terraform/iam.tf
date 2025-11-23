# IAM Role for EC2 Instance
resource "aws_iam_role" "factorio_server" {
  name = "factorio-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "Factorio Server Role"
    Application = "Factorio"
  }
}

# IAM Policy for S3 access
resource "aws_iam_policy" "factorio_server" {
  name        = "factorio-server-policy"
  description = "Policy for Factorio server operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = aws_s3_bucket.factorio_server.arn
      },
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListObjectVersions",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.factorio_server.arn}/*"
      },
      {
        Sid    = "EC2DescribeAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "Factorio Server Policy"
    Application = "Factorio"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "factorio_server" {
  role       = aws_iam_role.factorio_server.name
  policy_arn = aws_iam_policy.factorio_server.arn
}

# Instance profile
resource "aws_iam_instance_profile" "factorio_server" {
  name = "factorio-server-role"
  role = aws_iam_role.factorio_server.name

  tags = {
    Name        = "Factorio Server Instance Profile"
    Application = "Factorio"
  }
}
