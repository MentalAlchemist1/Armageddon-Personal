# Lab 1C Bonus D: Zone Apex + ALB Access Logs

## Complete Step-by-Step Guide with Socratic Q&A

---

> [!warning] **⚠️ PREREQUISITE**
> Lab 1C Bonus C must be completed and verified before starting Bonus D. You must have:
> - Route53 hosted zone configured (either Terraform-managed or existing)
> - ACM certificate validated
> - ALB with TLS (HTTPS listener)
> - WAF attached to ALB
> - CloudWatch Dashboard operational

---

## Lab Overview

**What You'll Build:**

| Component | What It Does | Why It Matters |
|-----------|--------------|----------------|
| Zone Apex ALIAS | `wheresjack.com` → ALB | Users can type the naked domain (no www) |
| ALB Access Logs | Every request logged to S3 | Incident response forensics |

**Time Estimate:** 45-60 minutes (including troubleshooting)

---

## PART 1: Pre-Flight Audit

Before adding new resources, we need to audit your existing codebase. This prevents the naming convention drift and duplicate resource errors that commonly occur when adding code from different lab guide versions.

---

### Step 1.1: Identify Your ALB Resource Name

**Why This Matters:** Different lab versions use different naming conventions. You need to know YOUR ALB's Terraform resource name to reference it correctly.

**Action:** Run this command from your `terraform-files` directory:

```bash
grep -rn "resource \"aws_lb\"" *.tf
```

**Expected Output (example):**
```
bonus_b.tf:55:resource "aws_lb" "main" {
```

**Record your ALB resource name:** `_______________` (e.g., `aws_lb.main` or `aws_lb.chewbacca_alb01`)

