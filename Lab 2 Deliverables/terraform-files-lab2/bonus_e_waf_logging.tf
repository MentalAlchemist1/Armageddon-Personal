############################################
# Bonus E - WAF Logging (CloudWatch Logs OR S3 OR Firehose)
# One destination per Web ACL, choose via var.waf_log_destination.
#
# UPDATED: Resource names match bonus_b.tf conventions
#   - Uses aws_wafv2_web_acl.main (not chewbacca_waf01)
#   - Uses local.name_prefix for consistency
#   - WAF is always created (no enable_waf toggle)
############################################

############################################
# Option 1: CloudWatch Logs destination
############################################

# Explanation: WAF logs in CloudWatch are your "blaster-cam footage"—fast search, fast triage, fast truth.
resource "aws_cloudwatch_log_group" "waf_logs" {
  count = var.waf_log_destination == "cloudwatch" ? 1 : 0

  # NOTE: AWS requires WAF log destination names start with aws-waf-logs- (students must not rename this).
  name              = "aws-waf-logs-${local.name_prefix}-webacl01"
  retention_in_days = var.waf_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf-log-group01"
  })
}

# Explanation: This wire connects the shield generator to the black box—WAF -> CloudWatch Logs.
resource "aws_wafv2_web_acl_logging_configuration" "cloudwatch" {
  count = var.waf_log_destination == "cloudwatch" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.main.arn
  log_destination_configs = [
    aws_cloudwatch_log_group.waf_logs[0].arn
  ]

  # TODO: Students can add redacted_fields (authorization headers, cookies, etc.) as a stretch goal.
  # redacted_fields {
  #   single_header {
  #     name = "authorization"
  #   }
  # }

  depends_on = [aws_wafv2_web_acl.main]
}

############################################
# Option 2: S3 destination (direct)
############################################

# Explanation: S3 WAF logs are the long-term archive—Chewbacca likes receipts that survive dashboards.
resource "aws_s3_bucket" "waf_logs" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  # NOTE: AWS requires WAF log destination names start with aws-waf-logs-
  bucket = "aws-waf-logs-${local.name_prefix}-${data.aws_caller_identity.chewbacca_self01.account_id}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf-logs-bucket01"
  })
}

# Explanation: Public access blocked—WAF logs are not a bedtime story for the entire internet.
resource "aws_s3_bucket_public_access_block" "waf_logs" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket                  = aws_s3_bucket.waf_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Connect shield generator to archive vault—WAF -> S3.
resource "aws_wafv2_web_acl_logging_configuration" "s3" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.main.arn
  log_destination_configs = [
    aws_s3_bucket.waf_logs[0].arn
  ]

  depends_on = [aws_wafv2_web_acl.main]
}

############################################
# Option 3: Firehose destination (classic "stream then store")
############################################

# Explanation: Firehose is the conveyor belt—WAF logs ride it to storage (and can fork to SIEM later).
resource "aws_s3_bucket" "waf_firehose_dest" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  bucket = "${local.name_prefix}-waf-firehose-dest-${data.aws_caller_identity.chewbacca_self01.account_id}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf-firehose-dest-bucket01"
  })
}

# Explanation: Public access blocked for Firehose destination bucket too
resource "aws_s3_bucket_public_access_block" "waf_firehose_dest" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  bucket                  = aws_s3_bucket.waf_firehose_dest[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Firehose needs a role—Chewbacca doesn't let random droids write into storage.
resource "aws_iam_role" "waf_firehose" {
  count = var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${local.name_prefix}-waf-firehose-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf-firehose-role01"
  })
}

# Explanation: Minimal permissions—allow Firehose to put objects into the destination bucket.
resource "aws_iam_role_policy" "waf_firehose" {
  count = var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${local.name_prefix}-waf-firehose-policy01"
  role  = aws_iam_role.waf_firehose[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.waf_firehose_dest[0].arn,
          "${aws_s3_bucket.waf_firehose_dest[0].arn}/*"
        ]
      }
    ]
  })
}

# Explanation: The delivery stream is the belt itself—logs move from WAF -> Firehose -> S3.
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  count       = var.waf_log_destination == "firehose" ? 1 : 0
  
  # NOTE: AWS requires WAF log destination names start with aws-waf-logs-
  name        = "aws-waf-logs-${local.name_prefix}-firehose01"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.waf_firehose[0].arn
    bucket_arn = aws_s3_bucket.waf_firehose_dest[0].arn
    prefix     = "waf-logs/"
    
    # Buffer settings (optional tuning)
    buffering_size     = 5    # MB (1-128)
    buffering_interval = 300  # seconds (60-900)
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf-firehose01"
  })
}

# Explanation: Connect shield generator to conveyor belt—WAF -> Firehose stream.
resource "aws_wafv2_web_acl_logging_configuration" "firehose" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.main.arn
  log_destination_configs = [
    aws_kinesis_firehose_delivery_stream.waf_logs[0].arn
  ]

  depends_on = [aws_wafv2_web_acl.main]
}
