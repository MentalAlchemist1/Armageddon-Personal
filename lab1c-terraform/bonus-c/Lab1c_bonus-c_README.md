# SEIR FOUNDATIONS
# LAB 1C BONUS-C: Route53 DNS + ACM Validation

*Enhanced Socratic Q&A Guide*

---

## ⚠️ PREREQUISITE

> **Lab 1C Bonus-B must be completed and verified before starting Bonus-C.**
> You must have:
> - ALB with TLS (HTTPS listener on port 443)
> - ACM certificate created (may still be pending validation)
> - WAF attached to ALB
> - Working EC2 → RDS application

---

## Bonus-C Overview

Bonus-C connects your infrastructure to the **real internet** through DNS. You're creating the "phone book entry" that lets users type `app.chewbacca-growl.com` instead of memorizing ugly ALB DNS names.

### What You're Building

| Component | Purpose | Career Value |
|-----------|---------|--------------|
| Route53 Hosted Zone | DNS authority for your domain | Domain management fundamentals |
| ACM DNS Validation | Prove you own the domain to get TLS cert | Certificate lifecycle management |
| ALIAS Record | Point `app.domain.com` → ALB | Production DNS patterns |

---

## Why DNS Matters (Industry Context)

> **SOCRATIC Q&A**
>
> ***Q:** I can already access my app via the ALB DNS name. Why do I need Route53?*
>
> **A (Explain Like I'm 10):** Imagine if instead of calling your friend "Alex," you had to say "Human-located-at-123-Oak-Street-Apartment-4B-Third-Floor." That's what ALB DNS names are like: `chewbacca-alb01-1234567890.us-east-1.elb.amazonaws.com`. Nobody wants to type that! DNS is like a phone book that lets people use easy names (`app.chewbacca-growl.com`) that secretly translate to the ugly addresses computers need.
>
> **Evaluator Question:** *Why do production applications need custom domain names instead of default AWS endpoints?*
>
> **Model Answer:** Custom domains provide: (1) **Brand identity** - users trust `mycompany.com` more than random AWS URLs, (2) **Portability** - if you migrate to another load balancer or cloud provider, you update DNS instead of changing every link, (3) **TLS certificates** - ACM certificates are issued for YOUR domain, not AWS's, (4) **SEO and marketing** - memorable URLs drive traffic, (5) **Professional credibility** - AWS endpoints scream "demo project" to customers.

---

## Part 1: Understanding the DNS → TLS → ALB Chain

Before writing Terraform, understand how these pieces connect:

```
User types: app.chewbacca-growl.com
        ↓
Route53 resolves: "That points to ALB at xyz.elb.amazonaws.com"
        ↓
Browser connects to ALB on port 443 (HTTPS)
        ↓
ALB presents TLS certificate (ACM) proving it's really chewbacca-growl.com
        ↓
Browser says "Certificate valid!" → secure green lock
        ↓
Traffic flows to private EC2 targets
```

> **SOCRATIC Q&A**
>
> ***Q:** Why does the certificate need to match the domain name? Can't I just use any certificate?*
>
> **A (Explain Like I'm 10):** Imagine you're visiting your friend's house. You knock, and someone opens the door holding an ID card. If the ID says "Alex Smith" and you're at 123 Oak Street where Alex lives, great! But if the ID says "Bob Johnson," you'd be suspicious—is this really Alex's house, or did someone break in? TLS certificates are ID cards for websites. The certificate MUST match the domain you typed, or your browser warns you: "This might not be who you think it is!"
>
> **Evaluator Question:** *What happens if a user navigates to your ALB's raw DNS name instead of your custom domain?*
>
> **Model Answer:** The browser will show a certificate mismatch warning. The ACM certificate is issued for `chewbacca-growl.com` and `app.chewbacca-growl.com`, NOT for `xyz.elb.amazonaws.com`. The connection might still work (with user override), but users will see scary "Not Secure" warnings. This is why we redirect all traffic through the custom domain and why origin cloaking (Lab 2) hides the ALB entirely.

---

## Part 2: Terraform File Structure for Bonus-C

| File | Purpose |
|------|---------|
| `variables.tf` | Add Route53 management toggles |
| `bonus_c_route53.tf` | Hosted zone + DNS validation + ALIAS record |
| `outputs.tf` | Zone ID and HTTPS URL outputs |
| `bonus_b.tf` | Update HTTPS listener depends_on |

---

## Step 1: Add Variables for Route53 Management

**Why variables?** You might already have a Route53 hosted zone from the AWS console, or you might want Terraform to create it. Variables give you flexibility.

### Action: Append to `variables.tf`

```hcl
# ==============================================
# ROUTE53 CONFIGURATION
# ==============================================

variable "manage_route53_in_terraform" {
  description = "If true, create/manage Route53 hosted zone in Terraform. If false, use existing zone."
  type        = bool
  default     = true
}

variable "route53_hosted_zone_id" {
  description = "If manage_route53_in_terraform=false, provide existing Hosted Zone ID."
  type        = string
  default     = ""
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why would someone NOT want Terraform to manage their Route53 zone?*
>
> **A (Explain Like I'm 10):** Imagine you already have a family address book that everyone uses. Creating a NEW address book in Terraform means you'd have two books—confusing! If your domain's DNS is already set up in Route53 (maybe by another team, or manually), you don't want Terraform to create a duplicate. Instead, you tell Terraform: "Here's the ID of the existing address book—just add entries to it."
>
> **Evaluator Question:** *What problems occur if you accidentally create a duplicate hosted zone for the same domain?*
>
> **Model Answer:** DNS chaos: (1) Your domain registrar points to ONE zone's name servers, (2) If Terraform creates a SECOND zone, its name servers are different, (3) Records in the second zone are invisible to the internet because the registrar doesn't know about them, (4) You'll waste hours debugging "why doesn't my DNS work?" Common symptom: `terraform apply` succeeds but `dig` returns nothing. Always verify your registrar's NS records match your active zone.

---

## Step 2: Create the Route53 Hosted Zone (Conditional)

### Action: Create `bonus_c_route53.tf`

```hcl
############################################
# BONUS-C: Route53 DNS + ACM Validation
############################################

# ==============================================
# HOSTED ZONE (Conditional Creation)
# ==============================================

# Explanation: The hosted zone is like registering your neighborhood in the 
# city's official directory. Without it, nobody can find addresses in your area.

resource "aws_route53_zone" "chewbacca_zone01" {
  count = var.manage_route53_in_terraform ? 1 : 0
  
  name    = var.domain_name
  comment = "Managed by Terraform - ${var.project_name}"
  
  tags = {
    Name        = "${local.name_prefix}-zone01"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ==============================================
# LOCAL: Resolve Zone ID (created vs existing)
# ==============================================

# Explanation: This local is like a switchboard operator—it figures out 
# which zone ID to use regardless of how it was created.

locals {
  chewbacca_zone_id = var.manage_route53_in_terraform ? aws_route53_zone.chewbacca_zone01[0].zone_id : var.route53_hosted_zone_id
  
  chewbacca_app_fqdn = "${var.app_subdomain}.${var.domain_name}"
}
```

> **SOCRATIC Q&A**
>
> ***Q:** What's that `count = var.manage_route53_in_terraform ? 1 : 0` doing?*
>
> **A (Explain Like I'm 10):** It's a light switch! When `manage_route53_in_terraform` is `true`, count = 1 means "create ONE of these." When it's `false`, count = 0 means "create ZERO of these"—the resource doesn't exist at all. This lets the same Terraform code work for both scenarios: "make me a new zone" vs. "use my existing zone."
>
> **Evaluator Question:** *Why use `[0]` when referencing the zone in the local?*
>
> **Model Answer:** When a resource uses `count`, Terraform treats it as a LIST, even if count is 1. `aws_route53_zone.chewbacca_zone01` becomes a list, so you must access the first (and only) element with `[0]`. Forgetting this causes errors like: `aws_route53_zone.chewbacca_zone01 is a list of objects, not a single object`. This is a common Terraform gotcha that trips up beginners.

---

## Step 3: Create ACM DNS Validation Records

DNS validation proves to AWS that you control the domain. ACM gives you a special record to add; when Route53 serves that record, ACM says "Yep, they own it!"

### Action: Continue in `bonus_c_route53.tf`

```hcl
# ==============================================
# ACM DNS VALIDATION RECORDS
# ==============================================

# Explanation: ACM says "prove you own this domain by adding a secret code 
# to your DNS." This is like AWS sending a letter that only the real owner 
# of the mailbox can receive and respond to.

resource "aws_route53_record" "chewbacca_acm_validation_records01" {
  for_each = {
    for dvo in aws_acm_certificate.chewbacca_acm_cert01.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.chewbacca_zone_id
}

# ==============================================
# ACM CERTIFICATE VALIDATION (DNS Method)
# ==============================================

# Explanation: This resource WAITS until ACM sees the validation records 
# and issues the certificate. It's like waiting at the DMV until they 
# call your number and hand you your license.

resource "aws_acm_certificate_validation" "chewbacca_acm_validation01_dns" {
  certificate_arn         = aws_acm_certificate.chewbacca_acm_cert01.arn
  validation_record_fqdns = [for record in aws_route53_record.chewbacca_acm_validation_records01 : record.fqdn]
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why does ACM need "validation"? Why can't I just request a certificate for any domain?*
>
> **A (Explain Like I'm 10):** Imagine anyone could walk into the DMV and say "I'm the President, give me a White House ID card." Chaos! Certificate authorities (like ACM) need PROOF you control the domain before giving you a certificate. Otherwise, bad guys could get certificates for `google.com` and trick people. DNS validation proves you control the domain's DNS—if you can add the secret record, you must be the real owner.
>
> **Evaluator Question:** *What are the differences between DNS validation and email validation for ACM certificates?*
>
> **Model Answer:** 
> | DNS Validation | Email Validation |
> |----------------|------------------|
> | Add CNAME record to DNS | Click link sent to admin@domain.com |
> | Fully automatable in Terraform | Requires manual human action |
> | Certificate auto-renews | Must re-validate on renewal |
> | Preferred for production | Good for quick one-time certs |
> 
> DNS validation is the industry standard because it enables zero-touch certificate renewal—critical for production systems where you don't want 2 AM pages about expiring certs.

> **SOCRATIC Q&A**
>
> ***Q:** What's that `for_each` loop doing? It looks complicated.*
>
> **A (Explain Like I'm 10):** When you request a certificate for `chewbacca-growl.com` AND `app.chewbacca-growl.com`, ACM gives you TWO validation challenges—one for each name. The `for_each` loop says "for EACH challenge ACM gives me, create a DNS record." It's like getting a homework packet with 3 worksheets: you don't write one piece of code per worksheet, you write a loop that handles however many worksheets you get.
>
> **Evaluator Question:** *Why is `allow_overwrite = true` set on the validation records?*
>
> **Model Answer:** If you run `terraform apply` multiple times, or if you're replacing an old certificate, the validation record names might already exist. Without `allow_overwrite = true`, Terraform fails with "record already exists." This setting tells Terraform: "If the record exists, update it instead of erroring." It's safe for validation records because they're machine-generated and should always match ACM's requirements.

---

## Step 4: Create ALIAS Record for App Subdomain

The ALIAS record is the "phone book entry" that points `app.chewbacca-growl.com` to your ALB.

### Action: Continue in `bonus_c_route53.tf`

```hcl
# ==============================================
# ALIAS RECORD: app.chewbacca-growl.com -> ALB
# ==============================================

# Explanation: This is the holographic sign outside the cantina—
# "app.chewbacca-growl.com" now points to your ALB. 
# Visitors see your domain, not AWS's ugly URL.

resource "aws_route53_record" "chewbacca_app_alias01" {
  zone_id = local.chewbacca_zone_id
  name    = local.chewbacca_app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.chewbacca_alb01.dns_name
    zone_id                = aws_lb.chewbacca_alb01.zone_id
    evaluate_target_health = true
  }
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why use an ALIAS record instead of a regular CNAME?*
>
> **A (Explain Like I'm 10):** Regular CNAME records are like sticky notes that say "go ask someone else." If you ask for `app.example.com`, the CNAME says "actually, go ask `xyz.elb.amazonaws.com`"—that's TWO lookups. ALIAS is like a smart sticky note that does the work FOR you. It looks up the ALB's actual IP addresses and gives them directly. Faster! Plus, CNAMEs can't be used at the "zone apex" (`chewbacca-growl.com` with no subdomain), but ALIAS can.
>
> **Evaluator Question:** *What does `evaluate_target_health = true` do?*
>
> **Model Answer:** Route53 performs health checks on the ALB. If the ALB is unhealthy (no healthy targets, or ALB itself is down), Route53 can stop sending traffic to it. This is critical for multi-region failover architectures: if your primary ALB dies, Route53 can route to a backup. For single-region setups, it still provides visibility—Route53 health check metrics show ALB availability.

> **SOCRATIC Q&A**
>
> ***Q:** The ALB already has a `zone_id`? I thought zone IDs were for hosted zones?*
>
> **A (Explain Like I'm 10):** Great catch! AWS load balancers live in special AWS-managed hosted zones (one per region). When you create an ALIAS to an ALB, you need to tell Route53 "this ALB lives in AWS's zone for us-east-1 ELBs." It's like mailing a letter: you need both the address (`dns_name`) AND the zip code (`zone_id`). AWS provides both values automatically on the ALB resource.
>
> **Evaluator Question:** *How would you add a second ALIAS for the zone apex (`chewbacca-growl.com` without `app.`)?*
>
> **Model Answer:** Duplicate the resource with different `name`:
> ```hcl
> resource "aws_route53_record" "chewbacca_apex_alias01" {
>   zone_id = local.chewbacca_zone_id
>   name    = var.domain_name  # No subdomain!
>   type    = "A"
>   alias {
>     name                   = aws_lb.chewbacca_alb01.dns_name
>     zone_id                = aws_lb.chewbacca_alb01.zone_id
>     evaluate_target_health = true
>   }
> }
> ```
> This enables both `chewbacca-growl.com` AND `app.chewbacca-growl.com` to reach your ALB.

---

## Step 5: Update HTTPS Listener Dependency

The HTTPS listener needs the certificate to be ISSUED before it can use it. Add a dependency on DNS validation.

### Action: Update `bonus_b.tf` HTTPS Listener

```hcl
# ==============================================
# HTTPS LISTENER (Updated for DNS Validation)
# ==============================================

# Explanation: The HTTPS listener is the real hangar bay—TLS terminates here, 
# then traffic flows to private targets. It MUST wait for the certificate 
# to be validated, or it fails with "certificate not yet issued."

resource "aws_lb_listener" "chewbacca_https_listener01" {
  load_balancer_arn = aws_lb.chewbacca_alb01.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  
  # Use the certificate ARN directly
  certificate_arn   = aws_acm_certificate.chewbacca_acm_cert01.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chewbacca_tg01.arn
  }

  # CRITICAL: Wait for DNS validation to complete!
  # Without this, Terraform might try to create the listener before 
  # the certificate is issued, causing failures.
  depends_on = [
    aws_acm_certificate_validation.chewbacca_acm_validation01_dns
  ]
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why do we need `depends_on` here? Doesn't Terraform figure out dependencies automatically?*
>
> **A (Explain Like I'm 10):** Terraform is smart, but not THAT smart. It sees that the listener uses `aws_acm_certificate.chewbacca_acm_cert01.arn` and waits for the certificate to be CREATED. But "created" isn't the same as "validated and issued!" The certificate exists immediately, but it's in PENDING_VALIDATION status until DNS validation completes. `depends_on` says: "Don't just wait for the certificate to exist—wait for the VALIDATION resource to complete too."
>
> **Evaluator Question:** *What error would you see if you forgot the `depends_on`?*
>
> **Model Answer:** You'd likely see: `UnsupportedCertificate: The certificate 'arn:aws:acm:...' must have a fully-qualified domain name, a supported signature, and a supported key size.` This misleading error actually means the certificate isn't validated yet. The listener creation races ahead of validation. Adding `depends_on` forces Terraform to wait. This is a VERY common production issue when setting up TLS for the first time.

---

## Step 6: Add Outputs

### Action: Append to `outputs.tf`

```hcl
# ==============================================
# ROUTE53 + DNS OUTPUTS
# ==============================================

# Explanation: Outputs are the nav computer readout—Chewbacca needs 
# coordinates that humans can paste into browsers.

output "chewbacca_route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = local.chewbacca_zone_id
}

output "chewbacca_app_url_https" {
  description = "HTTPS URL for the application"
  value       = "https://${var.app_subdomain}.${var.domain_name}"
}

output "chewbacca_route53_name_servers" {
  description = "Name servers for the hosted zone (update your domain registrar!)"
  value       = var.manage_route53_in_terraform ? aws_route53_zone.chewbacca_zone01[0].name_servers : ["Using existing zone - check console for NS records"]
}
```

> **SOCRATIC Q&A**
>
> ***Q:** Why output the name servers? What do I do with them?*
>
> **A (Explain Like I'm 10):** When AWS creates a hosted zone, it assigns name servers (like `ns-123.awsdns-45.com`). These are the "official phone operators" for your domain. But your domain registrar (where you bought `chewbacca-growl.com`) doesn't know about them yet! You must LOG INTO your registrar (GoDaddy, Namecheap, Route53 Registrar, etc.) and UPDATE the name server records to match AWS's. Until you do this, the internet can't find your DNS records.
>
> **Evaluator Question:** *What happens if the registrar's name servers don't match Route53's?*
>
> **Model Answer:** DNS resolution fails. The registrar tells the internet "ask ns-OLD.registrar.com for chewbacca-growl.com records." That old server doesn't have your Route53 records. Users get NXDOMAIN (domain doesn't exist) or stale data. This is the #1 reason "I set up Route53 but DNS doesn't work." Always verify: `dig NS chewbacca-growl.com` should return Route53's name servers, not your registrar's defaults.

---

## Verification Commands

### 1. Confirm Hosted Zone Exists

```bash
# If Terraform manages the zone:
aws route53 list-hosted-zones-by-name \
  --dns-name chewbacca-growl.com \
  --query "HostedZones[?Name=='chewbacca-growl.com.'].Id" \
  --output text

# Expected: /hostedzone/Z1234567890ABC
```

### 2. Confirm DNS Validation Records Exist

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --query "ResourceRecordSets[?Type=='CNAME' && contains(Name, '_')]"

# Expected: CNAME records starting with _acm-validation or similar
```

### 3. Confirm App ALIAS Record Exists

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --query "ResourceRecordSets[?Name=='app.chewbacca-growl.com.']"

# Expected: Type=A with AliasTarget pointing to ALB
```

### 4. Confirm Certificate Is Issued

```bash
aws acm describe-certificate \
  --certificate-arn <CERT_ARN> \
  --query "Certificate.Status" \
  --output text

# Expected: ISSUED
# If still PENDING_VALIDATION, DNS propagation may be in progress
```

### 5. Confirm HTTPS Works End-to-End

```bash
# Test HTTPS connection
curl -I https://app.chewbacca-growl.com

# Expected: HTTP/1.1 200 OK (or 301 → 200)

# Verify certificate details
echo | openssl s_client -connect app.chewbacca-growl.com:443 -servername app.chewbacca-growl.com 2>/dev/null | openssl x509 -noout -subject -dates

# Expected: Shows your domain name and valid dates
```

### 6. Verify DNS Resolution

```bash
# Check that DNS resolves to ALB IPs
dig app.chewbacca-growl.com A +short

# Expected: Multiple IP addresses (ALB's IPs)

# Verify name servers are Route53's
dig NS chewbacca-growl.com +short

# Expected: ns-xxxx.awsdns-xx.com (4 servers)
```

---

## Common Failure Modes & Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Certificate stuck in PENDING_VALIDATION | DNS validation records not propagated | Check Route53 has the CNAME records; wait up to 30 minutes |
| `dig` returns NXDOMAIN | Registrar NS records don't match Route53 | Update registrar to use Route53's name servers |
| HTTPS shows certificate error | Accessing via wrong domain (ALB DNS instead of custom) | Always use `https://app.chewbacca-growl.com` |
| `terraform apply` hangs on validation | DNS not reachable from AWS | Verify NS records at registrar; check for typos |
| Listener creation fails | Certificate not yet issued | Add `depends_on` for validation resource |

---

## Complete File: `bonus_c_route53.tf`

```hcl
############################################
# BONUS-C: Route53 DNS + ACM Validation
############################################

# ==============================================
# HOSTED ZONE (Conditional Creation)
# ==============================================

resource "aws_route53_zone" "chewbacca_zone01" {
  count = var.manage_route53_in_terraform ? 1 : 0
  
  name    = var.domain_name
  comment = "Managed by Terraform - ${var.project_name}"
  
  tags = {
    Name        = "${local.name_prefix}-zone01"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ==============================================
# LOCAL: Resolve Zone ID
# ==============================================

locals {
  chewbacca_zone_id  = var.manage_route53_in_terraform ? aws_route53_zone.chewbacca_zone01[0].zone_id : var.route53_hosted_zone_id
  chewbacca_app_fqdn = "${var.app_subdomain}.${var.domain_name}"
}

# ==============================================
# ACM DNS VALIDATION RECORDS
# ==============================================

resource "aws_route53_record" "chewbacca_acm_validation_records01" {
  for_each = {
    for dvo in aws_acm_certificate.chewbacca_acm_cert01.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.chewbacca_zone_id
}

# ==============================================
# ACM CERTIFICATE VALIDATION
# ==============================================

resource "aws_acm_certificate_validation" "chewbacca_acm_validation01_dns" {
  certificate_arn         = aws_acm_certificate.chewbacca_acm_cert01.arn
  validation_record_fqdns = [for record in aws_route53_record.chewbacca_acm_validation_records01 : record.fqdn]
}

# ==============================================
# ALIAS RECORD: app.chewbacca-growl.com -> ALB
# ==============================================

resource "aws_route53_record" "chewbacca_app_alias01" {
  zone_id = local.chewbacca_zone_id
  name    = local.chewbacca_app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.chewbacca_alb01.dns_name
    zone_id                = aws_lb.chewbacca_alb01.zone_id
    evaluate_target_health = true
  }
}
```

---

## Reflection Questions

**A) Why is DNS validation preferred over email validation for production certificates?**

DNS validation enables automatic certificate renewal without human intervention. Email validation requires someone to click a link every time the certificate renews (typically every 13 months). At 3 AM. On a holiday. DNS validation = operational maturity.

**B) What's the relationship between your domain registrar and Route53?**

The registrar is where you BOUGHT the domain and controls the "root" NS records. Route53 is where you MANAGE the domain's DNS records. The registrar must point to Route53's name servers for Route53 to have authority. Think of registrar as the deed holder, Route53 as the property manager.

**C) Why can't you use CNAME records at the zone apex?**

DNS RFC standards prohibit CNAMEs at the zone apex (the "naked" domain like `example.com`) because CNAME means "this name is an ALIAS for another name" and conflicts with other required records (SOA, NS) at the apex. ALIAS records are an AWS-specific workaround that resolves to A/AAAA records internally.

**D) How does ACM certificate renewal work with DNS validation?**

ACM automatically renews certificates ~60 days before expiration. As long as the DNS validation records still exist in Route53, ACM re-validates automatically. If you delete the validation records, renewal fails and your certificate expires. Leave them forever!

---

## What This Lab Proves About You

*If you complete Bonus-C, you've demonstrated:*

- Understanding of DNS fundamentals (zones, records, resolution)
- Certificate lifecycle management (request, validate, issue)
- Infrastructure-as-code for domain management
- Production TLS patterns (ALIAS, health checks, auto-renewal)

> **"I can configure DNS, TLS certificates, and secure ingress using Terraform."**

This is exactly how companies ship. You're operating at the level of a mid-level cloud engineer, not a student clicking around.

---

## What's Next: Bonus-D

**Bonus-D adds:**
- Zone apex ALIAS record (naked domain → ALB)
- ALB access logs to S3
- S3 bucket policy for log delivery

This enables incident response forensics—when something breaks, you'll have the logs to prove what happened.
