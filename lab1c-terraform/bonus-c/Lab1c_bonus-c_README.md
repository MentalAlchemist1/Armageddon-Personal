# Lab 1C Bonus-C: Route53 DNS + ACM Validation

## Enhanced Step-by-Step Guide with Embedded Socratic Q&A

---

## ⚠️ PREREQUISITES CHECKLIST

Before starting Bonus-C, verify you have completed Bonus-B.

**Action:** Run these verification commands:

```bash
# 1. Verify ALB exists
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'chewbacca')].{Name:LoadBalancerName,DNS:DNSName}" \
  --output table

# 2. Verify ACM certificate exists (may still be PENDING_VALIDATION - that's OK)
aws acm list-certificates \
  --query "CertificateSummaryList[].{Domain:DomainName,Status:Status}" \
  --output table

# 3. Verify HTTPS listener exists on ALB
aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'chewbacca')].LoadBalancerArn" --output text) \
  --query "Listeners[?Port==\`443\`].{Port:Port,Protocol:Protocol}" \
  --output table
```

**Expected Results:**
- ✅ ALB exists with DNS name
- ✅ ACM certificate exists (status may be PENDING_VALIDATION or ISSUED)
- ✅ HTTPS listener on port 443

> **If any check fails, complete Bonus-B first before proceeding.**

---

## 🎯 Bonus-C Overview

**What You're Building:**

| Component | Purpose | What It Does |
|-----------|---------|--------------|
| Route53 Hosted Zone | DNS authority for your domain | Manages all DNS records for `yourdomain.com` |
| ACM DNS Validation Records | Prove domain ownership | CNAME records that tell ACM you control the domain |
| ACM Certificate Validation | Wait for certificate issuance | Resource that blocks until cert status = ISSUED |
| ALIAS Record | Point subdomain → ALB | `www.yourdomain.com` resolves to your ALB |

**End State:** Users type `https://www.yourdomain.com` in their browser and reach your application over HTTPS with a valid TLS certificate.

---

## 🧠 Why DNS Matters (Understand Before You Build)

```
User types: www.yourdomain.com
        ↓
Route53 resolves → "That points to ALB at xyz.elb.amazonaws.com"
        ↓
Browser connects to ALB on port 443 (HTTPS)
        ↓
ALB presents TLS certificate (ACM) proving it's really yourdomain.com
        ↓
Browser says "Certificate valid!" → secure green lock 🔒
        ↓
Traffic flows to private EC2 targets
```

