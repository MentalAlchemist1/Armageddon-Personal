
# LAB 1C BONUS E: WAF Logging Configuration

*Enhanced Socratic Q&A Guide*

---

> [!warning] **⚠️ PREREQUISITE**
> 
> Lab 1C Bonus D must be completed and verified before starting Bonus E. You must have:
> - Working ALB with WAF attached (`var.enable_waf = true`)
> - Route53 DNS configured (apex + subdomain)
> - CloudWatch Dashboard operational
> - Zone apex + ALB access logs to S3
> - `aws_wafv2_web_acl.chewbacca_waf01` resource existing and active

---

## Lab Overview

**Bonus E adds WAF logging** to your infrastructure. This is your **security observability layer**—it answers the critical question: *"What is WAF actually doing to protect my application?"*

Without WAF logs, you're flying blind. You might have WAF attached, but you have **zero visibility** into:
- What requests are being blocked
- What rules are triggering
- Who (IP/country/ASN) is attacking you
- Whether WAF is helping or hurting your users

*"You can't defend what you can't see."*

---

## What This Bonus Adds

| Component | Purpose | Career Value |
|-----------|---------|--------------|
| WAF Logging Configuration | Send WAF events to a destination | Security observability |
| CloudWatch Logs destination | Fast search, real-time queries | Incident response speed |
| S3 destination (alternative) | Long-term archive, SIEM pipeline | Compliance & forensics |
| Firehose destination (alternative) | Stream processing, real-time analytics | Enterprise data pipeline |

---

## Key AWS Update (Critical Context)

> [!info] **📌 WHAT CHANGED SINCE "THE OLD DAYS"**
> 
> AWS WAF logging can now go **directly** to:
> 1. **CloudWatch Logs** — fast search, Logs Insights queries
> 2. **S3** — archive, compliance, SIEM export
> 3. **Kinesis Data Firehose** — real-time streaming to S3/Splunk/Datadog
> 
> **⚠️ CRITICAL NAMING REQUIREMENT:** 
> The destination name **MUST** start with `aws-waf-logs-`
> 
> You can associate **ONE destination per Web ACL** (not multiple).
> 
> Terraform supports this with `aws_wafv2_web_acl_logging_configuration`.

---

