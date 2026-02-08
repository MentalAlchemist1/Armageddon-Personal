# SEIR FOUNDATIONS
# LAB 2: CloudFront CDN & Origin Cloaking
## Enhanced Socratic Q&A Guide with Step-by-Step Instructions

> [!important] KEY PRINCIPLE
> Users should never know your origin exists. If they can reach your ALB directly, you have a security hole.

*If you can explain why direct ALB access returns 403, you understand modern CDN security.*

---

## Lab Overview

Lab 2 implements a secure CloudFront CDN architecture in front of your existing Lab 1 infrastructure. You will learn:

| Concept | What You Learn |
|---------|----------------|
| **Origin Cloaking** | Preventing direct access to your ALB using prefix lists and secret headers |
| **Cache Correctness** | Separating static (cacheable) vs dynamic (uncacheable) content behavior |
| **Edge Security** | WAF at CLOUDFRONT scope in us-east-1 for global protection |
| **Policy Separation** | Cache policy vs origin request policy - different knobs for different purposes |

### Target Architecture

```
User --> CloudFront (edge cache + WAF) --> ALB (secret header check) --> EC2
              |
         /static/* = 1-day cache
         /api/*    = no cache, forward all
```

### Prerequisites

Lab 1C Bonus B must be complete with:

| Requirement | Why Needed |
|-------------|------------|
| ALB with HTTPS listener (port 443) | CloudFront connects to origin via HTTPS |
| ACM certificate (us-west-2) | ALB needs valid TLS cert |
| Route53 hosted zone | DNS records will point to CloudFront |
| WAF on ALB (REGIONAL scope) | Existing protection stays in place |

### Your Environment Variables

Before starting, identify these values from your Lab 1 setup:

```bash
# Find your ALB DNS name
aws elbv2 describe-load-balancers --query "LoadBalancers[*].[LoadBalancerName,DNSName]" --output table

# Find your Route53 hosted zone ID
aws route53 list-hosted-zones --query "HostedZones[*].[Name,Id]" --output table

# Find your domain name (from terraform.tfvars or variables)
grep domain_name terraform.tfvars
```

**Record these values - you'll need them throughout:**
- ALB DNS Name: `_______________________________`
- Route53 Zone ID: `_______________________________`
- Domain Name: `_______________________________`

---

# PART 1: LAB 2A - Origin Cloaking