> [!question] SOCRATIC Q&A: Why Custom Domains?
> 
> ***Q:** I can already access my app via the ALB DNS name. Why do I need Route53?*
> 
> **A (Explain Like I'm 10):** Imagine if instead of calling your friend "Alex," you had to say "Human-located-at-123-Oak-Street-Apartment-4B-Third-Floor." That's what ALB DNS names are like: `chewbacca-alb01-1234567890.us-east-1.elb.amazonaws.com`. Nobody wants to type that! DNS is like a phone book that lets people use easy names (`www.yourdomain.com`) that secretly translate to the ugly addresses computers need.
> 
> **Evaluator Question:** *Why do production applications need custom domain names instead of default AWS endpoints?*
> 
> **Model Answer:** Custom domains provide: (1) **Brand identity** - users trust `mycompany.com` more than random AWS URLs, (2) **Portability** - if you migrate to another cloud provider, you update DNS instead of changing every link, (3) **TLS certificates** - ACM certificates are issued for YOUR domain, not AWS's, (4) **SEO and marketing** - memorable URLs drive traffic, (5) **Professional credibility** - AWS endpoints scream "demo project" to customers.

---

## PART 1: Navigate to Your Terraform Directory

### Step 1.1: Find Your Terraform Project Directory

**Action:** Open your terminal and navigate to your Lab 1C Terraform directory:

```bash
cd ~/path/to/your/lab1c-terraform
```

**Action:** Verify you're in the correct directory by checking for Terraform files AND state:

```bash
# List terraform files
ls -la *.tf

# Verify state file exists
ls -la terraform.tfstate 2>/dev/null || ls -la .terraform/ 2>/dev/null
```

**Expected Output:** 
- You should see files like `main.tf`, `variables.tf`, `bonus_b.tf`
- You should see `terraform.tfstate` or `.terraform/` directory

> [!warning] TROUBLESHOOTING: "No state file was found!"
> 
> **Symptom:** Running `terraform state list` shows "No state file was found!"
> 
> **Cause:** You're in the wrong directory. Your Terraform state lives where you originally ran `terraform apply`.
> 
> **Fix:** Find your actual Terraform directory:
> ```bash
> # Find directories with Terraform state
> find ~ -name "terraform.tfstate" 2>/dev/null
> 
> # Or find directories with .tf files
> find ~ -name "main.tf" -type f 2>/dev/null
> ```
> 
> Navigate to that directory before proceeding.

---

### Step 1.2: Verify Current Terraform State

**Action:** Confirm your Bonus-B resources are in the state:

```bash
terraform state list | grep -E "(alb|acm|waf)"
```

**Expected Output:** You should see resources like:
```
aws_acm_certificate.chewbacca_acm_cert01
aws_lb.chewbacca_alb01
aws_lb_listener.chewbacca_https_listener01
aws_wafv2_web_acl.chewbacca_waf01
```

**If you don't see these resources, you're either:**
1. In the wrong directory
2. Haven't completed Bonus-B
3. Resources were created in a different Terraform workspace

---

## PART 2: Add Required Variables

### Step 2.1: Check Existing Variables

Before adding new variables, check what you already have defined.

**Action:** Search for existing variables:

```bash
grep -E "^variable \"(domain_name|app_subdomain|environment|manage_route53)" variables.tf
```

**Possible Outputs:**

| Output | Meaning | Action |
|--------|---------|--------|
| `variable "domain_name"` appears | Already defined in Bonus-B | ✅ Skip adding it |
| `variable "app_subdomain"` appears | Already defined in Bonus-B | ✅ Skip adding it |
| `variable "environment"` appears | Already defined | ✅ Skip adding it |
| No output / grep returns nothing | Variables not defined | ⚠️ Need to add them |

---

### Step 2.2: Add Route53 Variables to `variables.tf`

**Action:** Open `variables.tf` in your code editor:

```bash
code variables.tf
# OR: vim variables.tf
# OR: nano variables.tf
```

**Action:** Scroll to the END of the file and add the following code block:

```hcl
# ==============================================
# ROUTE53 CONFIGURATION (Added in Bonus-C)
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

**Action:** Check if `variable "environment"` already exists in the file:

```bash
grep -n "variable \"environment\"" variables.tf
```

**If NO output (variable doesn't exist)**, add this to `variables.tf`:

```hcl
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}
```

**Action:** Save the file and close your editor.

---

### Step 2.3: Verify Variables Are Valid

**Action:** Run Terraform validate:

```bash
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

> [!warning] TROUBLESHOOTING: "No declaration found for var.environment"
> 
> **Symptom:** 
> ```
> Error: Reference to undeclared input variable
> No declaration found for "var.environment"
> ```
> 
> **Cause:** The `environment` variable is referenced somewhere but not defined in `variables.tf`.
> 
> **Fix:** Add the environment variable to `variables.tf`:
> ```hcl
> variable "environment" {
>   description = "Environment name (e.g., dev, staging, prod)"
>   type        = string
>   default     = "dev"
> }
> ```

