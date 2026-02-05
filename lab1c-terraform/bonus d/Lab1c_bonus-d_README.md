
# LAB 1C BONUS D: Zone Apex + ALB Access Logs to S3

*Enhanced Socratic Q&A Guide*

---

> [!warning] **⚠️ PREREQUISITE**
> Lab 1C Bonus C must be completed and verified before starting Bonus D. You must have:
> - Route53 hosted zone configured
> - ACM certificate validated
> - ALB with TLS (HTTPS listener)
> - WAF attached to ALB
> - CloudWatch Dashboard operational

---

## Lab Overview

Bonus D adds two critical production capabilities:

| **Component** | **What It Does** | **Why It Matters** |
|---------------|------------------|-------------------|
| Zone Apex ALIAS | `chewbacca-growl.com` → ALB | Users can type the naked domain |
| ALB Access Logs | Every request logged to S3 | Incident response forensics |

**This is incident response fuel.** When things break at 3 AM, these logs tell you WHO did WHAT and WHEN.

---

## Why Zone Apex Matters

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** We already have `app.chewbacca-growl.com` pointing to the ALB. Why do we need the naked domain (`chewbacca-growl.com`) to work too?*
> 
> **A (Explain Like I'm 10):** Imagine you tell your friend your address is "123 Main Street, Apartment 5." That's like `app.chewbacca-growl.com` — it's specific and works perfectly. But what if your friend just remembers "123 Main Street" and forgets the apartment number? They'd be stuck outside! The zone apex is like making sure people who forget the apartment number (the `app.` subdomain) still get to your door. Real humans type `chewbacca-growl.com` because it's easier to remember than `app.chewbacca-growl.com`.
> 
> **Evaluator Question:** *What's the technical challenge with pointing a zone apex to an ALB, and how does Route53 solve it?*
> 
> **Model Answer:** Zone apex (naked domain) cannot use a CNAME record per DNS RFC standards — CNAMEs at the apex break other record types like MX and TXT. Route53 solves this with ALIAS records, which are a Route53-specific feature that acts like a CNAME internally but appears as an A record externally. ALIAS records resolve directly to the ALB's IP addresses at query time, don't incur Route53 query charges, and support health checks. This is why AWS recommends ALIAS over CNAME for any AWS resource.

---

## Why ALB Access Logs Matter

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** We already have CloudWatch metrics and alarms. Why do we need access logs too?*
> 
> **A (Explain Like I'm 10):** Imagine your house has a doorbell camera (CloudWatch metrics) that counts how many people came by and whether they rang the bell. But what if something weird happens — like someone keeps ringing and running away? The doorbell camera tells you "10 rings today" but not WHO did it, WHEN exactly, or which door they tried. Access logs are like having a security guard who writes down every single visitor: their name badge, what time they arrived, which door they tried, how long they waited, and whether they got in. When something goes wrong, you don't guess — you read the log and KNOW.
> 
> **Evaluator Question:** *What specific data do ALB access logs capture that CloudWatch metrics don't provide?*
> 
> **Model Answer:** ALB access logs capture per-request details that metrics aggregate away:
> - **Client IP address** — who made the request (critical for attack attribution)
> - **Request path and query string** — what they asked for
> - **User-Agent header** — what client/browser they used
> - **Response code** — success (2xx), redirect (3xx), client error (4xx), server error (5xx)
> - **Target processing time** — how long your backend took
> - **Request processing time** — total time including ALB overhead
> - **SSL cipher and protocol** — TLS version and encryption used
> - **Actions taken** — which listener rule matched, whether WAF blocked it
> 
> Metrics tell you "5xx errors spiked." Logs tell you "IP 203.0.113.50 sent 500 requests to /api/login in 60 seconds, all returned 503, target processing time was 30+ seconds suggesting backend overload."

---

## The S3 Bucket Policy Reality

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** Why does the S3 bucket need a special policy? Can't we just create a bucket and point ALB at it?*
> 
> **A (Explain Like I'm 10):** Imagine you want the mail carrier (ALB) to put packages inside your garage (S3 bucket). But your garage has a lock! Just because YOU own the garage doesn't mean the mail carrier has the key. The bucket policy is like giving the mail carrier a special key that ONLY lets them drop off packages — they can't take anything out or look at what's already there. AWS ELB has its own AWS account that needs explicit permission to write to YOUR bucket.
> 
> **Evaluator Question:** *What's the ELB service account, and why does the bucket policy reference it?*
> 
> **Model Answer:** AWS runs Elastic Load Balancing from region-specific AWS-owned accounts. When ALB writes access logs, it's the ELB service account doing the write — not your account. The bucket policy must grant `s3:PutObject` permission to the ELB account ID for your region (e.g., `127311923021` for us-east-1). Without this policy, ALB cannot write logs even though you own both the ALB and the bucket. The `aws_elb_service_account` data source in Terraform automatically retrieves the correct account ID for your region.

---

## Terraform Implementation

### Step 1: Add Variables

**Action:** Append to `variables.tf`:

```hcl
# ============================================================
# Bonus D: ALB Access Logs Configuration
# ============================================================

variable "enable_alb_access_logs" {
  description = "Enable ALB access logging to S3."
  type        = bool
  default     = true
}

variable "alb_access_logs_prefix" {
  description = "S3 prefix for ALB access logs."
  type        = string
  default     = "alb-access-logs"
}
```

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** Why make `enable_alb_access_logs` a variable instead of just always enabling it?*
> 
> **A (Explain Like I'm 10):** Imagine your house has an option to record every conversation. In your regular home, you might not want that (too much data, costs money). But in your business office, you definitely want records! Making it a toggle lets you choose. In development environments, you might skip logs to save money. In production, you ALWAYS enable them. The variable lets the same Terraform code work in both situations without editing.
> 
> **Evaluator Question:** *Why use a prefix for ALB logs instead of dumping them in the bucket root?*
> 
> **Model Answer:** Prefixes provide organizational structure and enable:
> - **Multiple log sources** — same bucket can hold ALB logs, CloudFront logs, WAF logs under different prefixes
> - **Lifecycle policies** — different retention rules per prefix (keep ALB logs 90 days, archive WAF logs 7 years)
> - **IAM scoping** — restrict access to specific prefixes for different teams
> - **S3 Select efficiency** — query specific prefixes without scanning entire bucket
> - **Cost management** — easier to track storage costs per log type
> 
> A flat bucket becomes unmanageable quickly in production.

---

### Step 2: Create the Terraform File

**Action:** Create `bonus_d_apex_alb_logs.tf`:

```hcl
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
# Data source: Current AWS account ID
# ------------------------------------------------------------
data "aws_caller_identity" "current" {}

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
    name                   = aws_lb.chewbacca_alb01.dns_name
    zone_id                = aws_lb.chewbacca_alb01.zone_id
    evaluate_target_health = true
  }
}
```

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** Why do we have TWO different principals in the bucket policy — one AWS account and one Service?*
> 
> **A (Explain Like I'm 10):** AWS changed how they deliver logs over time. It's like how mail delivery evolved — first there were individual mail carriers (the old ELB account method), then the postal service got a fleet (the new service principal method). Some regions use the old way, some use the new way, and some use both! By including both principals, your bucket works no matter which delivery method AWS uses in your region. It's future-proofing.
> 
> **Evaluator Question:** *What does `evaluate_target_health = true` do on the ALIAS record, and when would you set it to false?*
> 
> **Model Answer:** When `evaluate_target_health = true`, Route53 monitors the ALB's health. If ALB becomes unhealthy (all targets down), Route53 can return no answer or failover to a backup record (if you have one). This enables DNS-level failover. 
> 
> Set it to `false` when:
> - You have a single ALB with no failover and want DNS to always return it (let the ALB handle health)
> - You're using Route53 health checks separately
> - The ALB is behind CloudFront (CloudFront handles failover, not DNS)
> 
> For most production cases with a single ALB, `true` is correct — but understand it adds Route53 health check costs and behavior.

---

### Step 3: Patch the Existing ALB Resource

> [!warning] **⚠️ CRITICAL PATCH**
> Terraform cannot "append" nested blocks. You MUST manually edit `bonus_b.tf` to add the `access_logs` block inside your existing ALB resource.

**Action:** In `bonus_b.tf`, find `resource "aws_lb" "chewbacca_alb01"` and add this block inside it...this is tricky. Do this very carefully:

```hcl
  # ============================================================
  # Access Logs: Chewbacca keeps flight logs for incident response
  # ============================================================
  access_logs {
    bucket  = var.enable_alb_access_logs ? aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket : ""
    prefix  = var.alb_access_logs_prefix
    enabled = var.enable_alb_access_logs
  }
```


> [!note] **SOCRATIC Q&A**
> 
> ***Q:** Why can't we just create a separate Terraform resource for the access_logs configuration?*
> 
> **A (Explain Like I'm 10):** Imagine you're building a LEGO spaceship. Some pieces MUST be attached while you're building the main body — you can't add the engine as a separate step after the ship is sealed up. The `access_logs` block is like that engine — it's part of the ALB definition itself, not a separate attachment. Terraform sees the ALB as one complete object. You have to open up the original definition and add the piece inside.
> 
> **Evaluator Question:** *What's the "learning friction" principle being applied here?*
> 
> **Model Answer:** Learning friction means intentionally requiring students to modify existing code rather than just copying new files. This:
> - Forces you to UNDERSTAND the existing ALB structure
> - Teaches real-world refactoring skills (you'll inherit code and need to modify it)
> - Builds confidence that you can safely change infrastructure
> - Mirrors production reality where you patch existing resources, not start fresh
> 
> If we gave you a complete new ALB resource, you'd learn nothing about integrating changes into existing infrastructure — which is 80% of real cloud work.

---

### Step 4: Add Outputs

**Action:** Append to `outputs.tf`:

```hcl
# ============================================================
# Bonus D Outputs
# ============================================================

# Explanation: The apex URL is the front gate—humans type this when they forget subdomains.
output "chewbacca_apex_url_https" {
  description = "HTTPS URL for the zone apex (naked domain)"
  value       = "https://${var.domain_name}"
}

# Explanation: Log bucket name is where the footprints live—useful when hunting 5xx or WAF blocks.
output "chewbacca_alb_logs_bucket_name" {
  description = "S3 bucket name for ALB access logs"
  value       = var.enable_alb_access_logs ? aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket : null
}

# Explanation: Full S3 path prefix for finding logs quickly during incidents
output "chewbacca_alb_logs_path" {
  description = "Full S3 path where ALB logs are stored"
  value       = var.enable_alb_access_logs ? "s3://${aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/elasticloadbalancing/${var.aws_region}/" : null
}
```

---

## Verification Commands

### Verify Zone Apex DNS Record

> [!tip] **VERIFICATION: Zone Apex Record Exists**
> ```bash
> # List Route53 records for the apex
> aws route53 list-resource-record-sets \
>   --hosted-zone-id <ZONE_ID> \
>   --query "ResourceRecordSets[?Name=='chewbacca-growl.com.']"
> 
> # Expected: Type = "A" with AliasTarget pointing to ALB
> 
> # Test DNS resolution
> dig chewbacca-growl.com A +short
> 
> # Expected: Returns ALB IP addresses (these rotate)
> 
> # Test HTTPS access
> curl -I https://chewbacca-growl.com
> 
> # Expected: HTTP/2 200 (or 301 redirect)
> ```

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** Why does `dig` show IP addresses but the Terraform shows an ALIAS to a DNS name?*
> 
> **A (Explain Like I'm 10):** When you look up your friend's phone number in your contacts, you see "Alex - 555-1234." But when your phone actually calls, it uses just the number, not the name. Route53 ALIAS is like your contacts — it STORES the ALB's DNS name, but when someone asks "what's the IP?", Route53 looks up that name and RETURNS the actual IP addresses. The dig command shows you what the phone sees (numbers), not what your contacts app stores (name + number).
> 
> **Evaluator Question:** *How do ALIAS records differ from CNAME records in terms of DNS queries?*
> 
> **Model Answer:** 
> | Aspect | CNAME | ALIAS |
> |--------|-------|-------|
> | DNS Response | Returns another domain name (requires second lookup) | Returns IP addresses directly (one lookup) |
> | Zone Apex | ❌ Not allowed at apex | ✅ Allowed at apex |
> | Query Charges | Standard Route53 pricing | Free for AWS resources |
> | TTL | You set it | Inherited from target |
> | Health Checks | Separate configuration | Built-in with `evaluate_target_health` |
> 
> ALIAS is faster and cheaper for AWS resources.

---

### Verify ALB Logging Configuration

> [!tip] **VERIFICATION: ALB Access Logs Enabled**
> ```bash
> # Step 1: Get the ALB ARN
> ALB_ARN=$(aws elbv2 describe-load-balancers \
>   --names chewbacca-alb01 \
>   --query "LoadBalancers[0].LoadBalancerArn" \
>   --output text)
> 
> # Step 2: Check ALB attributes
> aws elbv2 describe-load-balancer-attributes \
>   --load-balancer-arn "$ALB_ARN" \
>   --query "Attributes[?Key=='access_logs.s3.enabled' || Key=='access_logs.s3.bucket' || Key=='access_logs.s3.prefix']"
> 
> # Expected output:
> # [
> #   { "Key": "access_logs.s3.enabled", "Value": "true" },
> #   { "Key": "access_logs.s3.bucket", "Value": "chewbacca-alb-logs-123456789012" },
> #   { "Key": "access_logs.s3.prefix", "Value": "alb-access-logs" }
> # ]
> ```

---

### Generate Traffic and Verify Logs

> [!tip] **VERIFICATION: Logs Appearing in S3**
> ```bash
> # Step 1: Generate some traffic
> curl -I https://chewbacca-growl.com
> curl -I https://app.chewbacca-growl.com
> curl -I https://chewbacca-growl.com/nonexistent-page  # generates 404
> 
> # Step 2: Wait 5 minutes (ALB batches logs every 5 minutes)
> 
> # Step 3: Check for logs in S3
> aws s3 ls s3://<BUCKET_NAME>/alb-access-logs/AWSLogs/<ACCOUNT_ID>/elasticloadbalancing/ --recursive | head
> 
> # Expected: .gz files with timestamps
> # Example: alb-access-logs/AWSLogs/123456789012/elasticloadbalancing/us-east-1/2024/01/15/...
> 
> # Step 4: Download and inspect a log file
> aws s3 cp s3://<BUCKET_NAME>/<PATH_TO_LOG_FILE>.gz ./
> gunzip *.gz
> cat *.log | head -5
> ```

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** Why does it take 5 minutes for logs to appear? Why not instant?*
> 
> **A (Explain Like I'm 10):** Imagine if your teacher wrote a note to your parents every single time you raised your hand in class. That would be exhausting and wasteful! Instead, teachers usually write a summary at the end of the day. ALB does the same thing — instead of writing to S3 after EVERY request (expensive and slow), it collects requests for 5 minutes, then writes them all at once in a batch. This is efficient and cheaper, but means you wait a bit to see recent logs.
> 
> **Evaluator Question:** *How would you access logs faster than the 5-minute batch window during an active incident?*
> 
> **Model Answer:** For real-time visibility during incidents:
> 1. **CloudWatch Metrics** — ALB metrics update every minute (request count, 5xx errors, latency)
> 2. **CloudWatch Logs via ALB** — Not native, but you can stream to CloudWatch via Lambda
> 3. **WAF Logs** — If using WAF, logs can stream to CloudWatch Logs, S3, or Firehose in near-real-time
> 4. **VPC Flow Logs** — Network-level visibility without waiting for ALB batching
> 5. **AWS Firehose + real-time processing** — Stream ALB logs to Firehose for sub-minute delivery
> 
> For most incidents, 5-minute delay is acceptable for forensics. For real-time blocking, use WAF with CloudWatch metrics.

---

## Understanding ALB Log Format

Each log entry contains fields separated by spaces. Key fields for incident response:

| **Field** | **What It Tells You** | **Incident Use** |
|-----------|----------------------|------------------|
| `client:port` | Source IP and port | Who sent the request |
| `request_processing_time` | Time ALB spent | ALB overload detection |
| `target_processing_time` | Time backend spent | Backend performance issues |
| `response_processing_time` | Time to send response | Large response or client issues |
| `elb_status_code` | HTTP status ALB returned | Error rate analysis |
| `target_status_code` | HTTP status from backend | Backend errors vs ALB errors |
| `request` | HTTP method + path + query | What was requested |
| `user_agent` | Client software | Bot detection, browser issues |
| `ssl_cipher` | TLS cipher used | Security audit, compatibility |
| `actions_executed` | WAF/routing actions | Which rules matched |

> [!note] **SOCRATIC Q&A**
> 
> ***Q:** What's the difference between `elb_status_code` and `target_status_code`?*
> 
> **A (Explain Like I'm 10):** Imagine you call a pizza place (ALB) and ask for pepperoni pizza. The phone operator (ALB) might say "Sorry, we're closed" (ELB status 503) — that's the ALB's response. Or the operator might connect you to the kitchen (target), and the kitchen says "Sorry, we're out of pepperoni" (target status 404). The ELB status is what the ALB itself decided. The target status is what your backend EC2 said. If ELB shows an error but target is empty (`-`), the request never reached your backend — the problem is network or ALB-level.
> 
> **Evaluator Question:** *You see logs showing `elb_status_code=504` but `target_status_code=-`. What does this indicate?*
> 
> **Model Answer:** This indicates a **gateway timeout** where:
> - The request reached ALB
> - ALB tried to forward to the target
> - Target never responded within the timeout period
> - ALB gave up and returned 504
> 
> The `-` for target_status means no response was received. Root causes:
> 1. Target is down/crashed
> 2. Security group blocking ALB → Target
> 3. Target overloaded and not responding
> 4. Application deadlock or infinite loop
> 5. Network connectivity between ALB and target
> 
> Check: Target health status, security groups, application logs on EC2, `target_processing_time` for recent successful requests.

---

## Troubleshooting Common Issues

| **Symptom** | **Likely Cause** | **Fix** |
|-------------|------------------|---------|
| `terraform apply` fails with "Access Denied" on S3 | Bucket policy not applied before ALB references it | Use `depends_on` or apply twice |
| Logs not appearing after 5+ minutes | Bucket policy missing ELB service account | Verify policy includes correct regional ELB account |
| Zone apex returns NXDOMAIN | Record not created or wrong zone ID | Verify zone_id matches your hosted zone |
| Zone apex returns wrong IP | Cached old record | Wait for TTL to expire or flush DNS |
| Logs appear but are empty | Traffic not reaching ALB | Check CloudFront/WAF, verify ALB is receiving requests |

---

## Deliverables Checklist

| **Requirement** | **Verification Command** | **Expected Result** |
|-----------------|-------------------------|---------------------|
| Zone apex DNS record exists | `dig chewbacca-growl.com A +short` | Returns IP addresses |
| HTTPS works on apex | `curl -I https://chewbacca-growl.com` | HTTP/2 200 or 301 |
| ALB logging enabled | `aws elbv2 describe-load-balancer-attributes` | access_logs.s3.enabled = true |
| S3 bucket exists with policy | `aws s3 ls s3://<BUCKET>/` | Bucket is accessible |
| Logs appearing in S3 | `aws s3 ls s3://<BUCKET>/<PREFIX>/ --recursive` | .gz log files present |

---

## Reflection Questions

**A) Why can't you use a CNAME record for the zone apex?**

DNS RFC prohibits CNAME at the zone apex because it would conflict with SOA and NS records that MUST exist at the apex. Route53 ALIAS is a proprietary solution that returns A records while internally behaving like a CNAME.

**B) What information would you extract from ALB logs during a 5xx error spike?**

Client IPs (is it one source or many?), request paths (one endpoint or all?), target_status_code vs elb_status_code (backend issue or ALB issue?), target_processing_time (slow backend or timeout?), timestamp patterns (sudden spike or gradual increase?).

**C) Why do we set a 90-day lifecycle policy on logs?**

Balance between cost and forensic value. 90 days covers most incident investigations and audit requirements. Older logs can be archived to Glacier if compliance requires longer retention. Infinite retention = infinite cost growth.

**D) How do ALB logs complement WAF logs?**

ALB logs show ALL traffic (allowed and blocked) with backend behavior. WAF logs show only requests that matched WAF rules. Together: WAF shows "who we blocked and why," ALB shows "what happened to requests we allowed."

---

## What This Lab Proves About You

*If you complete this bonus, you've demonstrated:*

- **DNS mastery** — Zone apex ALIAS configuration for professional domain handling
- **Operational readiness** — Access logs for incident response and forensics
- **S3 security** — Bucket policies with service principals
- **Cost awareness** — Lifecycle policies to manage storage growth

**"I can configure production-grade DNS and logging for real incident response."**

This is how companies ship. You're operating like a real cloud engineer.

---

## What's Next

**Lab 1C Bonus E:** WAF Logging (CloudWatch / S3 / Firehose)
- Stream WAF decisions to CloudWatch Logs for real-time analysis
- Build on this foundation with security-specific observability

**Lab 1C Bonus F:** CloudWatch Logs Insights Queries
- Write operational runbooks using Logs Insights
- Query both ALB and WAF logs for incident patterns