> [!note] **SOCRATIC Q&A: Why Different Names Exist**
> 
> ***Q:** Why might my ALB be named differently than what the lab guide shows?*
> 
> **A (Explain Like I'm 10):** Imagine you and your friend both build the same LEGO set, but you name your spaceship "Millennium Falcon" and your friend names theirs "Space Cruiser." Both spaceships work the same way — the name is just a label YOU chose. In Terraform, the resource name (the part after `"aws_lb"`) is YOUR label. The lab guide might say `chewbacca_alb01`, but your code might use `main`. Both create an ALB — but you must use YOUR label consistently throughout your code.
> 
> **Evaluator Question:** *What's the difference between a Terraform resource name and an AWS resource name?*
> 
> **Model Answer:** The Terraform resource name (e.g., `aws_lb.main`) is an internal reference used only within your Terraform code — AWS never sees it. The AWS resource name (e.g., `chewbacca-alb01`) is the actual Name tag visible in the AWS Console. You reference Terraform names in your `.tf` files; you see AWS names in the Console and CLI output.

---

### Step 1.2: Identify Your Route53 Zone Configuration

**Why This Matters:** Your Route53 zone might be managed by Terraform OR it might be a pre-existing zone created by the domain registrar. You need to reference the correct zone ID.

**Action:** Check if you have a data source or local for the zone ID:

```bash
grep -rn "zone_id\|chewbacca_zone_id\|aws_route53_zone" *.tf
```

**Action:** List your actual Route53 hosted zones in AWS:

```bash
aws route53 list-hosted-zones --query "HostedZones[*].[Id,Name,Config.PrivateZone]" --output table
```

**Record your findings:**
- Zone ID: `_______________` (e.g., `Z08529463796GXWJTC93E`)
- How it's referenced in Terraform: `_______________` (e.g., `local.chewbacca_zone_id` or `data.aws_route53_zone.main.zone_id`)

> [!note] **SOCRATIC Q&A: Why Multiple Zones Can Exist**
> 
> ***Q:** Why might I have two hosted zones with the same domain name?*
> 
> **A (Explain Like I'm 10):** Imagine you have two phone books — one your parents made when you were born (the registrar zone) and one you made yourself (Terraform-created zone). Both have your family's name on the cover, but only ONE is the "real" phone book that people actually use to find your number. The "real" one is whichever zone your domain's NS (nameserver) records point to. If you add your phone number to the wrong book, nobody can reach you!
> 
> **Evaluator Question:** *How do you determine which hosted zone is "active" for a domain?*
> 
> **Model Answer:** Check the domain's NS records at the registrar level using `dig NS yourdomain.com`. The nameservers returned must match one of your hosted zones. In Route53, each hosted zone has unique NS records (shown in the zone's NS record set). The zone whose NS records match the registrar's NS delegation is the "active" zone where DNS records will actually resolve.

---

### Step 1.3: Check for Existing Route53 Records

**Why This Matters:** You might already have a Route53 record for `www.yourdomain.com` from a previous lab step. Creating a duplicate causes Terraform to fail.

**Action:** Find all Route53 record resources in your code:

```bash
grep -rn "aws_route53_record" *.tf
```

**Action:** List existing DNS records in your hosted zone:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id YOUR_ZONE_ID \
  --query "ResourceRecordSets[?Type=='A'].[Name,Type]" \
  --output table
```

**Record what exists:**
- [ ] `www.yourdomain.com` A record exists in AWS
- [ ] `www.yourdomain.com` A record exists in Terraform (which file? _______________)
- [ ] Zone apex (`yourdomain.com`) A record exists in AWS
- [ ] Zone apex A record exists in Terraform

---

### Step 1.4: Check for Duplicate Data Sources

**Why This Matters:** If a data source like `aws_caller_identity` already exists in another file, declaring it again causes a "duplicate resource" error.

**Action:** Check for existing data sources:

```bash
grep -rn "data \"aws_caller_identity\"" *.tf
grep -rn "data \"aws_elb_service_account\"" *.tf
grep -rn "data \"aws_route53_zone\"" *.tf
```

**Record what exists:**
- `aws_caller_identity` in file: `_______________` (or "not found")
- `aws_elb_service_account` in file: `_______________` (or "not found")
- `aws_route53_zone` in file: `_______________` (or "not found")

---

## PART 2: Add Variables for ALB Logging

### Step 2.1: Add Variables to `variables.tf`

**Action:** Open `variables.tf` and append these variables at the end of the file:

```bash
# Open the file in your editor
code variables.tf   # VS Code
# OR
nano variables.tf   # Terminal editor
```

**Add this code block:**

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

**Verification:** Save the file and run:

```bash
terraform validate
```

**Expected:** `Success! The configuration is valid.`

> [!note] **SOCRATIC Q&A: Why Variables Instead of Hardcoding**
> 
> ***Q:** Why make `enable_alb_access_logs` a variable instead of just always enabling it?*
> 
> **A (Explain Like I'm 10):** Imagine your house has an option to record every conversation. In your regular home, you might not want that (too much data, costs money). But in your business office, you definitely want records! Making it a toggle lets you choose. In development environments, you might skip logs to save money. In production, you ALWAYS enable them. The variable lets the same Terraform code work in both situations without editing.
> 
> **Evaluator Question:** *Why use a prefix for ALB logs instead of dumping them in the bucket root?*
> 
> **Model Answer:** Prefixes provide organizational structure and enable: (1) Multiple log sources in one bucket (ALB, CloudFront, WAF under different prefixes), (2) Different lifecycle policies per prefix, (3) IAM scoping to restrict access by prefix, (4) S3 Select query efficiency, (5) Easier cost tracking per log type.

---

## PART 3: Create the Bonus D Terraform File

### Step 3.1: Create `bonus_d_apex_alb_logs.tf`

**Action:** Create a new file named `bonus_d_apex_alb_logs.tf`:

```bash
touch bonus_d_apex_alb_logs.tf
code bonus_d_apex_alb_logs.tf   # Open in VS Code
```

**Add the following code.** Read the comments to understand each section.

> [!warning] **IMPORTANT: Customize These References**
> Before pasting, note:
> - If you found `aws_caller_identity` already exists, **DO NOT** include that data source
> - Replace `aws_lb.main` with YOUR ALB resource name from Step 1.1
> - Replace `local.chewbacca_zone_id` with YOUR zone reference from Step 1.2

```hcl
# ============================================================
# BONUS D: Zone Apex + ALB Access Logs
# ============================================================
# This file adds:
#   1) Zone apex (wheresjack.com) ALIAS → ALB
#   2) S3 bucket for ALB access logs with required bucket policy
# ============================================================

# ------------------------------------------------------------
# Data source: ELB Service Account for your region
# ------------------------------------------------------------
# AWS runs ELB from their own accounts. We need to know WHICH 
# account so we can grant them permission to write to our S3 bucket.
data "aws_elb_service_account" "main" {}

# ------------------------------------------------------------
# Data source: Current AWS account ID
# ------------------------------------------------------------
# ONLY INCLUDE THIS IF IT DOESN'T ALREADY EXIST IN ANOTHER FILE!
# Check with: grep -rn "data \"aws_caller_identity\"" *.tf
# If it exists elsewhere, DELETE these 3 lines:
data "aws_caller_identity" "current" {}

# ------------------------------------------------------------
# S3 Bucket for ALB Access Logs
# ------------------------------------------------------------
# This bucket stores every request that hits your ALB.
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
# The ELB service needs explicit permission to write to YOUR bucket.
# We include BOTH the legacy account-based principal AND the new 
# service principal for compatibility across all AWS regions.
resource "aws_s3_bucket_policy" "chewbacca_alb_logs_policy01" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.chewbacca_alb_logs_bucket01[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowELBServiceAccountToPutLogs"
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
# S3 Bucket Lifecycle: Auto-expire old logs after 90 days
# ------------------------------------------------------------
# Logs are valuable, but infinite logs = infinite cost.
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
# This lets users type "wheresjack.com" (no www/subdomain)
# and still reach your ALB. Humans forget subdomains!
#
# ⚠️ UPDATE: Replace aws_lb.main with YOUR ALB resource name
# ⚠️ UPDATE: Replace local.chewbacca_zone_id with YOUR zone reference
resource "aws_route53_record" "chewbacca_apex01" {
  zone_id = local.chewbacca_zone_id  # UPDATE THIS if your zone reference is different
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name      # UPDATE THIS to your ALB resource
    zone_id                = aws_lb.main.zone_id       # UPDATE THIS to your ALB resource
    evaluate_target_health = true
  }
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------
output "apex_url_https" {
  description = "Zone apex HTTPS URL"
  value       = "https://${var.domain_name}"
}

output "alb_logs_bucket_name" {
  description = "S3 bucket name for ALB access logs"
  value       = var.enable_alb_access_logs ? aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket : "disabled"
}

output "alb_logs_path" {
  description = "S3 path where ALB logs are stored"
  value       = var.enable_alb_access_logs ? "s3://${aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/elasticloadbalancing/${var.aws_region}/" : "disabled"
}
```

**Verification:** Save the file and run:

```bash
terraform validate
```

> [!note] **SOCRATIC Q&A: Why Two Principals in the Bucket Policy?**
> 
> ***Q:** Why do we have TWO different principals — one AWS account and one Service?*
> 
> **A (Explain Like I'm 10):** AWS changed how they deliver logs over time. It's like how mail delivery evolved — first there were individual mail carriers (the old ELB account method), then the postal service got a fleet (the new service principal method). Some regions use the old way, some use the new way! By including both principals, your bucket works no matter which delivery method AWS uses in your region. It's future-proofing.
> 
> **Evaluator Question:** *What does `evaluate_target_health = true` do on the ALIAS record?*
> 
> **Model Answer:** When `true`, Route53 monitors the ALB's health. If ALB becomes unhealthy (all targets down), Route53 can failover to a backup record if configured. For a single ALB with no failover, this adds health monitoring but won't change DNS behavior since there's no backup target.

---

## PART 4: Modify the Existing ALB Resource

### Step 4.1: Add `access_logs` Block to Your ALB

**Why This Matters:** Terraform can't "append" to existing resources. You must manually edit the ALB resource to add the `access_logs` block.

**Action:** Open the file containing your ALB resource (identified in Step 1.1):

```bash
code bonus_b.tf   # Or whichever file contains your ALB
```

**Action:** Find your ALB resource. It looks something like:

```hcl
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb01"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # ... other configuration ...

  tags = {
    Name = "${var.project_name}-alb01"
  }
}
```

**Action:** Add the `access_logs` block AND the `depends_on` block INSIDE the resource:

```hcl
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb01"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # ============================================================
  # Access Logs: Log every request to S3 for incident response
  # ============================================================
  access_logs {
    bucket  = var.enable_alb_access_logs ? aws_s3_bucket.chewbacca_alb_logs_bucket01[0].bucket : ""
    prefix  = var.alb_access_logs_prefix
    enabled = var.enable_alb_access_logs
  }

  # ... rest of your existing configuration ...

  tags = {
    Name = "${var.project_name}-alb01"
  }

  # ============================================================
  # Dependency: Bucket policy must exist before ALB tries to write
  # ============================================================
  depends_on = [
    aws_s3_bucket_policy.chewbacca_alb_logs_policy01
  ]
}
```

> [!warning] **CRITICAL: `depends_on` Must Be INSIDE the Resource Block**
> The `depends_on` line must be INSIDE the closing brace of the resource, not after it. Putting it outside causes a syntax error.

**Verification:**

```bash
terraform validate
```

> [!note] **SOCRATIC Q&A: Why `depends_on` is Required Here**
> 
> ***Q:** Terraform usually figures out dependencies automatically. Why do we need explicit `depends_on`?*
> 
> **A (Explain Like I'm 10):** Imagine you're baking a cake. Terraform is smart enough to know you need to mix ingredients BEFORE putting the pan in the oven (it sees you reference the batter). But what if the recipe says "make sure the oven is preheated"? Terraform doesn't see a direct ingredient connection — the oven just needs to BE ready. `depends_on` is you telling Terraform: "Trust me, the oven (bucket policy) MUST be ready before I put the pan in (enable ALB logging)." Without it, Terraform might try to enable logging before AWS has granted the bucket permission, causing "Access Denied."
> 
> **Evaluator Question:** *What error would you see if the bucket policy doesn't exist when ALB tries to enable logging?*
> 
> **Model Answer:** `InvalidConfigurationRequest: Access Denied for bucket: <bucket-name>`. This happens because ALB validates it can write to the bucket during configuration. Without the policy granting ELB permission, the validation fails even though you own both resources.

---

## PART 5: Validate, Plan, and Apply

### Step 5.1: Validate Configuration

**Action:** Run validation:

```bash
terraform validate
```

**Expected:** `Success! The configuration is valid.`

**If you get errors, see the Troubleshooting section at the end of this guide.**

---

### Step 5.2: Run Terraform Plan

**Action:** Generate an execution plan:

```bash
terraform plan
```

**Review the plan carefully. You should see:**
- `aws_s3_bucket.chewbacca_alb_logs_bucket01[0]` — CREATE
- `aws_s3_bucket_policy.chewbacca_alb_logs_policy01[0]` — CREATE
- `aws_s3_bucket_lifecycle_configuration...` — CREATE
- `aws_s3_bucket_public_access_block...` — CREATE
- `aws_route53_record.chewbacca_apex01` — CREATE
- `aws_lb.main` — UPDATE (to add access_logs)

**If the plan shows unexpected changes or errors, see Troubleshooting.**

---

### Step 5.3: Apply Changes

**Action:** Apply the configuration:

```bash
terraform apply
```

**When prompted:** Type `yes` to confirm.

**Expected Output:**

```
Apply complete! Resources: 5 added, 1 changed, 0 destroyed.