> [!question] **SOCRATIC Q&A: Why Can't I Just Use Sampled Requests?**
> 
> ***Q:** Why can't I just use the WAF console "Sampled Requests" tab? It shows blocked requests!*
> 
> **A (Explain Like I'm 10):** Imagine your house has a security camera that only saves the last 3 photos, and they disappear after 5 minutes. That's "Sampled Requests"—you see a tiny snapshot, then it's gone forever. WAF logging is like having a DVR that records EVERYTHING, saves it for weeks, and lets you search through it. When someone asks "Were we attacked last Tuesday at 3am?", sampled requests says "🤷 I dunno", but WAF logs say "Yes, here's exactly what happened."
> 
> **Evaluator Question:** *What's the difference between sampled requests and full WAF logging?*
> 
> **Model Answer:** Sampled requests provide a limited, ephemeral view of recent traffic (typically ~500 requests, 3-hour retention) for quick debugging. Full WAF logging captures **EVERY** request that passes through the WAF with complete metadata: timestamp, action (ALLOW/BLOCK/COUNT), terminating rule, client IP, URI, headers, country, and more. Logs persist based on your retention policy (days to years). For incident response, compliance audits, and threat hunting, you need full logging—sampled requests are insufficient.

---

## Choosing Your Log Destination

Before writing Terraform, you need to choose **ONE** destination:

| Destination | Best For | Trade-offs |
|-------------|----------|------------|
| **CloudWatch Logs** | Fast queries, real-time alerting, Logs Insights | Cost scales with volume; 14-90 day retention typical |
| **S3** | Long-term archive, compliance, SIEM export | No real-time search; need Athena for queries |
| **Kinesis Firehose** | Real-time streaming to S3/Splunk/Datadog | More complex; additional cost; enterprise pattern |

> [!tip] **RECOMMENDATION FOR THIS LAB**
> 
> Use **CloudWatch Logs** (`var.waf_log_destination = "cloudwatch"`).
> It's fastest to verify, integrates with Logs Insights from Bonus F, and is the most practical for learning.

---

> [!question] **SOCRATIC Q&A: CloudWatch vs S3 vs Firehose**
> 
> ***Q:** Why would anyone choose S3 over CloudWatch Logs? CloudWatch seems easier.*
> 
> **A (Explain Like I'm 10):** Imagine you're collecting Pokémon cards. CloudWatch Logs is like a binder that's fast to flip through but gets expensive if you have thousands of cards and want to keep them for years. S3 is like a storage box in your closet—way cheaper for tons of cards, but you have to dig through the box to find specific ones. For a LAB, CloudWatch is perfect (fast and simple). For a COMPANY with millions of requests and 7-year compliance requirements, S3 (or Firehose→S3) is the right choice.
> 
> **Evaluator Question:** *When would you choose Firehose over direct S3 logging?*
> 
> **Model Answer:** Firehose provides: (1) Near real-time delivery (configurable buffer), (2) Automatic format transformation (JSON to Parquet), (3) Direct integration with SIEM tools (Splunk, Datadog), (4) Data enrichment before storage. Direct S3 is simpler but only supports JSON format with potential delivery delays. For enterprise security operations requiring real-time SIEM correlation, Firehose is the standard pattern.

---

## Terraform File Structure for Bonus E

| File | Purpose |
|------|---------|
| `variables.tf` | Add WAF logging variables (destination choice, retention) |
| `bonus_e_waf_logging.tf` | All three logging destination options (conditional) |
| `outputs.tf` | Export log destination coordinates |

---

# PART 1: Add Variables

**Why Variables?** Variables make your Terraform reusable and configurable. Different environments (dev/staging/prod) might use different log destinations or retention periods.

---

## Step 1.1: Append to `variables.tf`

Add these variables to your existing `variables.tf` file:

```hcl
# ============================================
# WAF LOGGING VARIABLES (Bonus E)
# ============================================

variable "waf_log_destination" {
  description = "Choose ONE destination per WebACL: cloudwatch | s3 | firehose"
  type        = string
  default     = "cloudwatch"
}

variable "waf_log_retention_days" {
  description = "Retention for WAF CloudWatch log group."
  type        = number
  default     = 14
}

variable "enable_waf_sampled_requests_only" {
  description = "If true, students can optionally filter/redact fields later. (Placeholder toggle.)"
  type        = bool
  default     = false
}
```

---

> [!question] **SOCRATIC Q&A: Why Use Variables for Log Destination?**
> 
> ***Q:** Why not just hardcode "cloudwatch" in the Terraform? It's simpler.*
> 
> **A (Explain Like I'm 10):** Imagine you have a toy robot that can only say "Hello" because that word is glued inside. If you want it to say "Goodbye," you have to break it open and re-glue. Variables are like giving the robot a button—press once for "Hello," twice for "Goodbye." When your boss says "We need to switch to S3 for compliance," you just change `waf_log_destination = "s3"` instead of rewriting all your Terraform code.
> 
> **Evaluator Question:** *How do variables support environment promotion (dev → staging → prod)?*
> 
> **Model Answer:** Variables allow environment-specific configuration via `.tfvars` files or CI/CD variable injection. Dev might use `waf_log_destination = "cloudwatch"` with 7-day retention for fast debugging. Prod might use `waf_log_destination = "firehose"` with SIEM integration and 90-day retention for compliance. Same Terraform code, different configurations—this is the core principle of DRY (Don't Repeat Yourself) in IaC.

---

# PART 2: Create WAF Logging Terraform File

This file provides **three mutually exclusive options**. Terraform's `count` parameter ensures only ONE destination is created based on your variable choice.

---

## Step 2.1: Create `bonus_e_waf_logging.tf`

Create a new file called `bonus_e_waf_logging.tf` with the following content:

```hcl
############################################
# Bonus E - WAF Logging (CloudWatch Logs OR S3 OR Firehose)
# One destination per Web ACL, choose via var.waf_log_destination.
############################################

############################################
# Option 1: CloudWatch Logs destination
############################################

# Explanation: WAF logs in CloudWatch are your "blaster-cam footage"—fast search, fast triage, fast truth.
resource "aws_cloudwatch_log_group" "chewbacca_waf_log_group01" {
  count = var.waf_log_destination == "cloudwatch" ? 1 : 0

  # NOTE: AWS requires WAF log destination names start with aws-waf-logs- (students must not rename this).
  name              = "aws-waf-logs-${var.project_name}-webacl01"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name = "${var.project_name}-waf-log-group01"
  }
}

# Explanation: This wire connects the shield generator to the black box—WAF -> CloudWatch Logs.
resource "aws_wafv2_web_acl_logging_configuration" "chewbacca_waf_logging01" {
  count = var.enable_waf && var.waf_log_destination == "cloudwatch" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.chewbacca_waf01[0].arn
  log_destination_configs = [
    aws_cloudwatch_log_group.chewbacca_waf_log_group01[0].arn
  ]

  # TODO: Students can add redacted_fields (authorization headers, cookies, etc.) as a stretch goal.
  # redacted_fields { ... }

  depends_on = [aws_wafv2_web_acl.chewbacca_waf01]
}

############################################
# Option 2: S3 destination (direct)
############################################

# Explanation: S3 WAF logs are the long-term archive—Chewbacca likes receipts that survive dashboards.
resource "aws_s3_bucket" "chewbacca_waf_logs_bucket01" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket = "aws-waf-logs-${var.project_name}-${data.aws_caller_identity.chewbacca_self01.account_id}"

  tags = {
    Name = "${var.project_name}-waf-logs-bucket01"
  }
}

# Explanation: Public access blocked—WAF logs are not a bedtime story for the entire internet.
resource "aws_s3_bucket_public_access_block" "chewbacca_waf_logs_pab01" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket                  = aws_s3_bucket.chewbacca_waf_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Connect shield generator to archive vault—WAF -> S3.
resource "aws_wafv2_web_acl_logging_configuration" "chewbacca_waf_logging_s3_01" {
  count = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.chewbacca_waf01[0].arn
  log_destination_configs = [
    aws_s3_bucket.chewbacca_waf_logs_bucket01[0].arn
  ]

  depends_on = [aws_wafv2_web_acl.chewbacca_waf01]
}

############################################
# Option 3: Firehose destination (classic "stream then store")
############################################

# Explanation: Firehose is the conveyor belt—WAF logs ride it to storage (and can fork to SIEM later).
resource "aws_s3_bucket" "chewbacca_firehose_waf_dest_bucket01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  bucket = "${var.project_name}-waf-firehose-dest-${data.aws_caller_identity.chewbacca_self01.account_id}"

  tags = {
    Name = "${var.project_name}-waf-firehose-dest-bucket01"
  }
}

# Explanation: Firehose needs a role—Chewbacca doesn't let random droids write into storage.
resource "aws_iam_role" "chewbacca_firehose_role01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${var.project_name}-firehose-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# Explanation: Minimal permissions—allow Firehose to put objects into the destination bucket.
resource "aws_iam_role_policy" "chewbacca_firehose_policy01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${var.project_name}-firehose-policy01"
  role  = aws_iam_role.chewbacca_firehose_role01[0].id

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
          aws_s3_bucket.chewbacca_firehose_waf_dest_bucket01[0].arn,
          "${aws_s3_bucket.chewbacca_firehose_waf_dest_bucket01[0].arn}/*"
        ]
      }
    ]
  })
}

# Explanation: The delivery stream is the belt itself—logs move from WAF -> Firehose -> S3.
resource "aws_kinesis_firehose_delivery_stream" "chewbacca_waf_firehose01" {
  count       = var.waf_log_destination == "firehose" ? 1 : 0
  name        = "aws-waf-logs-${var.project_name}-firehose01"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.chewbacca_firehose_role01[0].arn
    bucket_arn = aws_s3_bucket.chewbacca_firehose_waf_dest_bucket01[0].arn
    prefix     = "waf-logs/"
  }
}

# Explanation: Connect shield generator to conveyor belt—WAF -> Firehose stream.
resource "aws_wafv2_web_acl_logging_configuration" "chewbacca_waf_logging_firehose01" {
  count = var.enable_waf && var.waf_log_destination == "firehose" ? 1 : 0

  resource_arn = aws_wafv2_web_acl.chewbacca_waf01[0].arn
  log_destination_configs = [
    aws_kinesis_firehose_delivery_stream.chewbacca_waf_firehose01[0].arn
  ]

  depends_on = [aws_wafv2_web_acl.chewbacca_waf01]
}
```

---

> [!question] **SOCRATIC Q&A: Understanding the `count` Pattern**
> 
> ***Q:** What does `count = var.waf_log_destination == "cloudwatch" ? 1 : 0` mean?*
> 
> **A (Explain Like I'm 10):** It's like a light switch! If `waf_log_destination` equals "cloudwatch", the switch is ON (count = 1), and Terraform creates that resource. If it's anything else, the switch is OFF (count = 0), and Terraform skips it completely. This way, you choose ONE destination, and only that destination's resources get built—the others don't exist at all.
> 
> **Evaluator Question:** *Why use `count` instead of creating all three destinations and picking one at runtime?*
> 
> **Model Answer:** Creating unused resources wastes money (CloudWatch log groups, S3 buckets, Firehose streams all have costs), creates security surface area (more resources to secure/audit), and violates the principle of least infrastructure. Additionally, WAF only allows ONE logging destination per Web ACL—you physically cannot attach multiple. The `count` pattern ensures Terraform's state matches AWS's reality: exactly one destination exists.

---

> [!question] **SOCRATIC Q&A: Why `aws-waf-logs-` Prefix is Mandatory**
> 
> ***Q:** Why does AWS require the name to start with `aws-waf-logs-`? Can't I name it anything?*
> 
> **A (Explain Like I'm 10):** AWS is like a very strict librarian. When WAF wants to put books (logs) on a shelf, the librarian says "I only put books on shelves labeled 'aws-waf-logs-something'." If your shelf has a different label, the librarian refuses to touch it. AWS enforces this naming convention to prevent mistakes—you can't accidentally send WAF logs to your application log group and corrupt your data.
> 
> **Evaluator Question:** *What error would you see if the destination name doesn't start with `aws-waf-logs-`?*
> 
> **Model Answer:** Terraform apply would fail with an error similar to: `WAFInvalidParameterException: Error reason: The specified log destination is invalid. You must specify a log destination that starts with 'aws-waf-logs-'`. This is a hard AWS API requirement, not a Terraform limitation. Always validate naming conventions before `terraform apply`.

---

> [!question] **SOCRATIC Q&A: Why Block Public Access on S3?**
> 
> ***Q:** Why do we need `aws_s3_bucket_public_access_block` for the WAF logs bucket?*
> 
> **A (Explain Like I'm 10):** WAF logs contain secrets! They show every IP address that tried to attack you, what paths they hit, and what your defenses did. If that bucket is public, attackers can READ your logs, learn what works against you, and try again smarter. It's like posting your house's alarm system manual on your front door. Block public access = keep your security playbook private.
> 
> **Evaluator Question:** *What sensitive information exists in WAF logs that requires protection?*
> 
> **Model Answer:** WAF logs contain: (1) Client IP addresses (PII in many jurisdictions), (2) Request URIs (may contain session tokens, API keys in query strings), (3) HTTP headers (Authorization, cookies, API keys), (4) Attack patterns (reveals what attackers are trying), (5) Rule effectiveness (shows which defenses work). Exposing this data enables reconnaissance, credential theft, and attack optimization. S3 public access block is non-negotiable for security logging.

---

> [!question] **SOCRATIC Q&A: Understanding Firehose IAM Role**
> 
> ***Q:** Why does Firehose need its own IAM role? Can't it just use my role?*
> 
> **A (Explain Like I'm 10):** Imagine you hire a delivery driver (Firehose) to move packages (logs) to your warehouse (S3). The driver needs their OWN key to your warehouse—you don't give them YOUR house key! The IAM role is the delivery driver's key: it ONLY opens the warehouse door, nothing else. If someone steals the driver's key, they can't get into your house, bank account, or anything else.
> 
> **Evaluator Question:** *What's the principle demonstrated by the Firehose IAM policy?*
> 
> **Model Answer:** Least privilege. The policy grants exactly what Firehose needs: S3 Put/Get/List/Abort operations on ONE specific bucket. It cannot read other buckets, cannot delete objects, cannot access EC2/RDS/anything else. If the Firehose role is compromised, blast radius is limited to that single bucket. This is defense in depth—even internal AWS services operate with minimal permissions.

---

> [!question] **SOCRATIC Q&A: Understanding `depends_on`**
> 
> ***Q:** Why do the logging configurations have `depends_on = [aws_wafv2_web_acl.chewbacca_waf01]`?*
> 
> **A (Explain Like I'm 10):** You can't put a security camera in a room that doesn't exist yet! The `depends_on` tells Terraform: "Hey, build the WAF first, THEN connect the logging to it." Without this, Terraform might try to connect logging to a WAF that hasn't been created yet, and everything breaks. It's like telling someone to hang a picture on a wall before you've built the wall.
> 
> **Evaluator Question:** *When is `depends_on` necessary versus implicit dependency?*
> 
> **Model Answer:** Terraform automatically creates implicit dependencies when you reference another resource's attributes (like using `.arn`). However, `depends_on` is needed when: (1) The dependency isn't expressed through attribute references, (2) Race conditions exist (resource available before fully configured), (3) Side effects must complete first (like IAM propagation). In this case, `depends_on` provides explicit clarity and guards against edge cases where the WAF ARN exists but the resource isn't fully ready for logging attachment.

---

# PART 3: Add Outputs

Outputs tell you WHERE your logs are going after `terraform apply`. This is critical for verification and incident response—you need to know the exact log group name, bucket name, or stream name.

---

## Step 3.1: Append to `outputs.tf`

Add these outputs to your existing `outputs.tf` file:

```hcl
# ============================================
# WAF LOGGING OUTPUTS (Bonus E)
# ============================================

# Explanation: Coordinates for the WAF log destination—Chewbacca wants to know where the footprints landed.
output "chewbacca_waf_log_destination" {
  description = "Which WAF log destination is active"
  value       = var.waf_log_destination
}

output "chewbacca_waf_cw_log_group_name" {
  description = "CloudWatch Log Group name for WAF logs (if cloudwatch destination)"
  value       = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.chewbacca_waf_log_group01[0].name : null
}

output "chewbacca_waf_logs_s3_bucket" {
  description = "S3 bucket name for WAF logs (if s3 destination)"
  value       = var.waf_log_destination == "s3" ? aws_s3_bucket.chewbacca_waf_logs_bucket01[0].bucket : null
}

output "chewbacca_waf_firehose_name" {
  description = "Firehose stream name for WAF logs (if firehose destination)"
  value       = var.waf_log_destination == "firehose" ? aws_kinesis_firehose_delivery_stream.chewbacca_waf_firehose01[0].name : null
}
```

---

> [!question] **SOCRATIC Q&A: Why Conditional Outputs?**
> 
> ***Q:** Why do the outputs use ternary expressions with `null`? Why not just output everything?*
> 
> **A (Explain Like I'm 10):** If you chose CloudWatch, the S3 bucket doesn't exist—there's nothing to output! Terraform would crash trying to read `aws_s3_bucket.chewbacca_waf_logs_bucket01[0].bucket` when count was 0 (bucket wasn't created). The ternary says: "If S3 was chosen, show the bucket name. Otherwise, show nothing (null)." This prevents errors and shows only what's relevant.
> 
> **Evaluator Question:** *How would you use these outputs in a CI/CD pipeline?*
> 
> **Model Answer:** CI/CD pipelines can parse `terraform output -json` and route downstream actions. Example: If `chewbacca_waf_log_destination == "cloudwatch"`, the pipeline configures CloudWatch Logs Insights alarms. If `== "s3"`, it configures Athena tables for query. If `== "firehose"`, it verifies Splunk/Datadog integration. Outputs become the contract between Terraform and your automation.

---

# PART 4: Deploy and Verify

## Step 4.1: Terraform Workflow

```bash
# Initialize (if new providers needed)
terraform init

# Preview changes (ALWAYS do this first!)
terraform plan

# Apply changes
terraform apply
```

**Expected Output (for CloudWatch destination):**
```
aws_cloudwatch_log_group.chewbacca_waf_log_group01[0]: Creating...
aws_cloudwatch_log_group.chewbacca_waf_log_group01[0]: Creation complete
aws_wafv2_web_acl_logging_configuration.chewbacca_waf_logging01[0]: Creating...
aws_wafv2_web_acl_logging_configuration.chewbacca_waf_logging01[0]: Creation complete
```

---

## Step 4.2: Verify WAF Logging is Enabled (Authoritative)

This is the **single source of truth**—it proves WAF is actually sending logs somewhere.

> [!success] **VERIFICATION: WAF Logging Configuration**
> 
> ```bash
> # Get your Web ACL ARN first
> aws wafv2 list-web-acls --scope REGIONAL --region <REGION> \
>   --query "WebACLs[?contains(Name, 'waf01')].ARN" --output text
> 
> # Verify logging configuration
> aws wafv2 get-logging-configuration \
>   --resource-arn <WEB_ACL_ARN> \
>   --region <REGION>
> ```
> 
> **Expected Output:**
> ```json
> {
>     "LoggingConfiguration": {
>         "ResourceArn": "arn:aws:wafv2:...:webacl/<project>-waf01/...",
>         "LogDestinationConfigs": [
>             "arn:aws:logs:<region>:<account>:log-group:aws-waf-logs-<project>-webacl01"
>         ]
>     }
> }
> ```
> 
> ✅ `LogDestinationConfigs` contains **exactly ONE** destination ARN  
> ✅ Destination ARN starts with `aws-waf-logs-`  
> ✅ No errors returned

---

## Step 4.3: Generate Traffic (Hits + Blocks)

You need actual requests to generate log entries:

```bash
# Normal requests (should be ALLOWED)
curl -I https://chewbacca-growl.com/
curl -I https://app.chewbacca-growl.com/

# Suspicious request (may be BLOCKED by managed rules)
curl -I "https://chewbacca-growl.com/?<script>alert(1)</script>"
curl -I "https://chewbacca-growl.com/../../../etc/passwd"
```

---

## Step 4.4: Verify Logs Arrived (By Destination)

### Option C1: If CloudWatch Logs Destination

> [!success] **VERIFICATION: CloudWatch WAF Logs**
> 
> ```bash
> # Check log streams exist
> aws logs describe-log-streams \
>   --log-group-name aws-waf-logs-<project>-webacl01 \
>   --order-by LastEventTime \
>   --descending \
>   --region <REGION>
> 
> # Pull recent log events
> aws logs filter-log-events \
>   --log-group-name aws-waf-logs-<project>-webacl01 \
>   --max-items 20 \
>   --region <REGION>
> ```
> 
> **Expected:** JSON entries showing `"action": "ALLOW"` or `"action": "BLOCK"` with request details.

---

### Option C2: If S3 Destination

> [!success] **VERIFICATION: S3 WAF Logs**
> 
> ```bash
> # List objects in WAF logs bucket
> aws s3 ls s3://aws-waf-logs-<project>-<account_id>/ --recursive | head
> 
> # Download and inspect a log file
> aws s3 cp s3://aws-waf-logs-<project>-<account_id>/<path>/file.gz - | gunzip | head
> ```
> 
> **Note:** S3 logs have delivery delay (typically 5-10 minutes). Be patient!

---

### Option C3: If Firehose Destination

> [!success] **VERIFICATION: Firehose WAF Logs**
> 
> ```bash
> # Check Firehose stream status
> aws firehose describe-delivery-stream \
>   --delivery-stream-name aws-waf-logs-<project>-firehose01 \
>   --query "DeliveryStreamDescription.DeliveryStreamStatus" \
>   --region <REGION>
> 
> # Check objects landed in destination bucket
> aws s3 ls s3://<project>-waf-firehose-dest-<account_id>/waf-logs/ --recursive | head
> ```
> 
> **Expected Status:** `ACTIVE`

---

> [!question] **SOCRATIC Q&A: Why Logs Might Be Empty**
> 
> ***Q:** I ran curl but my logs are empty. What went wrong?*
> 
> **A (Explain Like I'm 10):** Several possible reasons: (1) **Timing**—S3/Firehose have delivery delays (5-10 min); CloudWatch is faster but not instant. (2) **Traffic didn't hit WAF**—if you're curling the ALB directly (bypassing CloudFront), and WAF is on CloudFront, logs won't appear. (3) **WAF not enabled**—check `var.enable_waf = true`. (4) **Wrong log group name**—verify you're querying the exact name from `terraform output`.
> 
> **Evaluator Question:** *How would you troubleshoot missing WAF logs systematically?*
> 
> **Model Answer:** Systematic approach: (1) Verify `get-logging-configuration` returns valid config—if not, logging isn't enabled. (2) Confirm traffic path hits WAF (curl through CloudFront/ALB where WAF is attached, not direct EC2). (3) Check CloudWatch/S3/Firehose permissions (IAM). (4) Wait for delivery delay (S3: 5-10 min, Firehose: buffering interval). (5) Check Firehose delivery errors in CloudWatch metrics. (6) Verify log group/bucket exists and isn't blocked by SCP/permissions.

---

# PART 5: Why This Matters (Incident Response Reality)

With WAF logging enabled, you can now answer critical incident response questions:

| Question | How WAF Logs Answer It |
|----------|------------------------|
| "Are 5xx errors caused by attackers or backend failure?" | Correlate WAF BLOCK spikes with ALB 5xx timestamps |
| "Do we see WAF blocks spike before ALB errors?" | Timeline analysis: WAF blocks → then ALB overwhelmed |
| "What paths/IPs are hammering the app?" | Query top URIs and client IPs from WAF logs |
| "Is it one client, one ASN, one country, or broad?" | Aggregate by clientIp, country, ASN fields |
| "Did WAF mitigate, or are we failing downstream?" | Compare BLOCK count vs requests reaching origin |

---

> [!question] **SOCRATIC Q&A: Correlation is the Superpower**
> 
> ***Q:** Why do we need BOTH WAF logs AND ALB logs? Isn't one enough?*
> 
> **A (Explain Like I'm 10):** Imagine you're a detective investigating a crime. WAF logs are like security camera footage at the front gate—they show who was stopped. ALB logs are like footage inside the building—they show who got in and what they did. If someone got past the gate but caused trouble inside, you need BOTH recordings to understand what happened. WAF logs alone don't show backend errors; ALB logs alone don't show blocked attacks.
> 
> **Evaluator Question:** *How would you correlate WAF and ALB logs during an incident?*
> 
> **Model Answer:** Correlation strategy: (1) Identify incident time window from alerts. (2) Query WAF logs for that window: `action = "BLOCK"` count, top terminating rules, top IPs. (3) Query ALB logs for same window: 5xx count, latency spikes, top error URIs. (4) Compare timelines: Did WAF blocks spike BEFORE ALB errors (attack mitigated) or AFTER (attack got through)? (5) Identify common client IPs in both logs. (6) Determine if issue was external (attack) or internal (backend failure with coincidental traffic).

---

# Common Failure Modes & Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `terraform apply` fails with "invalid log destination" | Destination name doesn't start with `aws-waf-logs-` | Fix the name in Terraform |
| Logging config exists but no logs appear | Traffic not hitting WAF-protected resource | Verify traffic path (CloudFront/ALB, not direct EC2) |
| S3 logs empty after 15+ minutes | S3 delivery can be delayed up to 1 hour | Wait longer; check for S3 permissions errors |
| Firehose status is `CREATING` forever | IAM role/policy issue | Check Firehose error metrics in CloudWatch |
| "Resource not found" when getting logging config | WAF logging never enabled, or wrong ARN | Run `terraform apply` again; verify ARN |
| CloudWatch queries return nothing | Wrong log group name | Use exact name from `terraform output` |
| `Error: Invalid index` on count | Condition evaluated to 0 (resource not created) | Check variable values; ensure consistency |

---

# Deliverables Checklist

| Requirement | Verification Command | Expected Result |
|-------------|---------------------|-----------------|
| WAF logging enabled | `aws wafv2 get-logging-configuration --resource-arn <ARN>` | Returns `LogDestinationConfigs` with one entry |
| Log destination exists | `aws logs describe-log-groups` or `aws s3 ls` | Log group/bucket exists with correct name |
| Logs are populated | Query logs after generating traffic | JSON entries with `action`, `clientIp`, `uri` |
| Terraform outputs correct | `terraform output chewbacca_waf_log_destination` | Shows chosen destination type |
| No public access (S3) | `aws s3api get-public-access-block --bucket <BUCKET>` | All four block settings = true |

---

# Reflection Questions

Answer these to solidify your understanding:

**A) Why must WAF log destinations start with `aws-waf-logs-`?**

AWS enforces this naming convention to prevent accidental misconfiguration. It ensures you don't accidentally send WAF logs to application log groups or shared buckets, which could corrupt data or create security issues.

**B) When would you choose S3 over CloudWatch for WAF logs?**

When you need: (1) Long-term retention (years) at low cost, (2) Integration with SIEM via S3 export, (3) Athena queries for historical analysis, (4) Compliance archives with lifecycle policies.

**C) What's the security risk of public WAF log buckets?**

Exposed WAF logs reveal: attack patterns, client IPs, request paths, header contents (potentially including tokens), and which defenses work—enabling attackers to refine their approach.

**D) How does WAF logging support "mean time to detect" (MTTD)?**

WAF logs enable real-time alerting on block spikes, unusual traffic patterns, or specific attack signatures. Without logs, you only discover attacks when they succeed and cause visible damage.

**E) Why does Firehose use a separate IAM role instead of a user's credentials?**

Least privilege and separation of duties. The Firehose role can ONLY write to one specific S3 bucket—nothing else. If compromised, blast radius is minimal. User credentials typically have broader access and should never be embedded in services.

---

# What's Next: Bonus F

**Bonus F: CloudWatch Logs Insights Queries** builds on this foundation:

- Write queries to analyze WAF logs
- Create dashboards from WAF + ALB log correlation  
- Build incident runbook queries
- Automate threat hunting patterns

*WAF logging (Bonus E) provides the DATA. Logs Insights (Bonus F) provides the ANALYSIS.*

---

# What This Lab Proves About You

*If you complete this lab, you can confidently say:*

> **"I can implement security observability for web applications using WAF logging with appropriate destination selection based on operational requirements."**

*This is senior-level security engineering, not entry-level. Most engineers deploy WAF and never enable logging—you now understand why that's negligent and dangerous.*

---

# Quick Reference: All Verification Commands

```bash
# ============================================
# BONUS E VERIFICATION SCRIPT
# ============================================

# 1. Get Web ACL ARN
WEB_ACL_ARN=$(aws wafv2 list-web-acls --scope REGIONAL --region <REGION> \
  --query "WebACLs[?contains(Name, 'waf01')].ARN" --output text)

# 2. Verify logging configuration exists
aws wafv2 get-logging-configuration \
  --resource-arn "$WEB_ACL_ARN" \
  --region <REGION>

# 3. Verify terraform outputs
terraform output chewbacca_waf_log_destination
terraform output chewbacca_waf_cw_log_group_name

# 4. Generate traffic
curl -I https://chewbacca-growl.com/

# 5. Check logs (CloudWatch example)
aws logs filter-log-events \
  --log-group-name aws-waf-logs-<project>-webacl01 \
  --max-items 20 \
  --region <REGION>
```