> [!question] SOCRATIC Q&A: Why Conditional Zone Management?
> 
> ***Q:** Why would someone NOT want Terraform to manage their Route53 zone?*
> 
> **A (Explain Like I'm 10):** Imagine you already have a family address book that everyone uses. Creating a NEW address book in Terraform means you'd have two books—confusing! If your domain's DNS is already set up in Route53 (maybe by another team, or manually in the console), you don't want Terraform to create a duplicate. Instead, you tell Terraform: "Here's the ID of the existing address book—just add entries to it."
> 
> **Evaluator Question:** *What problems occur if you accidentally create a duplicate hosted zone for the same domain?*
> 
> **Model Answer:** DNS chaos: (1) Your domain registrar points to ONE zone's name servers, (2) If Terraform creates a SECOND zone, its name servers are different, (3) Records in the second zone are invisible to the internet because the registrar doesn't know about them, (4) You'll waste hours debugging "why doesn't my DNS work?" Common symptom: `terraform apply` succeeds but `dig` returns nothing.

---

## PART 3: Create the Route53 Configuration File

### Step 3.1: Create the New File

**Action:** Create a new file called `bonus_c_route53.tf`:

```bash
touch bonus_c_route53.tf
```

**Action:** Open the file in your editor:

```bash
code bonus_c_route53.tf
# OR: vim bonus_c_route53.tf
# OR: nano bonus_c_route53.tf
```

---

### Step 3.2: Add the Hosted Zone Resource

**Action:** Copy and paste this ENTIRE code block into `bonus_c_route53.tf`:

```hcl
############################################
# BONUS-C: Route53 DNS + ACM Validation
# 
# This file creates:
# 1. Route53 Hosted Zone (conditional)
# 2. ACM DNS validation records
# 3. ACM certificate validation resource
# 4. ALIAS record pointing subdomain → ALB
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
  # If Terraform manages the zone, use its ID. Otherwise, use the provided ID.
  chewbacca_zone_id = var.manage_route53_in_terraform ? aws_route53_zone.chewbacca_zone01[0].zone_id : var.route53_hosted_zone_id
  
  # Construct the fully qualified domain name for the app
  chewbacca_app_fqdn = "${var.app_subdomain}.${var.domain_name}"
}
```

**Action:** Save the file (but keep it open—we'll add more code).

---

### Step 3.3: Add ACM DNS Validation Records

**Action:** Add this code block to the END of `bonus_c_route53.tf` (after the locals block):

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
```

**Action:** Save the file.

> [!question] SOCRATIC Q&A: Understanding for_each
> 
> ***Q:** What's that `for_each` loop doing? It looks complicated.*
> 
> **A (Explain Like I'm 10):** When you request a certificate for `yourdomain.com` AND `www.yourdomain.com`, ACM gives you TWO validation challenges—one for each name. The `for_each` loop says "for EACH challenge ACM gives me, create a DNS record." It's like getting a homework packet with 3 worksheets: you don't write one piece of code per worksheet, you write a loop that handles however many worksheets you get.
> 
> **Evaluator Question:** *Why is `allow_overwrite = true` set on the validation records?*
> 
> **Model Answer:** If you run `terraform apply` multiple times, or if you're replacing an old certificate, the validation record names might already exist. Without `allow_overwrite = true`, Terraform fails with "record already exists." This setting tells Terraform: "If the record exists, update it instead of erroring."

---

### Step 3.4: Add ACM Certificate Validation Resource

**Action:** Add this code block to the END of `bonus_c_route53.tf`:

```hcl
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

**Action:** Save the file.

> [!question] SOCRATIC Q&A: Why Validation?
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

---

### Step 3.5: Add ALIAS Record for App Subdomain

**Action:** Add this code block to the END of `bonus_c_route53.tf`:

```hcl
# ==============================================
# ALIAS RECORD: subdomain → ALB
# ==============================================

# Explanation: This is the holographic sign outside the cantina—
# "www.yourdomain.com" now points to your ALB. 
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

**Action:** Save and close the file.

> [!question] SOCRATIC Q&A: ALIAS vs CNAME
> 
> ***Q:** Why use an ALIAS record instead of a regular CNAME?*
> 
> **A (Explain Like I'm 10):** Regular CNAME records are like sticky notes that say "go ask someone else." If you ask for `www.example.com`, the CNAME says "actually, go ask `xyz.elb.amazonaws.com`"—that's TWO lookups. ALIAS is like a smart sticky note that does the work FOR you. It looks up the ALB's actual IP addresses and gives them directly. Faster! Plus, CNAMEs can't be used at the "zone apex" (`example.com` with no subdomain), but ALIAS can.
> 
> **Evaluator Question:** *What does `evaluate_target_health = true` do?*
> 
> **Model Answer:** Route53 performs health checks on the ALB. If the ALB is unhealthy (no healthy targets, or ALB itself is down), Route53 can stop sending traffic to it. This is critical for multi-region failover architectures: if your primary ALB dies, Route53 can route to a backup.

---

### Step 3.6: Validate the Complete File

**Action:** Verify the file structure is correct:

```bash
# Check the file exists and has content
wc -l bonus_c_route53.tf
```

**Expected Output:** Approximately 80-100 lines.

**Action:** Run Terraform validate:

```bash
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

---

## PART 4: Update HTTPS Listener Dependency

The HTTPS listener needs to wait for certificate validation to complete before it can use the certificate.

### Step 4.1: Locate the HTTPS Listener in `bonus_b.tf`

**Action:** Find the HTTPS listener resource:

```bash
grep -n "aws_lb_listener.*https" bonus_b.tf
```

**Expected Output:** A line number showing where the HTTPS listener is defined.

---

### Step 4.2: Update the HTTPS Listener

**Action:** Open `bonus_b.tf` in your editor:

```bash
code bonus_b.tf
```

**Action:** Find the `aws_lb_listener` resource for HTTPS (port 443) and ensure it has:
1. `certificate_arn` pointing to the certificate (not the validation)
2. `depends_on` pointing to the DNS validation resource

**Action:** Update (or verify) the HTTPS listener looks like this:

```hcl
# ==============================================
# HTTPS LISTENER (Updated for DNS Validation)
# ==============================================

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
  depends_on = [
    aws_acm_certificate_validation.chewbacca_acm_validation01_dns
  ]
}
```

**Action:** Save and close the file.

> [!question] SOCRATIC Q&A: Why depends_on?
> 
> ***Q:** Why do we need `depends_on` here? Doesn't Terraform figure out dependencies automatically?*
> 
> **A (Explain Like I'm 10):** Terraform is smart, but not THAT smart. It sees that the listener uses `aws_acm_certificate.chewbacca_acm_cert01.arn` and waits for the certificate to be CREATED. But "created" isn't the same as "validated and issued!" The certificate exists immediately, but it's in PENDING_VALIDATION status until DNS validation completes. `depends_on` says: "Don't just wait for the certificate to exist—wait for the VALIDATION resource to complete too."
> 
> **Evaluator Question:** *What error would you see if you forgot the `depends_on`?*
> 
> **Model Answer:** You'd likely see: `UnsupportedCertificate: The certificate 'arn:aws:acm:...' must have a fully-qualified domain name, a supported signature, and a supported key size.` This misleading error actually means the certificate isn't validated yet. The listener creation races ahead of validation.

---

## PART 5: Add Outputs

### Step 5.1: Add Route53 Outputs

**Action:** Open `outputs.tf` in your editor:

```bash
code outputs.tf
```

**Action:** Add this code block to the END of the file:

```hcl
# ==============================================
# ROUTE53 + DNS OUTPUTS (Added in Bonus-C)
# ==============================================

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

**Action:** Save and close the file.

> [!question] SOCRATIC Q&A: Why Output Name Servers?
> 
> ***Q:** Why output the name servers? What do I do with them?*
> 
> **A (Explain Like I'm 10):** When AWS creates a hosted zone, it assigns name servers (like `ns-123.awsdns-45.com`). These are the "official phone operators" for your domain. But your domain registrar (where you bought the domain) doesn't know about them yet! You must LOG INTO your registrar (GoDaddy, Namecheap, Route53 Registrar, etc.) and UPDATE the name server records to match AWS's. Until you do this, the internet can't find your DNS records.
> 
> **Evaluator Question:** *What happens if the registrar's name servers don't match Route53's?*
> 
> **Model Answer:** DNS resolution fails. The registrar tells the internet "ask ns-OLD.registrar.com for domain records." That old server doesn't have your Route53 records. Users get NXDOMAIN (domain doesn't exist) or stale data. Always verify: `dig NS yourdomain.com` should return Route53's name servers.

---

## PART 6: Deploy the Infrastructure

### Step 6.1: Format and Validate

**Action:** Format all Terraform files:

```bash
terraform fmt
```

**Action:** Validate the configuration:

```bash
terraform validate
```

**Expected Output:**
```
Success! The configuration is valid.
```

---

### Step 6.2: Review the Plan

**Action:** Generate and review the execution plan:

```bash
terraform plan
```

**What to Look For:**
- `aws_route53_zone.chewbacca_zone01[0]` will be created
- `aws_route53_record.chewbacca_acm_validation_records01` will be created (multiple)
- `aws_acm_certificate_validation.chewbacca_acm_validation01_dns` will be created
- `aws_route53_record.chewbacca_app_alias01` will be created

**Expected:** ~4-6 resources to add.

---

### Step 6.3: Apply the Configuration

**Action:** Apply the changes:

```bash
terraform apply
```

**Action:** Review the plan output and type `yes` when prompted.

**Note:** The `aws_acm_certificate_validation` resource may take 2-5 minutes to complete while ACM verifies the DNS records.

**Expected Output:**
```
Apply complete! Resources: X added, 0 changed, 0 destroyed.

Outputs:

chewbacca_app_url_https = "https://www.yourdomain.com"
chewbacca_route53_name_servers = tolist([
  "ns-xxx.awsdns-xx.com",
  "ns-xxx.awsdns-xx.net",
  "ns-xxx.awsdns-xx.co.uk",
  "ns-xxx.awsdns-xx.org",
])
chewbacca_route53_zone_id = "Z1234567890ABC"
```

> [!warning] TROUBLESHOOTING: terraform apply Hangs on Validation
> 
> **Symptom:** `terraform apply` hangs for more than 10 minutes on `aws_acm_certificate_validation`.
> 
> **Cause:** ACM can't see the DNS validation records. Usually a name server issue.
> 
> **Fix:** 
> 1. Check your domain registrar has the correct Route53 name servers
> 2. Verify DNS propagation: `dig NS yourdomain.com`
> 3. Wait for DNS propagation (can take up to 48 hours for new domains)

---

## PART 7: Verification Commands

### Step 7.1: Get Your Zone ID

**Action:** Export your zone ID for use in subsequent commands:

```bash
# Replace 'yourdomain.com' with your actual domain
export ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name yourdomain.com \
  --query "HostedZones[?Name=='yourdomain.com.'].Id" \
  --output text | sed 's|/hostedzone/||')

echo "Zone ID: $ZONE_ID"
```

**Expected Output:** `Zone ID: Z08529463796GXWJTC93E` (your ID will differ)

---

### Step 7.2: Verify Hosted Zone Exists

**Action:** Run:

```bash
aws route53 list-hosted-zones-by-name \
  --dns-name yourdomain.com \
  --query "HostedZones[?Name=='yourdomain.com.'].Id" \
  --output text
```

**Expected Output:** `/hostedzone/Z08529463796GXWJTC93E`

---

### Step 7.3: Verify ACM Validation Records Exist

**Action:** Run:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='CNAME' && contains(Name, '_')]" \
  --output table
```

**Expected Output:** Table showing CNAME records with names starting with `_` (ACM validation records).

---

### Step 7.4: Verify ALIAS Record Exists

**Action:** Run (replace `www` with your `app_subdomain` value):

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Name=='www.yourdomain.com.']"
```

**Expected Output:**
```json
[
    {
        "Name": "www.yourdomain.com.",
        "Type": "A",
        "AliasTarget": {
            "HostedZoneId": "Z1H1FL5HABSF5",
            "DNSName": "chewbacca-alb01-1234567890.us-west-2.elb.amazonaws.com.",
            "EvaluateTargetHealth": true
        }
    }
]
```

> [!warning] TROUBLESHOOTING: ALIAS Record Shows Different Subdomain
> 
> **Symptom:** You expected `app.yourdomain.com` but see `www.yourdomain.com` (or vice versa).
> 
> **Cause:** Your `app_subdomain` variable is set differently than expected.
> 
> **Diagnosis:**
> ```bash
> # Check what subdomain is configured
> grep -r "app_subdomain" *.tf *.tfvars 2>/dev/null
> 
> # Or check all records in the zone
> aws route53 list-resource-record-sets \
>   --hosted-zone-id $ZONE_ID \
>   --query "ResourceRecordSets[].{Name:Name,Type:Type}" \
>   --output table
> ```
> 
> **Fix:** If the subdomain is correct for your use case, use that subdomain in your verification and curl commands. If you need to change it, update `app_subdomain` in your `variables.tf` or `terraform.tfvars` and run `terraform apply`.

---

### Step 7.5: Verify Certificate Is Issued

**Action:** Run:

```bash
aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='yourdomain.com'].Status" \
  --output text