Outputs:

alb_logs_bucket_name = "chewbacca-alb-logs-262164343754"
alb_logs_path = "s3://chewbacca-alb-logs-262164343754/alb-access-logs/AWSLogs/262164343754/elasticloadbalancing/us-west-2/"
apex_url_https = "https://wheresjack.com"
...
```

---

## PART 6: Verification

### Step 6.1: Verify Zone Apex DNS

**Action:** Test DNS resolution:

```bash
# Zone apex should resolve to ALB IPs
dig wheresjack.com A +short

# Should match the app subdomain IPs
dig www.wheresjack.com A +short
```

**Expected:** Both commands return the same 2-3 IP addresses.

**Action:** Verify the record type (should be A, not CNAME):

```bash
dig wheresjack.com +noall +answer
```

**Expected:** Shows `A` record type, not `CNAME`.

---

### Step 6.2: Verify HTTPS Connectivity

**Action:** Test zone apex HTTPS:

```bash
curl -I https://wheresjack.com
```

**Expected:** `HTTP/2 200` (or `301` redirect, then `200`)

**Action:** Test app subdomain HTTPS:

```bash
curl -I https://www.wheresjack.com
```

**Expected:** `HTTP/2 200`

---

### Step 6.3: Verify ALB Access Logs Enabled

**Action:** Check ALB attributes:

```bash
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn $(aws elbv2 describe-load-balancers \
    --names chewbacca-alb01 \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text) \
  --query "Attributes[?starts_with(Key, 'access_logs')]"
