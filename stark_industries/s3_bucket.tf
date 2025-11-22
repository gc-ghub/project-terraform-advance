###########################################################
#Logging Bucket
#This bucket stores access logs from the main bucket.
###########################################################


resource "aws_s3_bucket" "logging_bucket" {
  bucket        = "${local.name_suffix}-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(
    local.required_tags,
    {
      Name = "${local.name_suffix}-logs"
    }
  )
}

# Ownership controls (required before ACL)
resource "aws_s3_bucket_ownership_controls" "logging_bucket_ownership" {
  bucket = aws_s3_bucket.logging_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# ACL needed for access logging
resource "aws_s3_bucket_acl" "logging_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.logging_bucket_ownership]
  bucket     = aws_s3_bucket.logging_bucket.id
  acl        = "log-delivery-write"
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "logging_bucket_public_access" {
  bucket = aws_s3_bucket.logging_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "logging_bucket_sse" {
  bucket = aws_s3_bucket.logging_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning for log retention
resource "aws_s3_bucket_versioning" "logging_bucket_versioning" {
  bucket = aws_s3_bucket.logging_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle policy to expire old logs
resource "aws_s3_bucket_lifecycle_configuration" "logging_bucket_lifecycle" {
  bucket = aws_s3_bucket.logging_bucket.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    # Required: filter or prefix must be provided
    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }
  }
}


######################################################################################
# Main Bucket (Primary Region)
# This bucket stores application data and sends access logs to the logging bucket.
######################################################################################

resource "aws_s3_bucket" "main_bucket" {
  bucket        = "${local.name_suffix}-main-bucket-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(
    local.required_tags,
    {
      Name = "${local.name_suffix}-main-bucket"
    }
  )
}

# Ownership enforced — best practice for main bucket
resource "aws_s3_bucket_ownership_controls" "main_bucket_ownership" {
  bucket = aws_s3_bucket.main_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "main_bucket_public_access" {
  bucket = aws_s3_bucket.main_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Default encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main_bucket_sse" {
  bucket = aws_s3_bucket.main_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning enabled
resource "aws_s3_bucket_versioning" "main_bucket_versioning" {
  bucket = aws_s3_bucket.main_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Access Logging → Logging Bucket
resource "aws_s3_bucket_logging" "main_bucket_logging" {
  bucket        = aws_s3_bucket.main_bucket.id
  target_bucket = aws_s3_bucket.logging_bucket.bucket
  target_prefix = "access-logs/${local.name_suffix}-main/"
}

######################################################################################
# Replica Bucket (Secondary Region)
# This bucket stores replicated data from the main bucket.
######################################################################################

# ---------- Replica bucket in secondary region ----------
resource "aws_s3_bucket" "replica_bucket" {
  provider      = aws.secondary
  bucket        = "${local.name_suffix}-replica-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(local.required_tags, { Name = "${local.name_suffix}-replica" })
}

resource "aws_s3_bucket_ownership_controls" "replica_ownership" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "replica_public_block" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "replica_versioning" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Add CORS to replica just for console/browser troubleshooting if needed (not required for replication)
resource "aws_s3_bucket_cors_configuration" "replica_cors" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "x-amz-version-id"]
    max_age_seconds = 3000
  }
}

# CORS on source is REQUIRED so browser uploads (PUT) via presigned URL succeed
resource "aws_s3_bucket_cors_configuration" "main_cors" {
  bucket = aws_s3_bucket.main_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "x-amz-version-id"]
    max_age_seconds = 3000
  }
}





##########################################################################
#Replication role + replication configuration (in same primary region)
##########################################################################

# Role that S3 uses to perform replication
resource "aws_iam_role" "s3_replication_role" {
  name = "${local.name_suffix}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication_policy" {
  name = "${local.name_suffix}-s3-replication-policy"
  role = aws_iam_role.s3_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadSourceObject"
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectLegalHold",
          "s3:GetObjectRetention",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          "${aws_s3_bucket.main_bucket.arn}/*",
          "${aws_s3_bucket.main_bucket.arn}"
        ]
      },
      {
        Sid    = "AllowReplicateToDestination"
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.replica_bucket.arn}/*",
          "${aws_s3_bucket.replica_bucket.arn}"
        ]
      },
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["${aws_s3_bucket.main_bucket.arn}"]
      }
    ]
  })
}

# Replication configuration on the source bucket
resource "aws_s3_bucket_replication_configuration" "main_to_replica" {
  depends_on = [
    aws_s3_bucket_versioning.replica_versioning,
    aws_s3_bucket_versioning.main_bucket_versioning
  ]

  bucket = aws_s3_bucket.main_bucket.id
  role   = aws_iam_role.s3_replication_role.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket        = aws_s3_bucket.replica_bucket.arn
      storage_class = "STANDARD"

    }
    # 🔥 Correct place for AWS provider v6.x
    delete_marker_replication {
      status = "Disabled"
    }
  }
}