> [!question] SOCRATIC Q&A
> **Q: Why can't I just let users hit my ALB directly? It works fine.**
> 
> **A (Explain Like I'm 10):** Imagine you have a store with a security guard at the front door (CloudFront). The guard checks IDs, blocks troublemakers, and keeps a list of recent visitors (cache). But there's also a back door (ALB) that goes straight to the stockroom. If bad guys find the back door, they bypass ALL your security! Origin cloaking is like putting a special lock on the back door that ONLY the security guard has the key to.
> 
> **Evaluator Question:** How does CloudFront origin cloaking prevent direct origin access?
> 
> **Model Answer:** Three layers: (1) CloudFront prefix list on ALB security group limits source IPs to CloudFront edge nodes only, (2) Secret header (X-Origin-Secret) that CloudFront adds to every request - ALB rejects requests without it, (3) DNS only resolves to CloudFront IPs, not ALB. Even if attackers find the ALB DNS name, they can't reach it.

---

## Step 1: Add us-east-1 Provider Alias

CloudFront WAF and ACM certificates MUST be in us-east-1, regardless of where your other resources live.

### Step 1.1: Open your providers.tf file

```bash
cd ~/terraform-files
nano providers.tf
```

### Step 1.2: Add the us-east-1 provider alias

Add this block to the file (keep your existing provider, just add this one):

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

### Step 1.3: Save and verify

```bash
# Save the file (Ctrl+O, Enter, Ctrl+X in nano)

# Verify the provider is recognized
terraform init
```

**Expected output:** "Terraform has been successfully initialized!"

> [!question] SOCRATIC Q&A
> **Q: Why does CloudFront WAF have to be in us-east-1 specifically?**
> 
> **A (Explain Like I'm 10):** Think of CloudFront like a pizza chain with stores everywhere. The headquarters (us-east-1) has the master recipe book. Even though pizzas get made at local stores around the world, the recipes MUST be stored at headquarters. AWS designed CloudFront this way - the 'recipes' (WAF rules, certificates) live in us-east-1, but they get copied to all the edge locations automatically.

---

## Step 2: Request ACM Certificate in us-east-1

CloudFront requires certificates in us-east-1 (even if your ALB cert is in another region).

### Step 2.1: Request the certificate

Replace `yourdomain.com` with your actual domain:

```bash
aws acm request-certificate \
  --domain-name yourdomain.com \
  --subject-alternative-names "*.yourdomain.com" \
  --validation-method DNS \
  --region us-east-1
```

**Expected output:** 
```json
{
    "CertificateArn": "arn:aws:acm:us-east-1:123456789012:certificate/abc123-..."
}
```

### Step 2.2: Save the certificate ARN

```bash
# Copy the CertificateArn value and save it
export CF_CERT_ARN="arn:aws:acm:us-east-1:123456789012:certificate/abc123-..."
echo $CF_CERT_ARN
```

### Step 2.3: Get DNS validation records

```bash
aws acm describe-certificate \
  --certificate-arn $CF_CERT_ARN \
  --region us-east-1 \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord"
```

**Expected output:**
```json
{
    "Name": "_abc123.yourdomain.com.",
    "Type": "CNAME",
    "Value": "_xyz789.acm-validations.aws."
}
```

### Step 2.4: Create DNS validation record in Route53

**If the CNAME already exists from Lab 1** (same domain), the certificate will validate automatically. Check:

```bash
aws acm describe-certificate \
  --certificate-arn $CF_CERT_ARN \
  --region us-east-1 \
  --query "Certificate.Status"
```

If status is `PENDING_VALIDATION`, create the CNAME record:

```bash
# Get your hosted zone ID (replace with your zone ID)
ZONE_ID="Z08529463796GXWJTC93E"

# Create the validation record (replace values from step 2.3)
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "_abc123.yourdomain.com.",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "_xyz789.acm-validations.aws."}]
      }
    }]
  }'
```

### Step 2.5: Wait for certificate validation

```bash
# Check status every 30 seconds until ISSUED
aws acm describe-certificate \
  --certificate-arn $CF_CERT_ARN \
  --region us-east-1 \
  --query "Certificate.Status"
```

**Expected output after 2-10 minutes:** `"ISSUED"`

> [!warning] TROUBLESHOOTING
> **Issue:** Certificate stays PENDING_VALIDATION for hours
> 
> **Cause:** DNS validation CNAME record not created or not propagated
> 
> **Fix:** Check `aws acm describe-certificate` output for ResourceRecord values, add CNAME to Route53, wait 5-30 minutes for DNS propagation

---

## Step 3: Create Origin Cloaking Terraform File

### Step 3.1: Create the new file

```bash
nano lab2_cloudfront_origin_cloaking.tf
```

### Step 3.2: Add the complete content

Copy and paste this entire block:

```hcl
# =============================================================================
# LAB 2A: Origin Cloaking Resources
# =============================================================================

# -----------------------------------------------------------------------------
# CloudFront Prefix List (AWS-managed list of all CloudFront edge IPs)
# -----------------------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# -----------------------------------------------------------------------------
# ALB Security Group Rule - Only allow traffic from CloudFront
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "alb_ingress_cloudfront" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  description       = "Allow HTTPS from CloudFront only"
}

# -----------------------------------------------------------------------------
# Secret Header - CloudFront will send this, ALB will require it
# -----------------------------------------------------------------------------
resource "random_password" "origin_header_secret" {
  length  = 32
  special = false
}

# -----------------------------------------------------------------------------
# ALB Listener Rule - Allow requests WITH the secret header
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "require_origin_header" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Secret"
      values           = [random_password.origin_header_secret.result]
    }
  }
}

# -----------------------------------------------------------------------------
# ALB Listener Rule - Block everything else with 403
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "default_block" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 99

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["*"]
    }
  }
}
```

### Step 3.3: Save the file

Press `Ctrl+O`, `Enter`, `Ctrl+X`

### Step 3.4: Validate syntax

```bash
terraform validate
```

**Expected output:** "Success! The configuration is valid."

> [!warning] TROUBLESHOOTING
> **Issue:** Error: Reference to undeclared resource "aws_security_group.alb"
> 
> **Cause:** Your Lab 1 used a different resource name
> 
> **Fix:** Find your actual security group name:
> ```bash
> grep "resource \"aws_security_group\"" *.tf
> ```
> Then replace `aws_security_group.alb` with your actual name (e.g., `aws_security_group.main`)

---

## Step 4: Create CloudFront WAF File

### Step 4.1: Create the new file

```bash
nano lab2_cloudfront_shield_waf.tf
```

### Step 4.2: Add the complete content

```hcl
# =============================================================================
# LAB 2A: CloudFront WAF (MUST be in us-east-1)
# =============================================================================

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "${var.project_name}-cf-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-cf-waf-metrics"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-managed-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-aws-common"
      sampled_requests_enabled   = true
    }
  }
}
```

### Step 4.3: Save the file

Press `Ctrl+O`, `Enter`, `Ctrl+X`

### Step 4.4: Validate syntax

```bash
terraform validate
```

**Expected output:** "Success! The configuration is valid."

---

## Step 5: Create CloudFront Distribution File

### Step 5.1: Create the new file

```bash
nano lab2_cloudfront_alb.tf
```

### Step 5.2: Add the complete content

**IMPORTANT:** Replace `var.cloudfront_acm_cert_arn` with your actual certificate ARN from Step 2, or add it to your variables.tf.

```hcl
# =============================================================================
# LAB 2A: CloudFront Distribution
# =============================================================================

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-cf"
  default_root_object = ""
  price_class         = "PriceClass_100"

  # ---------------------------------------------------------------------------
  # Origin Configuration - Points to ALB with secret header
  # ---------------------------------------------------------------------------
  origin {
    origin_id   = "${var.project_name}-alb-origin"
    domain_name = aws_lb.main.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # SECRET HEADER - This is the key to origin cloaking
    custom_header {
      name  = "X-Origin-Secret"
      value = random_password.origin_header_secret.result
    }
  }

  # ---------------------------------------------------------------------------
  # Ordered Cache Behavior 1: Static Content (/static/*)
  # ---------------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "${var.project_name}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = aws_cloudfront_cache_policy.static.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.static.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.static.id
  }

  # ---------------------------------------------------------------------------
  # Ordered Cache Behavior 2: API Routes (/api/*)
  # ---------------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "${var.project_name}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    cache_policy_id          = aws_cloudfront_cache_policy.api_disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  # ---------------------------------------------------------------------------
  # Default Cache Behavior (everything else)
  # ---------------------------------------------------------------------------
  default_cache_behavior {
    target_origin_id       = "${var.project_name}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = aws_cloudfront_cache_policy.api_disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  # ---------------------------------------------------------------------------
  # WAF Association
  # ---------------------------------------------------------------------------
  web_acl_id = aws_wafv2_web_acl.cloudfront.arn

  # ---------------------------------------------------------------------------
  # Domain Aliases
  # ---------------------------------------------------------------------------
  aliases = [var.domain_name, "app.${var.domain_name}"]

  # ---------------------------------------------------------------------------
  # TLS Certificate (must be in us-east-1)
  # ---------------------------------------------------------------------------
  viewer_certificate {
    acm_certificate_arn      = var.cloudfront_acm_cert_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # ---------------------------------------------------------------------------
  # Geographic Restrictions (none)
  # ---------------------------------------------------------------------------
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.project_name}-cloudfront"
  }
}

# Output the CloudFront domain for verification
output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.main.id
}
```

### Step 5.3: Add the certificate variable to variables.tf

```bash
nano variables.tf
```

Add this block at the end of the file:

```hcl
variable "cloudfront_acm_cert_arn" {
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  type        = string
}
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).

### Step 5.4: Add the certificate ARN to terraform.tfvars

```bash
nano terraform.tfvars
```

Add this line (use YOUR certificate ARN from Step 2):

```hcl
cloudfront_acm_cert_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123-..."
```

Save and exit.

### Step 5.5: Validate syntax

```bash
terraform validate
```

> [!warning] TROUBLESHOOTING
> **Issue:** Error: Reference to undeclared resource "aws_lb.main"
> 
> **Cause:** Your Lab 1 used a different resource name for the ALB
> 
> **Fix:** Find your actual ALB resource name:
> ```bash
> grep "resource \"aws_lb\"" *.tf
> ```
> Replace `aws_lb.main` with your actual name throughout the file

---

## Step 6: Create Route53 DNS File

### Step 6.1: Check for existing Route53 records

First, see what Route53 resources exist in your Terraform state:

```bash
terraform state list | grep route53
```

If you see records like `aws_route53_record.app` or `aws_route53_record.apex`, you need to remove them before creating new ones.

### Step 6.2: Remove old Route53 records from Terraform state

```bash
# Remove records from state (they still exist in AWS, just not managed by TF)
terraform state rm aws_route53_record.app 2>/dev/null
terraform state rm aws_route53_record.apex 2>/dev/null
terraform state rm aws_route53_record.chewbacca_apex01 2>/dev/null
```

### Step 6.3: Comment out old Route53 resources in Lab 1 files

Find which files contain the old records:

```bash
grep -l "aws_route53_record" *.tf
```

Open each file and comment out (or delete) the old Route53 record resources. Example:

```bash
nano bonus_b.tf
```

Comment out old records by adding `#` at the start of each line:

```hcl
# resource "aws_route53_record" "app" {
#   zone_id = data.aws_route53_zone.main.zone_id
#   name    = "app.${var.domain_name}"
#   type    = "A"
#   ...
# }
```

Save and exit.

### Step 6.4: Delete existing DNS records in AWS

```bash
# Get your hosted zone ID
ZONE_ID="Z08529463796GXWJTC93E"  # Replace with yours

# List current records to see what exists
aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='A']"
```

Delete existing A records that point to ALB (you'll replace them with CloudFront):

```bash
# Delete apex record (replace values with your actual record)
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "yourdomain.com.",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "Z1H1FL5HABSF5",
        "DNSName": "dualstack.your-alb-dns-name.us-west-2.elb.amazonaws.com.",
        "EvaluateTargetHealth": true
      }
    }
  }]
}'

# Delete app subdomain record
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "app.yourdomain.com.",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "Z1H1FL5HABSF5",
        "DNSName": "dualstack.your-alb-dns-name.us-west-2.elb.amazonaws.com.",
        "EvaluateTargetHealth": true
      }
    }
  }]
}'
```

### Step 6.5: Create the new Route53 file

```bash
nano lab2_cloudfront_r53.tf
```

### Step 6.6: Add the complete content

```hcl
# =============================================================================
# LAB 2A: Route53 DNS Records pointing to CloudFront
# =============================================================================

# -----------------------------------------------------------------------------
# Apex domain (yourdomain.com) -> CloudFront
# -----------------------------------------------------------------------------
resource "aws_route53_record" "apex_to_cloudfront" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# -----------------------------------------------------------------------------
# App subdomain (app.yourdomain.com) -> CloudFront
# -----------------------------------------------------------------------------
resource "aws_route53_record" "app_to_cloudfront" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
```

### Step 6.7: Save and validate

```bash
terraform validate
```

---

## Step 7: Apply Lab 2A Infrastructure

### Step 7.1: Preview changes

```bash
terraform plan
```

Review the output carefully. You should see:
- New resources being created (CloudFront distribution, WAF, security group rules, listener rules, Route53 records)
- No resources being destroyed (unless you're replacing old Route53 records)

### Step 7.2: Apply changes

```bash
terraform apply
```

Type `yes` when prompted.

**This takes 5-15 minutes** (CloudFront distributions take time to deploy globally).

### Step 7.3: Wait for CloudFront deployment

```bash
# Get your distribution ID from the output
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

# Check status
aws cloudfront get-distribution --id $DIST_ID --query "Distribution.Status"
```

**Wait until status is `"Deployed"`** (not "InProgress")

---

## Step 8: Verify Lab 2A

### Step 8.1: Flush local DNS cache

```bash
# macOS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

# Linux
sudo systemd-resolve --flush-caches
```

### Step 8.2: Verify DNS points to CloudFront

```bash
dig yourdomain.com A +short
dig app.yourdomain.com A +short
```

**Expected:** IPs in the `13.35.x.x` range (CloudFront), NOT your ALB IPs

### Step 8.3: Verify CloudFront access works

```bash
curl -I https://yourdomain.com
curl -I https://app.yourdomain.com
```

**Expected:** HTTP/2 200 or 404 (app response), NOT 403

### Step 8.4: Verify direct ALB access is blocked

```bash
# Get your ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[0].DNSName" --output text)

# Try to access directly (should fail)
curl -I -k https://$ALB_DNS
```

**Expected:** HTTP/2 403 with `server: awselb/2.0`

> [!success] VERIFICATION: Lab 2A Complete
> - [ ] `dig yourdomain.com` shows CloudFront IPs (13.35.x.x)
> - [ ] `curl -I https://yourdomain.com` returns 200 or 404 (not 403)
> - [ ] `curl -I -k https://<ALB_DNS>` returns 403 Forbidden
> - [ ] WAF shows in CloudFront console attached to distribution

---

# PART 2: LAB 2B - Cache Correctness

> [!question] SOCRATIC Q&A
> **Q: Why can't I just cache everything? Wouldn't that make my site faster?**
> 
> **A (Explain Like I'm 10):** Imagine a restaurant with a display case (cache) at the front. Putting pre-made sandwiches there is great - customers grab and go! But what if you put a sandwich with someone's NAME on it in the display case? Now anyone might grab it! That's what happens when you cache API responses - User A's private data could be served to User B. Static files (images, CSS, JS) are like generic sandwiches - safe to display. API responses are like custom orders - make them fresh every time.
> 
> **Evaluator Question:** What is the difference between cache policy and origin request policy?
> 
> **Model Answer:** Cache policy determines WHAT goes in the cache key (what makes requests 'same' or 'different'). Origin request policy determines WHAT gets forwarded to origin. They're separate knobs. Example: You might forward Authorization header to origin (so it can authenticate) but NOT include it in cache key (so one user's cached response isn't served to another).

---

## Cache Behavior Strategy

| Path | Strategy | Why |
|------|----------|-----|
| `/static/*` | Aggressive (1 day TTL) | Files rarely change, identical for all users |
| `/api/*` | Disabled (TTL=0) | Responses may be user-specific, stale data = security risk |
| `/api/public-feed` | Origin-driven | Origin decides via Cache-Control headers (Honors) |

---

## Step 1: Create the Cache Policies File

### Step 1.1: Create the new file

```bash
cd ~/terraform-files
nano lab2b_cache_correctness.tf
```

### Step 1.2: Add the complete content

Copy and paste this **entire block**:

```hcl
# =============================================================================
# LAB 2B: Cache Correctness - Policies and Behaviors
# =============================================================================

# =============================================================================
# SECTION 1: CACHE POLICIES
# =============================================================================

# -----------------------------------------------------------------------------
# Static Cache Policy - Aggressive caching for /static/* paths
# - 1 day default TTL
# - No cookies, query strings, or headers in cache key
# - Compression enabled
# -----------------------------------------------------------------------------
resource "aws_cloudfront_cache_policy" "static" {
  name        = "${var.project_name}-cache-static"
  comment     = "Aggressive caching for static assets"
  default_ttl = 86400     # 1 day in seconds
  max_ttl     = 31536000  # 1 year in seconds
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# -----------------------------------------------------------------------------
# API Cache Policy - Caching DISABLED for /api/* paths
# - TTL = 0 (no caching)
# - IMPORTANT: When TTL=0, compression MUST be false
# - IMPORTANT: When TTL=0, all behaviors MUST be "none"
# -----------------------------------------------------------------------------
resource "aws_cloudfront_cache_policy" "api_disabled" {
  name        = "${var.project_name}-cache-api-disabled"
  comment     = "No caching for API routes"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    # CRITICAL: These MUST be false when TTL=0
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}

# =============================================================================
# SECTION 2: ORIGIN REQUEST POLICIES
# =============================================================================

# -----------------------------------------------------------------------------
# API Origin Request Policy - Forward everything origin needs
# - All cookies (for session/auth)
# - All query strings (for filtering/pagination)
# - Selected headers (for CORS, content negotiation)
# -----------------------------------------------------------------------------
resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${var.project_name}-orp-api"
  comment = "Forward all cookies/query strings and selected headers for API"

  cookies_config {
    cookie_behavior = "all"
  }

  query_strings_config {
    query_string_behavior = "all"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Content-Type", "Origin", "Host", "Accept"]
    }
  }
}

# -----------------------------------------------------------------------------
# Static Origin Request Policy - Forward nothing extra
# - No cookies (static files don't need them)
# - No query strings (cache buster in filename instead)
# - No extra headers
# -----------------------------------------------------------------------------
resource "aws_cloudfront_origin_request_policy" "static" {
  name    = "${var.project_name}-orp-static"
  comment = "Minimal forwarding for static assets"

  cookies_config {
    cookie_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "none"
  }

  headers_config {
    header_behavior = "none"
  }
}

# =============================================================================
# SECTION 3: RESPONSE HEADERS POLICY
# =============================================================================

# -----------------------------------------------------------------------------
# Static Response Headers Policy - Add Cache-Control header
# - Tells browsers to cache for 1 day
# - "immutable" tells browsers not to revalidate during max-age
# -----------------------------------------------------------------------------
resource "aws_cloudfront_response_headers_policy" "static" {
  name    = "${var.project_name}-rsp-static"
  comment = "Add Cache-Control header for static assets"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value    = "public, max-age=86400, immutable"
    }
  }
}
```

### Step 1.3: Save the file

Press `Ctrl+O`, `Enter`, `Ctrl+X`

### Step 1.4: Validate syntax

```bash
terraform validate
```

**Expected output:** "Success! The configuration is valid."

> [!warning] TROUBLESHOOTING
> **Issue:** Error: EnableAcceptEncodingGzip is invalid for policy with caching disabled
> 
> **Cause:** AWS doesn't allow compression settings when TTL=0
> 
> **Fix:** Make sure `enable_accept_encoding_gzip = false` and `enable_accept_encoding_brotli = false` in the api_disabled cache policy

> [!warning] TROUBLESHOOTING  
> **Issue:** Error: Headers contains Authorization that is not allowed
> 
> **Cause:** AWS restricts certain headers in origin request policies
> 
> **Fix:** Remove "Authorization" from the headers list - it's not allowed in origin request policies

---

## Step 2: Verify CloudFront Distribution Has Cache Behaviors

The CloudFront distribution file (`lab2_cloudfront_alb.tf`) created in Lab 2A already includes the `ordered_cache_behavior` blocks that reference these policies. Let's verify:

### Step 2.1: Check the distribution file

```bash
grep -A 5 "ordered_cache_behavior" lab2_cloudfront_alb.tf
```

You should see two `ordered_cache_behavior` blocks:
1. One for `/static/*` 
2. One for `/api/*`

If these are missing, open the file and add them (see Lab 2A Step 5.2 for the complete code).

---

## Step 3: Apply Lab 2B Changes

### Step 3.1: Preview changes

```bash
terraform plan
```

**Expected changes:**
- `aws_cloudfront_cache_policy.static` - create
- `aws_cloudfront_cache_policy.api_disabled` - create
- `aws_cloudfront_origin_request_policy.api` - create
- `aws_cloudfront_origin_request_policy.static` - create
- `aws_cloudfront_response_headers_policy.static` - create
- `aws_cloudfront_distribution.main` - update (if behaviors weren't added in 2A)

### Step 3.2: Apply changes

```bash
terraform apply
```

Type `yes` when prompted.

**This takes 5-10 minutes** (CloudFront needs to propagate changes to all edge locations).

### Step 3.3: Wait for deployment

```bash
# Get your distribution ID
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

# Check status repeatedly until "Deployed"
aws cloudfront get-distribution --id $DIST_ID --query "Distribution.Status"
```

**Wait until status is `"Deployed"`**

---

## Step 4: Verify Lab 2B Cache Behaviors

### Step 4.1: Test Static Path Caching

Run this command twice, waiting 3 seconds between:

```bash
# First request
echo "=== First Request ===" && curl -I https://app.yourdomain.com/static/example.txt

# Wait 3 seconds
sleep 3

# Second request
echo "=== Second Request ===" && curl -I https://app.yourdomain.com/static/example.txt
```

**Look for these headers:**
- `cache-control: public, max-age=86400, immutable` ✓ (response headers policy working)
- `age: X` where X is a number > 0 on second request ✓ (caching working)

> [!note] NOTE
> If you get a 502 error, that's OK - it means the file doesn't exist on your server, but the infrastructure is correct. The `cache-control` header proves the response headers policy is applied.

### Step 4.2: Test API Path No-Caching

Run this command twice:

```bash
# First request
echo "=== First Request ===" && curl -I https://app.yourdomain.com/api/list

# Second request
echo "=== Second Request ===" && curl -I https://app.yourdomain.com/api/list
```

**Look for:**
- **NO** `age:` header (not cached)
- `server: Werkzeug/...` (reached Flask origin)
- `x-cache: Error from cloudfront` or `Miss from cloudfront` (not served from cache)

### Step 4.3: Test Query Strings Ignored for Static

```bash
# Request with ?v=1
echo "=== Request with ?v=1 ===" && curl -I "https://app.yourdomain.com/static/example.txt?v=1"

# Wait 3 seconds
sleep 3

# Request with ?v=2 (should use SAME cached object)
echo "=== Request with ?v=2 ===" && curl -I "https://app.yourdomain.com/static/example.txt?v=2"
```

**Look for:**
- Second request shows `age:` header > 0 (proves same cached object was used)
- Query string didn't create a new cache entry

### Step 4.4: Record your verification results

| Test | Command | Expected | Actual Result |
|------|---------|----------|---------------|
| Static caching | `curl -I /static/example.txt` (x2) | `age:` increases | |
| Cache-Control header | Same as above | `cache-control: public, max-age=86400, immutable` | |
| API no-cache | `curl -I /api/list` (x2) | No `age:` header | |
| Query strings ignored | `curl -I /static/x?v=1` then `?v=2` | Same cached object | |

> [!success] VERIFICATION: Lab 2B Complete
> - [ ] Static path shows `cache-control: public, max-age=86400, immutable`
> - [ ] Static path shows `age:` header that increases on subsequent requests
> - [ ] API path does NOT show `age:` header
> - [ ] Different query strings use the same cached static object

---

# HONORS MODULES

## Honors: Origin-Driven Caching

Instead of CloudFront dictating TTLs, let your application decide via Cache-Control headers.

> [!question] SOCRATIC Q&A
> **Q: When should I use origin-driven caching vs CloudFront-controlled caching?**
> 
> **A (Explain Like I'm 10):** Imagine you're a chef (origin). Sometimes you KNOW a dish stays fresh for exactly 2 hours (static files - you can tell CloudFront). But sometimes freshness depends on ingredients you get that morning (API responses - only you know when they expire). Origin-driven caching lets the chef put the expiration date on each dish individually.

### Step 1: Create the Honors file

```bash
nano lab2b_honors_origin_driven.tf
```

### Step 2: Add the content

```hcl
# =============================================================================
# LAB 2B HONORS: Origin-Driven Caching
# Uses AWS-managed policies that respect origin Cache-Control headers
# =============================================================================

# -----------------------------------------------------------------------------
# AWS-Managed Cache Policy - Honors origin Cache-Control
# -----------------------------------------------------------------------------
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# -----------------------------------------------------------------------------
# AWS-Managed Origin Request Policy - Forwards most headers
# -----------------------------------------------------------------------------
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}
```

### Step 3: Save and validate

```bash
terraform validate
```

### Step 4: (Optional) Add an ordered behavior for /api/public-feed

If you want to test origin-driven caching, open `lab2_cloudfront_alb.tf`:

```bash
nano lab2_cloudfront_alb.tf
```

Add this block **BEFORE** the `/api/*` behavior (order matters - more specific paths first):

```hcl
  # ---------------------------------------------------------------------------
  # Honors: Origin-driven caching for public feed
  # ---------------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/api/public-feed"
    target_origin_id       = "${var.project_name}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }
```

Save, validate, and apply:

```bash
terraform validate
terraform apply
```

---

## Honors+: Cache Invalidation (CLI Procedure)

When you need to bust cached content before TTL expires:

### Get your distribution ID

```bash
DIST_ID=$(terraform output -raw cloudfront_distribution_id)
echo "Distribution ID: $DIST_ID"
```

### Invalidate a specific file

```bash
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/static/index.html"
```

### Invalidate an entire directory

```bash
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/static/*"
```

### Invalidate everything (expensive!)

```bash
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"
```

### Check invalidation status

```bash
aws cloudfront list-invalidations --distribution-id $DIST_ID
```

**Cost:** First 1,000 paths/month FREE, then $0.005/path. `/*` counts as ONE path.

---

## Honors++: RefreshHit / Validators (Conceptual)

Understanding conditional requests with ETag headers:

| Concept | What It Means |
|---------|---------------|
| **ETag** | A fingerprint of the content (like a hash) |
| **If-None-Match** | Client says 'I have this version, is it still valid?' |
| **304 Not Modified** | Origin says 'Yep, still valid - don't resend the whole thing' |
| **RefreshHit** | CloudFront revalidated with origin and confirmed cache is still good |

**Interview Answer:**

> "RefreshHit means CloudFront's cache expired but the origin confirmed via ETag/304 that the content hasn't changed, so CloudFront refreshed the TTL without transferring the full response body."

---

# DELIVERABLES

## Deliverable A: Terraform Files

| File | Contains |
|------|----------|
| `lab2_cloudfront_origin_cloaking.tf` | Prefix list, secret header, ALB listener rules |
| `lab2_cloudfront_shield_waf.tf` | WAF with CLOUDFRONT scope in us-east-1 |
| `lab2_cloudfront_alb.tf` | CloudFront distribution with cache behaviors |
| `lab2_cloudfront_r53.tf` | Route53 records pointing to CloudFront |
| `lab2b_cache_correctness.tf` | Cache policies, origin request policies, response headers |
| `lab2b_honors_origin_driven.tf` | AWS-managed policy data sources (Honors) |

---

## Deliverable B: Written Explanation

### Question 1: What is my cache key for /api/* and why?

My cache key for `/api/*` is effectively just the URL path - no cookies, no query strings, no headers are included in the cache key.

However, this is intentional because **caching is disabled (TTL = 0)**. The cache key configuration doesn't matter in practice because nothing is ever cached.

**Why this design:**
- API responses often contain user-specific data (authentication, personalization)
- Caching API responses risks serving User A's data to User B (cache poisoning)
- The 'safe default' is to disable caching entirely for `/api/*` and only enable it explicitly for known-safe endpoints

**The principle:** When in doubt, don't cache. The cost of a cache miss is latency. The cost of a cache poisoning incident is a security breach.

---

### Question 2: What am I forwarding to origin and why?

For `/api/*`, I forward to origin:

| What | Forwarded? | Why |
|------|------------|-----|
| **All cookies** | Yes | Origin needs session/auth cookies to identify the user |
| **All query strings** | Yes | API endpoints use query params for filtering, pagination, IDs |
| **Host header** | Yes | Origin may need to know which domain was requested |
| **Content-Type** | Yes | Origin needs to know the request body format (JSON, form) |
| **Origin header** | Yes | Required for CORS preflight requests |

**Key insight:** Cache policy and origin request policy are **separate knobs**. I forward everything the origin needs to function, but I don't include user-specific values in the cache key - this prevents one user's response from being served to another user.

---

## Deliverable C: Haiku (漢字で、英語なし)

> **忠義の心**
> **銀河を守りて**
> **吼える友**

*Meaning (for reference): Heart of loyalty / Protecting the galaxy / Roaring friend*

---

## Deliverable D: CLI Verification Evidence

| Test | Command | Expected Result |
|------|---------|-----------------|
| Static caching | `curl -I /static/example.txt` (x2) | `age:` header increases |
| API no-cache | `curl -I /api/list` (x2) | No `age:` header |
| Query strings ignored | `curl -I /static/x.txt?v=1` and `?v=2` | Same cached object (`age` present) |
| Origin cloaking | `curl -I -k https://<ALB_DNS>` | HTTP/2 403 Forbidden |
| DNS to CloudFront | `dig yourdomain.com A +short` | 13.35.x.x IPs (CloudFront) |

---

# EVALUATOR QUESTIONS & MODEL ANSWERS

## Origin Cloaking

**Q: How does CloudFront origin cloaking prevent direct origin access?**

A: Three layers: (1) CloudFront prefix list on ALB security group limits source IPs to CloudFront edge nodes only, (2) Secret header (X-Origin-Secret) that CloudFront adds to every request - ALB rejects requests without it, (3) DNS only resolves to CloudFront IPs, not ALB. Even if attackers find the ALB DNS name, they can't reach it.

---

## Cache Safety

**Q: What's the risk of caching API responses?**

A: Cache poisoning - serving one user's response to another. If User A's authenticated response gets cached, User B might receive User A's private data. This is why we disable caching for `/api/*` by default and only enable it for known-safe public endpoints.

---

## Policy Separation

**Q: Why are cache policy and origin request policy separate?**

A: Different purposes. Cache policy = what makes requests 'same' vs 'different' for caching. Origin request policy = what origin needs to function. Example: Forward Authorization header to origin (it needs to authenticate) but don't include in cache key (prevents serving User A's response to User B).

---

## Regional Requirements

**Q: Why must CloudFront WAF be in us-east-1?**

A: CloudFront is a global service with control plane in us-east-1. All CloudFront-scoped resources (WAF, Lambda@Edge, ACM certificates) must be created there. They get replicated to edge locations automatically, but the 'source of truth' lives in us-east-1.

---

## Cache Invalidation

**Q: When would you invalidate the CloudFront cache?**

A: When you deploy new static content (updated CSS/JS) and can't wait for TTL to expire. But invalidation should be surgical - invalidate only changed paths, not `/*`. Best practice is to use versioned filenames (app.v2.js) so the new URL naturally bypasses old cache.

---

# WHAT THIS LAB PROVES ABOUT YOU

> [!success] INTERVIEW-READY STATEMENT
> If you complete this lab, you can confidently say:
> 
> **"I can secure cloud infrastructure using CDN patterns and implement correct caching behavior."**
> 
> This is senior-level cloud architecture knowledge, not entry-level.

**Full Interview Answer:**

> "I implemented CloudFront with origin cloaking using prefix lists and secret headers, ensuring direct ALB access returns 403. I configured path-based cache behaviors - aggressive caching for static assets with response header policies, disabled caching for API routes to prevent cache poisoning. The WAF runs at CLOUDFRONT scope in us-east-1 for edge protection."

**That answer will stop the room.**

---

## Final Checklist

| Requirement | Proof | Status |
|-------------|-------|--------|
| Direct ALB access returns 403 | `curl -I -k https://<ALB>` | ⬜ |
| CloudFront access returns 200 | `curl -I https://domain.com` | ⬜ |
| WAF scope is CLOUDFRONT in us-east-1 | `aws wafv2 get-web-acl` | ⬜ |
| DNS resolves to CloudFront | `dig domain.com A +short` | ⬜ |
| Static shows `age:` header | `curl -I /static/x.txt` | ⬜ |
| Cache-Control header present | `curl -I /static/x.txt` | ⬜ |
| API shows no `age:` header | `curl -I /api/list` | ⬜ |
| Query strings ignored for static | `curl -I /static/x.txt?v=1,2` | ⬜ |
| Written answers complete | Deliverable B | ⬜ |
| Haiku in Japanese | Deliverable C | ⬜ |