```

**Expected:**

```json
[
    { "Key": "access_logs.s3.enabled", "Value": "true" },
    { "Key": "access_logs.s3.bucket", "Value": "chewbacca-alb-logs-262164343754" },
    { "Key": "access_logs.s3.prefix", "Value": "alb-access-logs" }
]
```

---

### Step 6.4: Verify S3 Bucket Configuration

**Action:** Check bucket exists and has correct policy:

```bash
# Bucket exists
aws s3api head-bucket --bucket chewbacca-alb-logs-262164343754

# Public access is blocked
aws s3api get-public-access-block \
  --bucket chewbacca-alb-logs-262164343754 \
  --query "PublicAccessBlockConfiguration"
```

**Expected:** No errors; all public access blocks show `true`.

---

### Step 6.5: Verify Logs Appear in S3

**Action:** Generate traffic:

```bash
for i in {1..10}; do curl -s https://wheresjack.com > /dev/null; done
```

**Action:** Wait 5-10 minutes (ALB batches logs every 5 minutes).

**Action:** Check for logs:

```bash
aws s3 ls s3://chewbacca-alb-logs-262164343754/alb-access-logs/AWSLogs/262164343754/elasticloadbalancing/us-west-2/ --recursive | head
```

**Expected:** `.log.gz` files with timestamps.

---

### Step 6.6: Verify Route53 Records

**Action:** List A records in your hosted zone:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id Z08529463796GXWJTC93E \
  --query "ResourceRecordSets[?Type=='A'].[Name,AliasTarget.DNSName]" \
  --output table
```

