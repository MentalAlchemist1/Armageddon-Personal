# Lab 1C - Bonus E: WAF Logging Configuration

## Complete Step-by-Step Guide with Socratic Q&A

---

## 📋 Overview

**What You're Building:** WAF logging to capture every request WAF evaluates (allowed AND blocked) for security analysis and incident response.

**Prerequisites Completed:**
- ✅ Bonus B: ALB + TLS + WAF deployed
- ✅ WAF attached to ALB and working
- ✅ `terraform apply` successful for Bonus B

**Time Estimate:** 20-30 minutes

**End Result:** Every HTTP request hitting your ALB will be logged with client IP, URI, action taken, and which WAF rules were evaluated.

---

## 🎯 Why This Matters (Interview Context)

> **Evaluator Question:** *"Your app is getting 5xx errors. How do you determine if it's an attack or a backend bug?"*
>
> **Model Answer:** "I'd correlate three log sources: (1) WAF logs show if requests are being blocked or allowed, (2) ALB access logs show which requests reached the backend and their response codes, (3) Application logs show what happened inside the app. If WAF shows a spike in blocks right before 5xx errors, it's likely an attack that's overwhelming the system. If WAF shows all ALLOW but ALB shows 5xx, the backend is failing on legitimate traffic."

---

## 📚 Concept: WAF Logging vs. Sampled Requests

