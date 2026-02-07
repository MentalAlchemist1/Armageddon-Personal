# ============================================================
# BONUS D: Zone Apex + ALB Access Logs
# ============================================================
# This file adds:
#   1) Zone apex (chewbacca-growl.com) ALIAS → ALB
#   2) S3 bucket for ALB access logs with required bucket policy
# ============================================================

# ------------------------------------------------------------
# Data source: ELB Service Account for your region
# ------------------------------------------------------------
# Explanation: AWS runs ELB from their own accounts. We need to 
# know WHICH account so we can let them write to our S3 bucket.
data "aws_elb_service_account" "main" {}

# ------------------------------------------------------------
# S3 Bucket for ALB Access Logs
# ------------------------------------------------------------
# Explanation: This bucket is where ALB writes every request it handles.
# It's your forensic evidence locker for incident response.
resource "aws_s3_bucket" "chewbacca_alb_logs_bucket01" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = "${var.project_name}-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project_name}-alb-logs"
    Purpose     = "ALB Access Logs"
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# S3 Bucket Policy: Allow ELB Service to Write Logs
# ------------------------------------------------------------
# Explanation: The mail carrier (ELB service) needs a key (policy) 
# to put packages (logs) in your garage (bucket).
resource "aws_s3_bucket_policy" "chewbacca_alb_logs_policy01" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.chewbacca_alb_logs_bucket01[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowELBServiceToPutLogs"
        Effect    = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.chewbacca_alb_logs_bucket01[0].arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid       = "AllowELBLogDeliveryServiceToPutLogs"
        Effect    = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.chewbacca_alb_logs_bucket01[0].arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "AllowELBLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.chewbacca_alb_logs_bucket01[0].arn
      }
    ]
  })
}

# ------------------------------------------------------------
# S3 Bucket Lifecycle: Auto-expire old logs
# ------------------------------------------------------------
# Explanation: Logs are valuable, but infinite logs = infinite cost.
# This rule auto-deletes logs older than 90 days.
resource "aws_s3_bucket_lifecycle_configuration" "chewbacca_alb_logs_lifecycle01" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.chewbacca_alb_logs_bucket01[0].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    filter {
      prefix = var.alb_access_logs_prefix
    }
  }
}

# ------------------------------------------------------------
# Block Public Access (security best practice)
# ------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "chewbacca_alb_logs_public_block01" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.chewbacca_alb_logs_bucket01[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------
# Route53: Zone Apex ALIAS → ALB
# ------------------------------------------------------------
# Explanation: This lets users type "chewbacca-growl.com" (no subdomain)
# and still reach your ALB. Humans forget subdomains; this catches them.
resource "aws_route53_record" "chewbacca_apex01" {
  zone_id = local.chewbacca_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# ============================================================
# OUTPUTS
# ============================================================

output "apex_url_https" {
  description = "HTTPS URL for the zone apex (naked domain)"
  value       = "https://${var.domain_name}"
}

output "alb_logs_bucket_name" {
  description = "S3 bucket name for ALB access logs"
  value       = var.enable_alb_access_logs ? aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket : null
}

output "alb_logs_path" {
  description = "Full S3 path where ALB logs are stored"
  value       = var.enable_alb_access_logs ? "s3://${aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/elasticloadbalancing/${var.aws_region}/" : null
}