**Expected:** Shows both `wheresjack.com` and `www.wheresjack.com` pointing to ALB DNS name.

---

## PART 7: All-in-One Verification Script

**Action:** Run this complete verification:

```bash
echo "=== Lab 1C Bonus D Verification ==="
echo ""
echo "1. Zone Apex DNS:"
dig wheresjack.com A +short
echo ""
echo "2. HTTPS Connectivity:"
curl -sI https://wheresjack.com | head -1
curl -sI https://www.wheresjack.com | head -1
echo ""
echo "3. ALB Access Logs Enabled:"
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --names chewbacca-alb01 --query "LoadBalancers[0].LoadBalancerArn" --output text) \
  --query "Attributes[?starts_with(Key, 'access_logs')].{Key:Key,Value:Value}" --output table
echo ""
echo "4. S3 Bucket Public Access Block:"
aws s3api get-public-access-block --bucket chewbacca-alb-logs-262164343754 --query "PublicAccessBlockConfiguration" --output table
echo ""
echo "5. Route53 A Records:"
aws route53 list-resource-record-sets --hosted-zone-id Z08529463796GXWJTC93E --query "ResourceRecordSets[?Type=='A'].[Name]" --output text
echo ""
echo "=== Verification Complete ==="
```

---

## TROUBLESHOOTING: Common Errors and Resolutions

This section documents actual errors encountered during lab completion and their solutions.

---

### Error 1: Duplicate Data Source

**Error Message:**
```
Error: Duplicate data "aws_caller_identity" configuration
  on bonus_d_apex_alb_logs.tf line 19
```