```

**Expected Output:** `ISSUED`

**If output is `PENDING_VALIDATION`:** Wait 2-5 minutes and re-run. If it persists beyond 10 minutes, check DNS propagation.

---

### Step 7.6: Verify DNS Resolution

**Action:** Run (replace with your actual subdomain):

```bash
dig www.yourdomain.com A +short
```

**Expected Output:** One or more IP addresses (ALB's IPs).

---

### Step 7.7: Test HTTPS End-to-End

**Action:** Run (replace with your actual subdomain):

```bash
curl -I https://www.yourdomain.com/list
```

**Expected Output:**
```
HTTP/2 200
date: Wed, 04 Feb 2026 01:31:17 GMT
content-type: text/html; charset=utf-8
...
```

> [!warning] TROUBLESHOOTING: HTTP 404 Response
> 
> **Symptom:** `curl -I https://www.yourdomain.com` returns `HTTP/2 404`
> 
> **This is NOT an infrastructure failure!** 
> 
> **Cause:** Your Flask application doesn't have a route for `/`. The 404 comes from your app, not from AWS.
> 
> **Evidence:** Look at the response headers:
> ```
> server: Werkzeug/3.1.5 Python/3.9.25
> ```
> This proves traffic reached your Flask app.
> 
> **Fix:** Test an endpoint your app actually has:
> ```bash
> curl -I https://www.yourdomain.com/list
> curl -I https://www.yourdomain.com/init
> ```
> 
> **Or add a root route to your Flask app:**
> ```python
> @app.route('/')
> def home():
>     return "Chewbacca says RRWWWGG! App is running."
> ```

