resource "aws_s3_bucket" "backups" {
  bucket = "${var.project_name}-backups-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-backups"
    Environment = var.environment
    Purpose     = "disaster-recovery"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "backups_replica" {
  provider = aws.replica
  bucket   = "${var.project_name}-backups-replica-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-backups-replica"
    Environment = var.environment
    Purpose     = "disaster-recovery-replica"
  }
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"  # Different region for DR
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "backups_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.backups_replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.backups_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "backups_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.backups_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "backup_lifecycle"
    status = "Enabled"

    # Add this filter block - required for the rule
    filter {}  # Empty filter applies to all objects

    # Move to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after 1 year
    expiration {
      days = 365
    }

    # Delete incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Cross-region replication - Fixed with proper dependencies
resource "aws_s3_bucket_replication_configuration" "backups" {
  role   = aws_iam_role.s3_replication.arn
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "replicate_backups"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.backups_replica.arn
      storage_class = "STANDARD_IA"
    }
  }

  # Ensure both buckets have versioning enabled before replication
  depends_on = [
    aws_s3_bucket_versioning.backups,
    aws_s3_bucket_versioning.backups_replica
  ]
}

# IAM role for S3 replication
resource "aws_iam_role" "s3_replication" {
  name = "${var.project_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${var.project_name}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.backups.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.backups.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${aws_s3_bucket.backups_replica.arn}/*"
      }
    ]
  })
}