**Root Cause:** The `data "aws_caller_identity" "current" {}` data source already exists in another file (check `bonus_a.tf` or similar).

**Resolution:** Delete the duplicate data source declaration from `bonus_d_apex_alb_logs.tf`. Terraform shares data sources across all `.tf` files in the same directory.

**Prevention:** Always run the audit in Part 1 before adding new data sources.

---

### Error 2: Resource Reference Not Found (ALB Naming Mismatch)

**Error Message:**
```
Error: Reference to undeclared resource
  aws_lb.chewbacca_alb01 is not declared in the root module
```

**Root Cause:** The bonus_d file references `aws_lb.chewbacca_alb01` but your actual ALB is named `aws_lb.main` (or vice versa).

**Resolution:**
1. Find your actual ALB resource name:
   ```bash
   grep -rn "resource \"aws_lb\"" *.tf
   ```
2. Update all references in `bonus_d_apex_alb_logs.tf` to use the correct name.

**Prevention:** Complete Step 1.1 and use YOUR resource names, not the guide's examples.

---

### Error 3: Access Denied When Enabling ALB Logging

**Error Message:**
```
Error: modifying ELBv2 Load Balancer attributes
InvalidConfigurationRequest: Access Denied for bucket: chewbacca-alb-logs-262164343754
```

**Root Cause:** Terraform tried to enable ALB access logs before the S3 bucket policy was applied. This is a race condition.

**Resolution:** Add explicit `depends_on` inside the ALB resource:

```hcl
resource "aws_lb" "main" {
  # ... existing config ...

  depends_on = [
    aws_s3_bucket_policy.chewbacca_alb_logs_policy01
  ]
}
```

Then run `terraform apply` again.

---

### Error 4: Multiple Route53 Hosted Zones Matched

**Error Message:**
```
Error: multiple Route 53 Hosted Zones matched
  with data.aws_route53_zone.main
```

**Root Cause:** You have two or more hosted zones with the same domain name (common when Terraform creates a zone but the registrar also created one).

**Diagnosis:**
```bash
aws route53 list-hosted-zones --query "HostedZones[*].[Id,Name,ResourceRecordSetCount]" --output table
```

**Resolution Options:**

**Option A:** Use the existing registrar zone (recommended):
1. Identify the correct zone (the one with more records, or check which one the domain NS records point to)
2. Update `variables.tf`:
   ```hcl
   variable "route53_hosted_zone_id" {
     default = "Z08529463796GXWJTC93E"  # Your actual zone ID
   }
   ```
3. Delete any `data.aws_route53_zone.main` data sources
4. Use a local or variable for zone references:
   ```hcl
   locals {
     chewbacca_zone_id = var.route53_hosted_zone_id
   }
   ```

**Option B:** Delete the unused Terraform-created zone in AWS Console, then re-run Terraform.

---

### Error 5: Route53 Record Already Exists

**Error Message:**
```
Error: creating Route53 Record: InvalidChangeBatch: 
[Tried to create resource record set [name='www.wheresjack.com.', type='A'] but it already exists]
```

**Root Cause:** You have two Terraform resources trying to create the same DNS record (e.g., one in `variables.tf` and one in `bonus_b.tf`).

**Diagnosis:**
```bash
grep -rn "aws_route53_record" *.tf | grep -i "app\|www"
```

**Resolution:**
1. Identify which files contain duplicate record resources
2. Delete ONE of them (keep the one in the most logical location, usually near related resources)
3. Run `terraform apply`

---

### Error 6: Missing ACM Certificate Resource

**Error Message:**
```
Error: Reference to undeclared resource
  aws_acm_certificate.chewbacca_acm_cert01 is not declared
```

**Root Cause:** The HTTPS listener references a Terraform-managed ACM certificate, but the certificate resource was never created (you may have originally created the certificate manually in the Console).

**Diagnosis:**
```bash
grep -rn "aws_acm_certificate" *.tf
```

If you only see REFERENCES (`.arn`, `.domain_validation_options`) but no `resource "aws_acm_certificate"`, the resource is missing.