---

### Step 7.8: Verify Certificate Details (Optional)

**Action:** Run:

```bash
echo | openssl s_client -connect www.yourdomain.com:443 -servername www.yourdomain.com 2>/dev/null | openssl x509 -noout -subject -issuer
```

**Expected Output:**
```
subject=CN = yourdomain.com
issuer=C = US, O = Amazon, CN = Amazon RSA 2048 M02
```

---

## PART 8: All-in-One Verification Summary

**Action:** Run this comprehensive verification script (replace `yourdomain.com` and `www` with your values):

```bash
DOMAIN="yourdomain.com"
SUBDOMAIN="www"

echo "=== 1. Zone ID ===" && \
aws route53 list-hosted-zones-by-name --dns-name $DOMAIN --query "HostedZones[0].Id" --output text && \
echo "" && \
echo "=== 2. Certificate Status ===" && \
aws acm list-certificates --query "CertificateSummaryList[?DomainName=='$DOMAIN'].Status" --output text && \
echo "" && \
echo "=== 3. DNS Resolution ===" && \
dig $SUBDOMAIN.$DOMAIN A +short && \
echo "" && \
echo "=== 4. HTTPS Status Code ===" && \
curl -s -o /dev/null -w "%{http_code}" https://$SUBDOMAIN.$DOMAIN/list
```

