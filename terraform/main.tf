terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Backend configuration will be provided via backend-config file
    # Bucket, key, and region are set dynamically
  }
}

provider "aws" {
  region = "us-east-1"
}