> ### 🎓 SOCRATIC Q&A
>
> **Q:** *WAF already has "Sampled Requests" in the console. Why do I need full logging?*
>
> **A (Explain Like I'm 10):** Imagine you're a teacher with 30 students taking a test. "Sampled requests" is like checking 3 random papers to see how the class is doing. "Full logging" is like keeping every single paper so you can review any student's work later. Sampling gives you a quick peek; logging gives you the complete history for investigations.
>
> | Feature | Sampled Requests | Full WAF Logging |
> |---------|------------------|------------------|
> | Coverage | ~1-3 requests/rule | EVERY request |
> | Retention | 3 hours | You control (14 days default) |
> | Searchable | No | Yes (CloudWatch Insights) |
> | Incident Response | Useless | Essential |
> | Cost | Free | Pay for storage |
>
> **Evaluator Question:** *"When would you use sampled requests vs. full logging?"*
>
> **Model Answer:** "Sampled requests are good for quick health checks during development—'are my rules firing at all?' Full logging is required for production incident response, compliance audits, and security investigations. You can't answer 'what IP attacked us at 3am' with samples."

---

## Step 1: Understand Your Current Infrastructure

Before adding logging, verify your WAF exists and note its exact resource name.

### 1.1 Check Your bonus_b.tf File

Open your `bonus_b.tf` and find your WAF resource. Look for this block:

```hcl
resource "aws_wafv2_web_acl" "main" {
  name        = "${local.name_prefix}-waf01"
  ...
}
```

**Write down:**
- WAF resource name: `aws_wafv2_web_acl.main` ← You'll reference this later
- WAF display name: `${local.name_prefix}-waf01` (e.g., `chewbacca-waf01`)

### 1.2 Verify WAF is Working (CLI)

Run this command to confirm your WAF exists:

```bash
# List all Web ACLs in your region
aws wafv2 list-web-acls --scope REGIONAL --region us-west-2
```

**Expected Output:**
```json
{
    "WebACLs": [
        {
            "Name": "chewbacca-waf01",
            "Id": "d15215f9-3e36-4192-a298-f5b19188585f",
            "ARN": "arn:aws:wafv2:us-west-2:262164343754:regional/webacl/chewbacca-waf01/...",
            ...
        }
    ]
}
```

✅ **Checkpoint:** You should see your WAF listed. Copy the ARN—you'll need it later.

---

## Step 2: Choose Your Log Destination

> ### 🎓 SOCRATIC Q&A
>
> **Q:** *AWS offers three destinations: CloudWatch Logs, S3, and Kinesis Firehose. Which should I choose?*
>
> **A (Explain Like I'm 10):** Think of it like storing your diary:
> - **CloudWatch Logs** = Digital diary on your phone. Super fast to search, but costs more if you write a lot.
> - **S3** = Paper diary in a filing cabinet. Cheap to store forever, but slow to find specific entries.
> - **Firehose** = Automatic scanner that copies your diary to the filing cabinet AND can send pages to other apps.
>
> | Destination | Best For | Searchable? | Cost | Latency |
> |-------------|----------|-------------|------|---------|
> | CloudWatch Logs | Fast incident response | Yes (Logs Insights) | Higher | ~seconds |
> | S3 | Long-term archive, compliance | No (need Athena) | Lowest | Minutes |
> | Firehose | Streaming to SIEM (Splunk, etc.) | Via destination | Medium | Configurable |
>
> **For this lab, we'll use CloudWatch Logs** because it enables Bonus F (Logs Insights queries).

---

## Step 3: Add Variables to variables.tf

### 3.1 Open variables.tf

```bash
cd ~/path/to/your/terraform-files
```

### 3.2 Add These Variables at the Bottom

Copy and paste this entire block at the end of your `variables.tf`:

```hcl
# ====================
# Bonus E: WAF Logging Variables
# ====================

variable "waf_log_destination" {
  description = "Where to send WAF logs: cloudwatch | s3 | firehose (one per WebACL)"
  type        = string
  default     = "cloudwatch"

  validation {
    condition     = contains(["cloudwatch", "s3", "firehose"], var.waf_log_destination)
    error_message = "waf_log_destination must be one of: cloudwatch, s3, firehose"
  }
}

variable "waf_log_retention_days" {
  description = "How many days to keep WAF logs (CloudWatch only)"
  type        = number
  default     = 14
}
```

> ### 🎓 SOCRATIC Q&A
>
> **Q:** *Why do we use a validation block on the variable?*
>
> **A (Explain Like I'm 10):** Imagine a vending machine that only accepts $1, $5, or $10 bills. If you try to put in a $3 bill (which doesn't exist), the machine rejects it immediately instead of getting confused inside. The validation block is like that—it rejects bad inputs BEFORE Terraform tries to use them, giving you a clear error message instead of a confusing failure later.
>
> **Evaluator Question:** *"What happens if someone sets waf_log_destination = 'kafka'?"*
>
> **Model Answer:** "Terraform will fail at `terraform plan` with a clear error: 'waf_log_destination must be one of: cloudwatch, s3, firehose'. This is fail-fast behavior—catch mistakes early before any infrastructure changes."

### 3.3 Save the File

✅ **Checkpoint:** Your `variables.tf` now has `waf_log_destination` and `waf_log_retention_days`.

---

## Step 4: Create the WAF Logging Terraform File

### 4.1 Create a New File: bonus_e_waf_logging.tf

In your terraform-files directory, create a new file called `bonus_e_waf_logging.tf`:

```bash
touch bonus_e_waf_logging.tf
```

### 4.2 Add the Complete Configuration

Copy this **entire block** into `bonus_e_waf_logging.tf`:

```hcl
# ====================
# Bonus E: WAF Logging Configuration
# ====================
# 
# CRITICAL: AWS requires log destination names to start with "aws-waf-logs-"
# This is enforced by AWS, not a convention choice.
#
# This file supports three destinations (choose ONE via var.waf_log_destination):
#   - cloudwatch: Fast search via Logs Insights (recommended for incident response)
#   - s3: Cheap long-term storage (requires Athena for queries)
#   - firehose: Stream to SIEM or data lake
# ====================

# --- Data Sources ---
# Get current AWS account ID and region for resource naming
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


# ============================================================
# OPTION 1: CloudWatch Logs Destination
# ============================================================

resource "aws_cloudwatch_log_group" "waf_logs" {
  count = var.waf_log_destination == "cloudwatch" ? 1 : 0

  # CRITICAL: Name MUST start with "aws-waf-logs-" or AWS rejects it
  name              = "aws-waf-logs-${local.name_prefix}-webacl01"
  retention_in_days = var.waf_log_retention_days

  tags = merge(local.common_tags, {
    Name    = "aws-waf-logs-${local.name_prefix}-webacl01"
    Purpose = "WAF request logging for incident response"
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "cloudwatch" {
  count = var.waf_log_destination == "cloudwatch" ? 1 : 0

  # Reference YOUR WAF from bonus_b.tf
  resource_arn = aws_wafv2_web_acl.main.arn

  # CloudWatch Log Group ARN (must be the log group, not a stream)
  log_destination_configs = [
    aws_cloudwatch_log_group.waf_logs[0].arn
  ]

  # Optional: Redact sensitive fields (uncomment if needed)
  # redacted_fields {
  #   single_header {
  #     name = "authorization"
  #   }
  # }
}


# ============================================================
# OPTION 2: S3 Destination
# ============================================================

resource "aws_s3_bucket" "waf_logs" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  # CRITICAL: Bucket name MUST start with "aws-waf-logs-"
  # Include account ID to ensure global uniqueness
  bucket = "aws-waf-logs-${local.name_prefix}-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name    = "aws-waf-logs-${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
    Purpose = "WAF log archive for compliance and forensics"
  })
}

# Security: Block all public access to WAF logs bucket
resource "aws_s3_bucket_public_access_block" "waf_logs" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket = aws_s3_bucket.waf_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_wafv2_web_acl_logging_configuration" "s3" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.main.arn

  log_destination_configs = [
    aws_s3_bucket.waf_logs[0].arn
  ]
}


# ============================================================
# OPTION 3: Kinesis Firehose Destination
# ============================================================

# Firehose needs a destination bucket (this one doesn't need aws-waf-logs- prefix)
resource "aws_s3_bucket" "waf_firehose_dest" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  bucket = "${local.name_prefix}-waf-firehose-dest-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-waf-firehose-dest"
    Purpose = "Firehose delivery destination for WAF logs"
  })
}

resource "aws_s3_bucket_public_access_block" "waf_firehose_dest" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  bucket = aws_s3_bucket.waf_firehose_dest[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for Firehose to write to S3
resource "aws_iam_role" "waf_firehose" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  name = "${local.name_prefix}-waf-firehose-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf-firehose-role01"
  })
}

resource "aws_iam_role_policy" "waf_firehose" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  name = "${local.name_prefix}-waf-firehose-policy01"
  role = aws_iam_role.waf_firehose[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.waf_firehose_dest[0].arn,
          "${aws_s3_bucket.waf_firehose_dest[0].arn}/*"
        ]
      }
    ]
  })
}

# Firehose Delivery Stream
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  # CRITICAL: Firehose name MUST start with "aws-waf-logs-"
  name        = "aws-waf-logs-${local.name_prefix}-firehose01"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.waf_firehose[0].arn
    bucket_arn = aws_s3_bucket.waf_firehose_dest[0].arn
    prefix     = "waf-logs/"

    buffering_size     = 5    # MB - flush when buffer reaches this size
    buffering_interval = 300  # seconds - flush at least this often
  }

  tags = merge(local.common_tags, {
    Name = "aws-waf-logs-${local.name_prefix}-firehose01"
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "firehose" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.main.arn

  log_destination_configs = [
    aws_kinesis_firehose_delivery_stream.waf_logs[0].arn
  ]
}
```

> ### 🎓 SOCRATIC Q&A
>
> **Q:** *Why does every resource have `count = var.waf_log_destination == "cloudwatch" ? 1 : 0`?*
>
> **A (Explain Like I'm 10):** Imagine you're packing for a trip. If you're going to the beach, you pack swimsuits (count=1). If you're going skiing, you pack zero swimsuits (count=0). The `count` tells Terraform "only create this resource IF the condition is true." This way, one file handles all three destinations, but only creates the resources for the one you chose.
>
> **Evaluator Question:** *"What's the advantage of using count vs. having three separate .tf files?"*
>
> **Model Answer:** "Single file with count: (1) All logic in one place for code review, (2) Variable validation ensures only one destination, (3) Easier to maintain—change naming convention once, not three times, (4) Outputs can use the same conditional pattern. Separate files: harder to ensure mutual exclusivity, more files to manage, easier to accidentally enable multiple destinations."

> ### 🎓 SOCRATIC Q&A
>
> **Q:** *Why MUST the names start with `aws-waf-logs-`? What happens if I name it something else?*
>
> **A (Explain Like I'm 10):** It's like a special mailbox that only accepts mail with a specific zip code. AWS built their WAF logging system to ONLY send logs to destinations that start with `aws-waf-logs-`. If your bucket or log group doesn't have that prefix, AWS says "I don't recognize that address" and refuses to deliver the logs. It's a security feature to prevent accidentally sending WAF logs to the wrong place.
>
> **Error you'd see:**
> ```
> Error: error creating WAF Logging Configuration: WAFInvalidParameterException: 
> Error reason: The ARN isn't valid. A valid ARN begins with arn: ...
> must have a prefix of aws-waf-logs-
> ```

### 4.3 Save the File

✅ **Checkpoint:** You now have `bonus_e_waf_logging.tf` with all three destination options.

---

## Step 5: Add Outputs to outputs.tf

### 5.1 Open outputs.tf

### 5.2 Add These Outputs at the Bottom

Copy and paste this block at the end of your `outputs.tf`:

```hcl
# ====================
# Bonus E: WAF Logging Outputs
# ====================

output "waf_log_destination" {
  description = "Active WAF log destination type"
  value       = var.waf_log_destination
}

output "waf_cw_log_group_name" {
  description = "CloudWatch Log Group name for WAF logs"
  value       = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.waf_logs[0].name : null
}

output "waf_cw_log_group_arn" {
  description = "CloudWatch Log Group ARN for WAF logs"
  value       = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.waf_logs[0].arn : null
}

output "waf_logs_s3_bucket" {
  description = "S3 bucket name for WAF logs (if S3 destination)"
  value       = var.waf_log_destination == "s3" ? aws_s3_bucket.waf_logs[0].bucket : null
}

output "waf_firehose_name" {
  description = "Firehose delivery stream name (if Firehose destination)"
  value       = var.waf_log_destination == "firehose" ? aws_kinesis_firehose_delivery_stream.waf_logs[0].name : null
}

output "waf_firehose_dest_bucket" {
  description = "S3 bucket where Firehose delivers WAF logs"
  value       = var.waf_log_destination == "firehose" ? aws_s3_bucket.waf_firehose_dest[0].bucket : null
}
```

### 5.3 Save the File

✅ **Checkpoint:** Your outputs.tf will now display WAF logging info after apply.

---

## Step 6: Validate and Deploy

### 6.1 Navigate to Your Terraform Directory

```bash
cd ~/path/to/your/terraform-files
```

**IMPORTANT:** You must run Terraform commands from the directory containing your `.tf` files!

### 6.2 Validate Syntax

```bash
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

**If you see errors:** See Troubleshooting section below.

### 6.3 Preview Changes

```bash
terraform plan
```

**Expected Output (for CloudWatch destination):**
```
Plan: 2 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + waf_cw_log_group_arn  = (known after apply)
  + waf_cw_log_group_name = "aws-waf-logs-chewbacca-webacl01"
  + waf_log_destination   = "cloudwatch"
```

**What you should see:**
- `aws_cloudwatch_log_group.waf_logs[0]` will be created
- `aws_wafv2_web_acl_logging_configuration.cloudwatch[0]` will be created
- Three new outputs

### 6.4 Apply Changes

```bash
terraform apply
```

Type `yes` when prompted.

**Expected Output:**
```
Apply complete! Resources: 2 added, 1 changed, 0 destroyed.

Outputs:

waf_cw_log_group_name = "aws-waf-logs-chewbacca-webacl01"
waf_cw_log_group_arn = "arn:aws:logs:us-west-2:262164343754:log-group:aws-waf-logs-chewbacca-webacl01"
waf_log_destination = "cloudwatch"
```

✅ **Checkpoint:** WAF logging is now enabled!

---

## Step 7: Verify WAF Logging is Working

### 7.1 Confirm Logging Configuration via CLI

```bash
# Get your WAF ARN first
WAF_ARN=$(aws wafv2 list-web-acls --scope REGIONAL --region us-west-2 \
  --query "WebACLs[?contains(Name, 'chewbacca')].ARN" --output text)

echo "WAF ARN: $WAF_ARN"

# Check logging configuration
aws wafv2 get-logging-configuration \
  --resource-arn "$WAF_ARN" \
  --region us-west-2
```

**Expected Output:**
```json
{
    "LoggingConfiguration": {
        "ResourceArn": "arn:aws:wafv2:us-west-2:...:regional/webacl/chewbacca-waf01/...",
        "LogDestinationConfigs": [
            "arn:aws:logs:us-west-2:262164343754:log-group:aws-waf-logs-chewbacca-webacl01"
        ]
    }
}
```

### 7.2 Generate Test Traffic

Hit your application to create log entries:

```bash
# Normal request (should be ALLOWED)
curl -I https://www.wheresjack.com/

# Another normal request
curl -I https://www.wheresjack.com/

# Suspicious request with XSS attempt (may be blocked or allowed depending on rules)
curl -I "https://www.wheresjack.com/?test=<script>alert(1)</script>"
```

**Note:** You may see `HTTP/2 404` or `HTTP/2 200` - both are fine. The important thing is the request reached WAF.

### 7.3 Check Logs Arrived

Wait 30-60 seconds, then check for log streams:

```bash
aws logs describe-log-streams \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --order-by LastEventTime \
  --descending \
  --region us-west-2
```

**Expected Output:**
```json
{
    "logStreams": [
        {
            "logStreamName": "us-west-2_chewbacca-waf01_0",
            "creationTime": 1770255626974,
            "firstEventTimestamp": 1770255619573,
            "lastEventTimestamp": 1770255620168,
            ...
        }
    ]
}
```

### 7.4 View Actual Log Entries

```bash
aws logs filter-log-events \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --max-items 5 \
  --region us-west-2
```

**What you'll see:** A JSON blob containing:
- `"action": "ALLOW"` or `"action": "BLOCK"`
- `"clientIp": "..."` - The visitor's IP
- `"httpRequest": {...}` - Full request details (URI, method, headers)
- `"ruleGroupList": [...]` - Which WAF rules were evaluated

> ### 🎓 SOCRATIC Q&A
>
> **Q:** *The log output is a giant unreadable JSON blob. How do I find the "action" field?*
>
> **A (Explain Like I'm 10):** The raw logs are like a book written in one giant paragraph with no line breaks. You CAN read it, but it's painful. In the next bonus (Bonus F), you'll learn CloudWatch Logs Insights, which is like having a highlighter that finds exactly what you're looking for. For now, you can copy the output and paste it into a JSON formatter online, or look for `"action":"ALLOW"` in the text.
>
> **Quick tip:** The action field appears early in each log entry, right after `"terminatingRuleType"`.

---

## Step 8: Verify Complete (Final Checklist)

Run this verification script to confirm everything is working:

```bash
echo "=== BONUS E VERIFICATION ==="

# 1. Check WAF exists
echo -e "\n1. WAF Web ACL:"
aws wafv2 list-web-acls --scope REGIONAL --region us-west-2 \
  --query "WebACLs[?contains(Name, 'chewbacca')].Name" --output text

# 2. Check logging configuration
echo -e "\n2. Logging Configuration:"
WAF_ARN=$(aws wafv2 list-web-acls --scope REGIONAL --region us-west-2 \
  --query "WebACLs[?contains(Name, 'chewbacca')].ARN" --output text)
aws wafv2 get-logging-configuration --resource-arn "$WAF_ARN" --region us-west-2 \
  --query "LoggingConfiguration.LogDestinationConfigs[0]" --output text

# 3. Check log group exists
echo -e "\n3. CloudWatch Log Group:"
aws logs describe-log-groups \
  --log-group-name-prefix aws-waf-logs-chewbacca \
  --query "logGroups[0].logGroupName" --output text --region us-west-2

# 4. Check log streams exist (proves logs are flowing)
echo -e "\n4. Log Streams (proves data is flowing):"
aws logs describe-log-streams \
  --log-group-name aws-waf-logs-chewbacca-webacl01 \
  --query "logStreams[0].logStreamName" --output text --region us-west-2

echo -e "\n=== VERIFICATION COMPLETE ==="
```

**All four checks should return values (not empty or errors).**

---

## 🔧 Troubleshooting Guide

### Issue 1: "Resource Not Found" - WAF Reference Mismatch

**Error:**
```
Error: Reference to undeclared resource
  on bonus_e_waf_logging.tf line XX:
  XX:   resource_arn = aws_wafv2_web_acl.chewbacca_waf01[0].arn
```

**Cause:** The instructor's template uses `aws_wafv2_web_acl.chewbacca_waf01[0]` but YOUR bonus_b.tf uses `aws_wafv2_web_acl.main`.

**Solution:**
1. Open your `bonus_b.tf` and find your WAF resource name
2. In `bonus_e_waf_logging.tf`, change all references to match YOUR resource name

**Change this:**
```hcl
resource_arn = aws_wafv2_web_acl.chewbacca_waf01[0].arn
```

**To this (if your WAF is named `main`):**
```hcl
resource_arn = aws_wafv2_web_acl.main.arn
```

---

### Issue 2: "Invalid ARN" - Missing aws-waf-logs- Prefix

**Error:**
```
Error: error creating WAF Logging Configuration: WAFInvalidParameterException:
The ARN isn't valid... must have a prefix of aws-waf-logs-
```

**Cause:** Your log group or S3 bucket name doesn't start with `aws-waf-logs-`.

**Solution:** Ensure your resource names use the required prefix:
```hcl
# CORRECT
name = "aws-waf-logs-${local.name_prefix}-webacl01"

# WRONG - missing prefix
name = "${local.name_prefix}-waf-logs"
```

---

### Issue 3: "Unknown Variable" - local.name_prefix Not Found

**Error:**
```
Error: Reference to undeclared local value
  on bonus_e_waf_logging.tf line XX:
  XX:   name = "aws-waf-logs-${local.name_prefix}-webacl01"
```

**Cause:** Your project doesn't define `local.name_prefix`.

**Solution:** Check your `main.tf` or `locals.tf` for how locals are defined. Common patterns:

```hcl
# Option A: If you have local.name_prefix
locals {
  name_prefix = "chewbacca"
}

# Option B: If you use var.project_name instead
# Change the references in bonus_e_waf_logging.tf:
name = "aws-waf-logs-${var.project_name}-webacl01"
```

---

### Issue 4: "Unknown Variable" - local.common_tags Not Found

**Error:**
```
Error: Reference to undeclared local value
  on bonus_e_waf_logging.tf line XX:
  XX:   tags = merge(local.common_tags, {
```

**Cause:** Your project doesn't define `local.common_tags`.

**Solution A:** Add common_tags to your locals block:
```hcl
locals {
  common_tags = {
    Project     = "chewbacca"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
```

**Solution B:** Remove the merge and use simple tags:
```hcl
# Change this:
tags = merge(local.common_tags, {
  Name = "aws-waf-logs-${local.name_prefix}-webacl01"
})

# To this:
tags = {
  Name    = "aws-waf-logs-chewbacca-webacl01"
  Project = "chewbacca"
}
```

---

### Issue 5: Data Source Already Exists

**Error:**
```
Error: Duplicate resource "data.aws_caller_identity" configuration
```

**Cause:** You already have `data "aws_caller_identity"` defined elsewhere.

**Solution:** Remove the duplicate from `bonus_e_waf_logging.tf`:
```hcl
# DELETE these lines if they already exist in another file:
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
```

Then update references to use your existing data source name:
```hcl
# If your existing data source is named differently, e.g.:
# data "aws_caller_identity" "chewbacca_self01" {}

# Change this:
bucket = "aws-waf-logs-${local.name_prefix}-${data.aws_caller_identity.current.account_id}"

# To this:
bucket = "aws-waf-logs-${local.name_prefix}-${data.aws_caller_identity.chewbacca_self01.account_id}"
```

---

### Issue 6: No Log Streams After Generating Traffic

**Symptom:** `describe-log-streams` returns empty `"logStreams": []`

**Possible Causes:**

1. **Not enough time passed** - Wait 60 seconds and try again

2. **Traffic didn't reach WAF** - Verify your curl hit the ALB:
   ```bash
   curl -v https://www.wheresjack.com/ 2>&1 | grep "< HTTP"
   ```

3. **Logging config not applied** - Check it exists:
   ```bash
   aws wafv2 get-logging-configuration \
     --resource-arn "YOUR_WAF_ARN" \
     --region us-west-2
   ```
   If this returns an error, the logging configuration wasn't created.

4. **Wrong log group name** - Verify the exact name:
   ```bash
   aws logs describe-log-groups \
     --log-group-name-prefix aws-waf-logs \
     --region us-west-2
   ```

---

### Issue 7: Terraform Plan Shows "forces replacement"

**Warning:**
```
# aws_cloudwatch_log_group.waf_logs[0] must be replaced
-/+ resource "aws_cloudwatch_log_group" "waf_logs" {
      ~ name = "old-name" -> "new-name" # forces replacement
```

**Cause:** Changing the log group name forces Terraform to delete and recreate it (losing existing logs).

**Solution:** If you have important logs, export them first:
```bash
# Export existing logs before allowing replacement
aws logs create-export-task \
  --log-group-name "old-log-group-name" \
  --from 0 \
  --to $(date +%s000) \
  --destination "your-backup-bucket" \
  --destination-prefix "waf-logs-backup"
```

---

## 📊 Understanding WAF Log Fields

When you view log entries, here's what the key fields mean:

| Field | What It Tells You | Example |
|-------|-------------------|---------|
| `timestamp` | When the request occurred (Unix ms) | `1770255619573` |
| `action` | What WAF did | `"ALLOW"` or `"BLOCK"` |
| `terminatingRuleId` | Which rule made the decision | `"Default_Action"` or `"AWSManagedRulesCommonRuleSet"` |
| `clientIp` | Requester's IP address | `"64.15.129.108"` |
| `country` | Geo-location of IP | `"CA"` (Canada) |
| `uri` | Path requested | `"/"` or `"/admin"` |
| `httpMethod` | Request method | `"GET"`, `"POST"` |
| `ruleGroupList` | All rule groups evaluated | Shows which managed rules processed the request |

> ### 🎓 SOCRATIC Q&A
>
> **Q:** *If `action` is "ALLOW" and `terminatingRuleId` is "Default_Action", what does that mean?*
>
> **A (Explain Like I'm 10):** Imagine a security checkpoint with multiple guards (rules). Each guard checks you for different things. If ALL guards say "you're fine," you reach the end and the "default action" lets you through. `terminatingRuleId = "Default_Action"` means NO rule blocked the request, so the default (ALLOW) was applied. If a specific rule blocked it, you'd see that rule's name instead.
>
> **Evaluator Question:** *"You see a log entry with action=BLOCK and terminatingRuleId=AWSManagedRulesCommonRuleSet. What happened?"*
>
> **Model Answer:** "A request was blocked by a rule in the AWS Common Rule Set. This managed rule group blocks known malicious patterns like cross-site scripting, path traversal, and remote code execution attempts. To find the specific rule, I'd look at the `terminatingRuleMatchDetails` field or check the WAF console's sampled requests."

---

## ✅ Bonus E Complete!

You've successfully:
- ✅ Added WAF logging variables
- ✅ Created logging configuration with conditional destinations
- ✅ Deployed CloudWatch Logs destination
- ✅ Verified logs are flowing
- ✅ Understand how to read WAF log entries

**What You Can Now Answer in Interviews:**
1. "How would you investigate a suspected attack on your web application?"
2. "What's the difference between WAF sampled requests and full logging?"
3. "How do you determine if WAF is blocking legitimate traffic?"
4. "Where should WAF logs go for real-time alerting vs. long-term storage?"

---

## 🚀 Next: Bonus F - CloudWatch Logs Insights

Bonus F will teach you to QUERY these logs with CloudWatch Logs Insights:
- Find all blocked requests in the last hour
- Identify top attacking IPs
- Correlate WAF blocks with application errors
- Build incident response runbooks

**Your WAF is now logging. Next, you'll learn to ask it questions.**