**Expected Output:**
```
=== 1. Zone ID ===
/hostedzone/Z08529463796GXWJTC93E

=== 2. Certificate Status ===
ISSUED

=== 3. DNS Resolution ===
52.10.123.45
34.210.67.89

=== 4. HTTPS Status Code ===
200
```

---

## 📋 Verification Checklist

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Hosted Zone exists | `aws route53 list-hosted-zones-by-name --dns-name yourdomain.com` | Zone ID returned |
| 2 | ACM validation records | `aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID --query "ResourceRecordSets[?Type=='CNAME']"` | CNAME records with `_` prefix |
| 3 | ALIAS record exists | `aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID --query "ResourceRecordSets[?Name=='www.yourdomain.com.']"` | Type A with AliasTarget |
| 4 | Certificate issued | `aws acm list-certificates --query "CertificateSummaryList[?DomainName=='yourdomain.com'].Status"` | `ISSUED` |
| 5 | DNS resolves | `dig www.yourdomain.com A +short` | IP addresses |
| 6 | HTTPS works | `curl -I https://www.yourdomain.com/list` | `HTTP/2 200` |

---

## 🔧 Common Failure Modes & Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `No declaration found for "var.environment"` | Variable not defined | Add `variable "environment"` to variables.tf |
| `No state file was found!` | Wrong directory | Find correct directory with `find ~ -name "terraform.tfstate"` |
| `Error: No configuration files` | Wrong directory | Navigate to directory containing `.tf` files |
| Certificate stuck in PENDING_VALIDATION | DNS validation records not propagated | Wait 5-30 minutes; verify NS records at registrar |
| `dig` returns NXDOMAIN | Registrar NS records don't match Route53 | Update registrar to use Route53's name servers |
| HTTPS shows certificate error | Accessing via ALB DNS instead of custom domain | Always use `https://www.yourdomain.com` |
| ALIAS record has wrong subdomain | `app_subdomain` variable set differently | Check variable value; update if needed |
| HTTP 404 on curl | Flask app has no route for `/` | Test `/list` or `/init` endpoints instead |
| `terraform apply` hangs on validation | DNS not reachable from AWS | Verify NS records; wait for propagation |