**Resolution:** Add the ACM certificate resource to your Route53/SSL file:

```hcl
resource "aws_acm_certificate" "chewbacca_acm_cert01" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-acm-cert01"
    Environment = var.environment
  }
}
```

---

### Error 7: Orphaned `depends_on` Outside Resource Block

**Error Message:**
```
Error: Unsupported block type
  Blocks of type "depends_on" are not expected here.
```

**Root Cause:** The `depends_on` was placed AFTER the resource's closing brace instead of INSIDE it.

**Wrong:**
```hcl
resource "aws_lb" "main" {
  # config
}

depends_on = [aws_s3_bucket_policy.chewbacca_alb_logs_policy01]  # WRONG - outside!
```

**Correct:**
```hcl
resource "aws_lb" "main" {
  # config

  depends_on = [aws_s3_bucket_policy.chewbacca_alb_logs_policy01]  # CORRECT - inside!
}
```

---

### Error 8: Reference to Deleted Data Source

**Error Message:**
```
Error: Reference to undeclared resource
  data.aws_route53_zone.main.zone_id is not declared
```

**Root Cause:** You deleted the `data.aws_route53_zone.main` data source but other files still reference it.

**Diagnosis:**
```bash
grep -rn "data.aws_route53_zone.main" *.tf
```

**Resolution:** Update all references to use your zone local/variable:

```hcl
# Change this:
zone_id = data.aws_route53_zone.main.zone_id

# To this:
zone_id = local.chewbacca_zone_id
```

Check ALL files, including outputs files (`*_outputs.tf`).

---

## Reflection Questions

**A) Why can't you use a CNAME record for the zone apex?**

DNS RFC prohibits CNAME at the zone apex because it would conflict with SOA and NS records that MUST exist at the apex. Route53 ALIAS is a proprietary solution that returns A records while internally behaving like a CNAME.

**B) What information would you extract from ALB logs during a 5xx error spike?**

Client IPs (one source or many?), request paths (one endpoint or all?), target_status_code vs elb_status_code (backend issue or ALB issue?), target_processing_time (slow backend?), timestamp patterns (sudden spike or gradual?).

**C) Why do we set a 90-day lifecycle policy on logs?**

Balance between cost and forensic value. 90 days covers most incident investigations and audit requirements. Older logs can be archived to Glacier if compliance requires longer retention. Infinite retention = infinite cost growth.

**D) How do ALB logs complement WAF logs?**

ALB logs show ALL traffic (allowed and blocked) with backend behavior. WAF logs show only requests that matched WAF rules. Together: WAF shows "who we blocked and why," ALB shows "what happened to requests we allowed."

---

## Deliverables Checklist

| Requirement | Verification Command | Expected Result |
|-------------|---------------------|-----------------|
| Zone apex DNS record exists | `dig wheresjack.com A +short` | Returns IP addresses |
| HTTPS works on apex | `curl -I https://wheresjack.com` | HTTP/2 200 or 301 |
| ALB logging enabled | See Step 6.3 command | access_logs.s3.enabled = true |
| S3 bucket exists with policy | `aws s3 ls s3://<BUCKET>/` | Bucket accessible |
| Public access blocked | See Step 6.4 command | All blocks = true |
| Logs appearing in S3 | See Step 6.5 command | .gz files present (after 5 min) |

---

## What This Lab Proves About You

*If you complete this bonus, you've demonstrated:*

- **DNS mastery** — Zone apex ALIAS configuration for professional domain handling
- **Operational readiness** — Access logs for incident response and forensics
- **S3 security** — Bucket policies with service principals
- **Cost awareness** — Lifecycle policies to manage storage growth
- **Troubleshooting skills** — Resolving real-world Terraform configuration issues

**"I can configure production-grade DNS and logging, and debug infrastructure-as-code issues methodically."**

---

## What's Next

**Lab 1C Bonus E:** WAF Logging (CloudWatch / S3 / Firehose)
- Stream WAF decisions to CloudWatch Logs for real-time analysis
- Build on this foundation with security-specific observability