---

## 🎯 What This Lab Proves About You

If you complete Bonus-C, you've demonstrated:

| Skill | Evidence |
|-------|----------|
| **DNS Management** | Created hosted zone, validation records, ALIAS records |
| **Certificate Lifecycle** | Automated DNS validation for TLS certificates |
| **Infrastructure as Code** | Terraform-managed DNS and certificate validation |
| **Production Patterns** | ALIAS records, health checks, auto-renewal setup |
| **Troubleshooting** | Diagnosed and resolved real infrastructure issues |

> [!tip] Interview Statement
> 
> **"I can configure DNS, TLS certificates, and secure ingress using Terraform with automated certificate validation and renewal."**
> 
> This is exactly how production companies ship. You're operating at the level of a mid-level cloud engineer.

---

## 📁 Complete File Reference

### `bonus_c_route53.tf` (Complete)

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
# ALIAS RECORD: subdomain -> ALB
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

### Variables to Add to `variables.tf`

```hcl
# ==============================================
# ROUTE53 CONFIGURATION (Added in Bonus-C)
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

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}
```

### Outputs to Add to `outputs.tf`

```hcl
# ==============================================
# ROUTE53 + DNS OUTPUTS (Added in Bonus-C)
# ==============================================

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

---

## 🔜 What's Next: Bonus-D

**Bonus-D adds:**
- Zone apex ALIAS record (naked domain → ALB)
- ALB access logs to S3
- S3 bucket policy for log delivery

This enables incident response forensics—when something breaks, you'll have the logs to prove what happened.
