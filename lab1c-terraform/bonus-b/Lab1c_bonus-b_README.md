# LAB 1C BONUS-B: ALB + TLS + WAF + Dashboard

## Enhanced Socratic Q&A Guide (Step-by-Step)

---

> [!warning] PREREQUISITE
> Lab 1C with Bonus-A must be completed and verified before starting Bonus-B. You must have:
> - VPC with public and private subnets (`aws_vpc.main`, `aws_subnet.public[0]`, `aws_subnet.private[0]`)
> - VPC Endpoints (SSM, CloudWatch Logs, Secrets Manager, S3)
> - Private EC2 instance (`aws_instance.app`) accessible via Session Manager
> - EC2 Security Group (`aws_security_group.ec2`)
> - RDS MySQL in private subnet
> - SNS Topic for alerts (`aws_sns_topic.alerts`)
> - Working EC2 → RDS connectivity

---

## Lab Overview

Bonus-B transforms your infrastructure into a **production-grade enterprise pattern**:

| Component | What It Adds | Career Value |
|-----------|--------------|--------------|
| Public ALB | Internet-facing load balancer | Traffic distribution |
| Private EC2 Targets | Compute hidden from internet | Security hardening |
| TLS with ACM | HTTPS encryption | Compliance requirement |
| WAF on ALB | Web application firewall | Attack protection |
| CloudWatch Dashboard | Visual monitoring | Operational awareness |
| SNS Alarm (5xx) | Error spike detection | Incident response |

---

## Target Architecture

```
Internet 
    ↓
[Route53: www.yourdomain.com]
    ↓
[WAF] → Blocks SQL injection, XSS, known exploits
    ↓
[ALB: TLS termination, HTTP→HTTPS redirect]
    ↓
[Target Group: Health checks on /health]
    ↓
[Private EC2: Flask app on port 80]
    ↓
[RDS MySQL: Private subnet]
```

---

## Why This Architecture? (Industry Context)

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why put an ALB in front of EC2 when EC2 can already serve HTTP directly?*
> 
> **A (Explain Like I'm 10):** Imagine you're a popular restaurant. If customers come directly to the kitchen (EC2), it's chaos — the chef can't handle everything, there's no waiting area, and if the chef gets sick, everyone goes hungry. An ALB is like a proper front-of-house: it greets customers, manages the queue, can send people to multiple kitchens (load balancing), and if one kitchen closes, customers go to another without knowing.
> 
> **Evaluator Question:** *What are the security and operational benefits of ALB + private EC2 vs public EC2?*
> 
> **Model Answer:** 
> - **Security:** EC2 has no public IP — can't be directly attacked. ALB provides TLS termination — certificates managed in one place. WAF attaches to ALB — single point for web filtering.
> - **Operations:** Health checks route away from unhealthy targets. Blue/green deployments swap target groups. Centralized access logs. Auto-scaling attaches to target groups. DDoS mitigation at the edge, not on compute.

---

## Files You Will Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `variables.tf` | MODIFY | Add domain and certificate variables |
| `bonus_b.tf` | CREATE | ALB, Target Group, Listeners, WAF, Dashboard, Alarm, Route53 |
| `bonus_b_outputs.tf` | CREATE | ALB DNS, WAF ARN, Dashboard URL |
| `outputs.tf` | MODIFY | Remove obsolete outputs that conflict |

---

## PART 1: Prerequisites Check

### Step 1.1: Verify Your Existing Resources

Before starting, confirm your existing Terraform resources are named correctly. Run:

```bash
cd ~/path/to/your/terraform-files
terraform state list | grep -E "(vpc|security_group|subnet|instance|sns)"
```

**Expected output should include:**
```
aws_vpc.main
aws_security_group.ec2
aws_subnet.public[0]
aws_subnet.public[1]
aws_subnet.private[0]
aws_subnet.private[1]
aws_instance.app
aws_sns_topic.alerts
```

> [!warning] CRITICAL: Resource Names
> If your resources have different names (e.g., `aws_vpc.chewbacca_vpc01` instead of `aws_vpc.main`), you must adjust ALL references in the code below to match YOUR resource names.

### Step 1.2: Verify You Have an ACM Certificate

You need an ACM certificate **in the same region as your ALB** (e.g., us-west-2).

**Run this command to list your certificates:**

```bash
aws acm list-certificates --region us-west-2
```

**Expected output:**
```json
{
    "CertificateSummaryList": [
        {
            "CertificateArn": "arn:aws:acm:us-west-2:ACCOUNT_ID:certificate/CERTIFICATE_ID",
            "DomainName": "yourdomain.com"
        }
    ]
}
```

**If you don't have a certificate, create one:**

1. Go to AWS Console → Certificate Manager → Request certificate
2. Request a public certificate
3. Domain name: `yourdomain.com`
4. Add another name: `*.yourdomain.com` (wildcard covers all subdomains)
5. Validation method: DNS validation
6. Complete DNS validation (add CNAME records to Route53)
7. Wait for status to show "Issued"

### Step 1.3: Check What Subdomains Your Certificate Covers

**Run this command (replace with YOUR certificate ARN):**

```bash
aws acm describe-certificate \
  --certificate-arn "arn:aws:acm:us-west-2:YOUR_ACCOUNT:certificate/YOUR_CERT_ID" \
  --region us-west-2 \
  --query "Certificate.SubjectAlternativeNames"
```

**Example output:**
```json
[
    "wheresjack.com",
    "www.wheresjack.com"
]
```

> [!warning] IMPORTANT: Subdomain Matching
> Your `app_subdomain` variable MUST match a domain covered by your certificate.
> - If certificate covers `www.yourdomain.com` → use `app_subdomain = "www"`
> - If certificate covers `*.yourdomain.com` (wildcard) → use any subdomain (`app`, `www`, `api`, etc.)
> - If certificate only covers `yourdomain.com` → you can only use the apex domain (more complex setup)

---

## PART 2: Variables Setup

### Step 2.1: Add Bonus-B Variables to variables.tf

**Action:** Open `variables.tf` in your editor.

**Action:** Add the following block at the END of the file (after all existing variables):

```hcl
# ====================
# Bonus-B Variables
# ====================

variable "domain_name" {
  description = "Root domain name (e.g., wheresjack.com)"
  type        = string
  default     = "yourdomain.com"  # ← CHANGE THIS to your domain
}

variable "app_subdomain" {
  description = "Subdomain for the application (must be covered by your ACM certificate)"
  type        = string
  default     = "www"  # ← CHANGE THIS if your cert covers a different subdomain
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for TLS (must be validated and in same region as ALB)"
  type        = string
  default     = "arn:aws:acm:us-west-2:YOUR_ACCOUNT:certificate/YOUR_CERT_ID"  # ← CHANGE THIS
}

variable "app_port" {
  description = "Port the Flask app listens on"
  type        = number
  default     = 80
}
```

**Action:** Replace the placeholder values:
- `yourdomain.com` → Your actual domain (e.g., `wheresjack.com`)
- `www` → The subdomain your certificate covers (check Step 1.3 output)
- `YOUR_ACCOUNT:certificate/YOUR_CERT_ID` → Your actual certificate ARN from Step 1.2

**Action:** Save the file.

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why do we use variables instead of hardcoding the domain name directly in the resources?*
> 
> **A (Explain Like I'm 10):** Imagine you're writing a recipe that you want to share with friends. If you write "use ALEX'S OVEN at 350°F," only Alex can use it! But if you write "use YOUR OVEN at 350°F," anyone can follow the recipe with their own oven. Variables are like "YOUR OVEN" — they let the same Terraform code work for different domains, different environments (dev/staging/prod), and different team members.
> 
> **Evaluator Question:** *How do variables support the DRY (Don't Repeat Yourself) principle in Terraform?*
> 
> **Model Answer:** Variables centralize values that might change or be reused. If `domain_name` appears in 10 resources, changing the variable once updates all 10. Without variables, you'd search-and-replace across files — error-prone and time-consuming. Variables also enable environment-specific `.tfvars` files (dev.tfvars, prod.tfvars) that deploy the same infrastructure to different domains.

### Step 2.2: Validate Variables Syntax

**Action:** Run:

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

**If you see errors about duplicate variables:**
- Check for duplicate `variable "domain_name"` blocks
- Remove any duplicates, keeping only ONE declaration per variable

---

## PART 3: Create the ALB Infrastructure (bonus_b.tf)

### Step 3.1: Create the bonus_b.tf File

**Action:** Create a new file named `bonus_b.tf` in your terraform-files directory.

**Action:** Add the following content to `bonus_b.tf`:

```hcl
# ====================
# Bonus-B: ALB + TLS + WAF + Dashboard
# ====================

# --- ALB Security Group ---
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg01"
  description = "Security group for ALB - allows HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  # HTTPS from anywhere (internet-facing)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP from anywhere (for redirect to HTTPS)
  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound to EC2 targets
  egress {
    description     = "To EC2 targets on app port"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg01"
  })
}
```

**Save the file** (but don't run terraform yet - we'll add more).

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why does the ALB security group allow 0.0.0.0/0 (the entire internet) but the EC2 security group doesn't?*
> 
> **A (Explain Like I'm 10):** Think of a hotel. The front door (ALB) is open to EVERYONE — guests, delivery people, visitors. But the guest rooms (EC2) are locked and only accessible if you have a key from the front desk. The ALB is designed to face the internet (that's its job!). The EC2 is protected BEHIND the ALB and only accepts traffic FROM the ALB — like rooms only accepting people who came through the lobby.
> 
> **Evaluator Question:** *What's the principle of "defense in depth" and how does this architecture implement it?*
> 
> **Model Answer:** Defense in depth means multiple independent security layers, so compromising one doesn't expose everything. Here: (1) WAF filters malicious requests before they reach ALB, (2) ALB security group limits ports to 80/443, (3) EC2 security group only accepts traffic from ALB's security group, (4) EC2 has no public IP — can't be directly addressed, (5) RDS only accepts traffic from EC2's security group. An attacker must bypass ALL layers, not just one.

### Step 3.2: Add the EC2 Security Group Rule

**Action:** Add this block to `bonus_b.tf` (after the ALB security group):

```hcl
# --- Allow EC2 to receive traffic from ALB ---
resource "aws_security_group_rule" "ec2_from_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2.id
  source_security_group_id = aws_security_group.alb.id
  description              = "Allow traffic from ALB"
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why do we use `aws_security_group_rule` as a separate resource instead of adding an inline `ingress` block to the EC2 security group?*
> 
> **A (Explain Like I'm 10):** Imagine you have a house with locks on every door. If you want to give your friend a key, you have two choices: (1) Rebuild the entire door with a new lock that accepts both keys, or (2) Just add their key to the existing lock. The separate `aws_security_group_rule` is like adding a key — you don't have to touch the original security group resource. This prevents Terraform from wanting to recreate the EC2 security group (which would be disruptive).
> 
> **Evaluator Question:** *What happens if you define the same rule both inline and as a separate resource?*
> 
> **Model Answer:** Terraform will detect a conflict and may produce errors or unpredictable behavior. AWS security group rules are identified by their attributes (protocol, port, source). If the same rule exists both inline and as a separate resource, Terraform can't determine which one "owns" it. Best practice: use EITHER inline rules OR separate rule resources, not both for the same security group.

### Step 3.3: Add the Application Load Balancer

**Action:** Add this block to `bonus_b.tf`:

```hcl
# --- Application Load Balancer ---
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb01"
  internal           = false # Internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  # ALB goes in PUBLIC subnets (needs internet access)
  subnets = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]

  enable_deletion_protection = false # Set true in production

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb01"
  })
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why does the ALB go in PUBLIC subnets when the EC2 instances are in PRIVATE subnets?*
> 
> **A (Explain Like I'm 10):** Think of a post office. The mailboxes (ALB) are on the street where anyone can drop off mail — that's the PUBLIC subnet. But the sorting room and mail carriers (EC2) are inside the building where only employees can go — that's the PRIVATE subnet. The ALB needs to be publicly accessible so internet users can reach it, but it forwards traffic to EC2 instances that are safely hidden inside.
> 
> **Evaluator Question:** *What happens if you try to create an internet-facing ALB in private subnets?*
> 
> **Model Answer:** The ALB creation will fail or the ALB won't be reachable. Internet-facing ALBs need subnets with: (1) An Internet Gateway attached to the VPC, (2) A route table with a 0.0.0.0/0 route to the IGW. Private subnets route through NAT Gateway instead, which allows outbound connections but blocks inbound from the internet. AWS validates this during ALB creation.

### Step 3.4: Add the Target Group

**Action:** Add this block to `bonus_b.tf`:

```hcl
# --- Target Group ---
resource "aws_lb_target_group" "main" {
  name        = "${local.name_prefix}-tg01"
  port        = var.app_port
  protocol    = "HTTP" # ALB → EC2 is HTTP (TLS terminates at ALB)
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tg01"
  })
}

# --- Register EC2 with Target Group ---
resource "aws_lb_target_group_attachment" "main" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why is the target group protocol HTTP when we're using HTTPS for the website?*
> 
> **A (Explain Like I'm 10):** Imagine a secure envelope delivery service. The customer seals their letter in a special envelope (HTTPS). The delivery truck (ALB) carries it safely across the city. But once inside the building (VPC), the mail room (ALB) opens the special envelope and puts the letter in a regular envelope (HTTP) for internal delivery to the office (EC2). Why? Because inside the building is already secure — adding another locked envelope just wastes time. This is called "TLS termination" — the ALB handles encryption, so EC2 doesn't have to.
> 
> **Evaluator Question:** *When would you want end-to-end encryption (HTTPS from ALB to EC2)?*
> 
> **Model Answer:** When compliance requires data encrypted at ALL times, even inside the VPC. Examples: PCI-DSS for credit card data, HIPAA for healthcare data in some interpretations. Also useful in shared/multi-tenant VPCs where you don't fully trust the network. The tradeoff: more complexity (certificates on EC2), more CPU usage, slightly higher latency. Most production environments use TLS termination at ALB because the VPC is a trusted network boundary.

### Step 3.5: Add the HTTPS Listener

**Action:** Add this block to `bonus_b.tf`:

```hcl
# --- HTTPS Listener (443) ---
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-https-listener01"
  })
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** What is `ssl_policy` and why does the policy name have "TLS13-1-2" in it?*
> 
> **A (Explain Like I'm 10):** Imagine you and your friend have a secret code for passing notes. Over the years, you've made better codes: Version 1.0 was easy to crack, Version 1.1 was better but still had problems, Version 1.2 is pretty good, and Version 1.3 is the newest and strongest. `TLS13-1-2` means "speak the newest code (TLS 1.3) or the pretty-good code (TLS 1.2), but refuse to use the old crackable codes (TLS 1.0, 1.1)." The SSL policy tells the ALB which encryption versions to accept.
> 
> **Evaluator Question:** *What vulnerabilities exist in TLS 1.0 and 1.1 that justify disabling them?*
> 
> **Model Answer:** TLS 1.0/1.1 are vulnerable to attacks like BEAST, POODLE, and CRIME that can decrypt traffic. PCI-DSS explicitly prohibits TLS 1.0 for payment card data. Major browsers have deprecated TLS 1.0/1.1 since 2020. Using the `ELBSecurityPolicy-TLS13-1-2-2021-06` policy: enforces TLS 1.2 minimum, enables TLS 1.3 for modern clients, disables weak cipher suites. This balances security with compatibility for most clients.

### Step 3.6: Add the HTTP Listener (Redirect)

**Action:** Add this block to `bonus_b.tf`:

```hcl
# --- HTTP Listener (80) - Redirect to HTTPS ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301" # Permanent redirect
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-http-listener01"
  })
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why use HTTP_301 (permanent redirect) instead of HTTP_302 (temporary redirect)?*
> 
> **A (Explain Like I'm 10):** Imagine you move to a new house. A 301 is like telling the post office "I moved FOREVER, update all your records." A 302 is like saying "I'm visiting somewhere else temporarily, but I might come back." With 301, browsers REMEMBER and go directly to HTTPS next time without asking the server again. With 302, browsers ask every single time. Since we ALWAYS want HTTPS (not temporary), 301 is correct — it's faster for users and reduces server load.
> 
> **Evaluator Question:** *What is HSTS and how does it relate to this redirect?*
> 
> **Model Answer:** HSTS (HTTP Strict Transport Security) is a header that tells browsers "ONLY use HTTPS for this domain, period." It's stronger than a 301 redirect because: (1) Prevents the initial HTTP request entirely on subsequent visits, (2) Protects against SSL stripping attacks where an attacker intercepts the HTTP→HTTPS redirect. To implement HSTS, add this header to your application responses: `Strict-Transport-Security: max-age=31536000; includeSubDomains`. The 301 redirect handles first-time visitors; HSTS protects returning visitors.

### Step 3.7: Save and Validate

**Action:** Save `bonus_b.tf`.

**Action:** Run:

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

---

## PART 4: Add WAF (Web Application Firewall)

### Step 4.1: Add WAF Web ACL

**Action:** Add this block to `bonus_b.tf` (after the listeners):

```hcl
# ====================
# WAF Web ACL
# ====================

resource "aws_wafv2_web_acl" "main" {
  name        = "${local.name_prefix}-waf01"
  description = "WAF for ALB - blocks common attacks"
  scope       = "REGIONAL" # REGIONAL for ALB, CLOUDFRONT for CloudFront

  default_action {
    allow {} # Allow by default, block specific threats
  }

  # Rule 1: AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {} # Use rule group's actions as-is
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules - SQL Injection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-waf-badinputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf01"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-waf01"
  })
}

# --- Associate WAF with ALB ---
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Security groups already filter traffic. Why do we need WAF too?*
> 
> **A (Explain Like I'm 10):** Security groups are like a bouncer checking IDs at the door — they only look at WHERE you're coming from (IP address) and WHICH door you're using (port). But they don't check what you're CARRYING. WAF is like an X-ray machine that scans your bags for weapons. A hacker might come from a normal IP address through the normal door (passes security group), but their request contains `'; DROP TABLE users; --` (SQL injection attack). The security group says "looks fine!" but WAF says "THAT'S A WEAPON!" and blocks it.
> 
> **Evaluator Question:** *What's the difference between `scope = "REGIONAL"` and `scope = "CLOUDFRONT"`?*
> 
> **Model Answer:** `REGIONAL` scope creates a WAF that can attach to regional resources: ALB, API Gateway, AppSync in any AWS region. The WAF exists in the same region as the resource. `CLOUDFRONT` scope creates a WAF specifically for CloudFront distributions and MUST be created in us-east-1 (even if your origin is elsewhere). In Lab 2, when we move WAF to CloudFront for origin cloaking, we'll need to create a new WAF with `scope = "CLOUDFRONT"` in us-east-1.

### Step 4.2: Save and Validate

**Action:** Save `bonus_b.tf`.

**Action:** Run:

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

---

## PART 5: Add CloudWatch Dashboard

### Step 5.1: Add the Dashboard Resource

**Action:** Add this block to `bonus_b.tf`:

```hcl
# ====================
# CloudWatch Dashboard
# ====================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard01"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Request Count
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      # Row 1: 5xx Errors
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB 5xx Errors (Server Errors)"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      # Row 2: Target Health
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Healthy vs Unhealthy Targets"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.main.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Average"
        }
      },
      # Row 2: WAF Allowed vs Blocked
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "WAF Allowed vs Blocked"
          region = var.aws_region
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", "${local.name_prefix}-waf01", "Rule", "ALL"],
            ["AWS/WAFV2", "BlockedRequests", "WebACL", "${local.name_prefix}-waf01", "Rule", "ALL"]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      # Row 3: Response Time (full width)
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title  = "Target Response Time (seconds)"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Average"
        }
      }
    ]
  })
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** What's the difference between `HTTPCode_ELB_5XX_Count` and `HTTPCode_Target_5XX_Count`?*
> 
> **A (Explain Like I'm 10):** Imagine a restaurant with a host (ALB) and a chef (EC2). `ELB_5XX` means the HOST had a problem — maybe they couldn't find any available tables (all targets unhealthy) or the restaurant is closed (ALB misconfigured). `Target_5XX` means the CHEF had a problem — the food order failed (app crashed), the recipe was wrong (code bug), or the kitchen ran out of ingredients (database connection failed). Tracking both tells you WHERE to look when something breaks.
> 
> **Evaluator Question:** *Why do we use `arn_suffix` instead of the full `arn` for CloudWatch dimensions?*
> 
> **Model Answer:** CloudWatch metric dimensions for ALB expect a specific format — just the suffix portion of the ARN after `loadbalancer/`. The full ARN is `arn:aws:elasticloadbalancing:region:account:loadbalancer/app/name/id`, but CloudWatch only wants `app/name/id`. Terraform's `aws_lb.main.arn_suffix` attribute provides exactly this, avoiding manual string manipulation.

---

## PART 6: Add CloudWatch Alarm

### Step 6.1: Add the 5xx Error Alarm

**Action:** Add this block to `bonus_b.tf`:

```hcl
# ====================
# ALB 5xx Error Alarm
# ====================

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx-alarm01"
  alarm_description   = "Triggers when ALB target 5xx errors exceed threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10 # Alert if > 10 5xx errors in 2 consecutive minutes
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-5xx-alarm01"
  })
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why `evaluation_periods = 2` instead of alerting on the first error?*
> 
> **A (Explain Like I'm 10):** Imagine your smoke detector at home. Would you want it to scream every time you make toast and a tiny bit of smoke comes out? No! You'd go crazy. You want it to alert when there's REAL smoke for more than a few seconds. `evaluation_periods = 2` means "only alert if there are problems for 2 minutes in a row." One random error is toast smoke; sustained errors are a real fire.
> 
> **Evaluator Question:** *What does `treat_missing_data = "notBreaching"` mean and why is it important?*
> 
> **Model Answer:** When there's no metric data (e.g., no traffic to the ALB), CloudWatch must decide how to treat the alarm. Options: `missing` (keep current state), `breaching` (treat as alarm), `notBreaching` (treat as OK), `ignore` (don't evaluate). We use `notBreaching` because NO DATA usually means NO TRAFFIC, which means NO ERRORS. If we used `breaching`, you'd get alerts at 3 AM when nobody's using the site. The alarm should only fire when there IS traffic AND there ARE errors.

---

## PART 7: Add Route53 DNS Record

### Step 7.1: Add the Route53 Configuration

**Action:** Add this block to `bonus_b.tf`:

```hcl
# ====================
# Route53 DNS
# ====================

# Reference your existing hosted zone (don't create a new one)
data "aws_route53_zone" "main" {
  name = var.domain_name
}

# Point subdomain to ALB
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}" # e.g., www.wheresjack.com
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why use a `data` source for the hosted zone instead of a `resource`?*
> 
> **A (Explain Like I'm 10):** Imagine you're visiting a friend's house. You don't BUILD a new house (resource) — you FIND their existing house (data source) using their address. Your Route53 hosted zone already exists (you created it when you registered the domain or set up DNS). A `data` source looks up existing things; a `resource` creates new things. If you used `resource`, Terraform would try to create a SECOND hosted zone, which would conflict with your existing one.
> 
> **Evaluator Question:** *What's the difference between an ALIAS record and a CNAME record for pointing to an ALB?*
> 
> **Model Answer:** Both point a domain to another name, but ALIAS has advantages: (1) Works at the zone apex (e.g., `example.com` not just `www.example.com`), (2) Free for AWS resources (CNAME queries cost money), (3) Returns the IP directly (faster, one less DNS lookup), (4) Can integrate with Route53 health checks via `evaluate_target_health`. ALIAS is AWS-specific; CNAME is standard DNS. For AWS resources, always prefer ALIAS.

---

## PART 8: Create Outputs File

### Step 8.1: Create bonus_b_outputs.tf

**Action:** Create a new file named `bonus_b_outputs.tf`.

**Action:** Add this content:

```hcl
# ====================
# Bonus-B Outputs
# ====================

output "alb_dns_name" {
  description = "ALB DNS name (use for testing before DNS propagates)"
  value       = aws_lb.main.dns_name
}

output "app_url" {
  description = "Application URL (HTTPS via your domain)"
  value       = "https://${var.app_subdomain}.${var.domain_name}"
}

output "app_url_direct_alb" {
  description = "Direct ALB URL (cert won't match - use -k flag with curl)"
  value       = "https://${aws_lb.main.dns_name}"
}

output "waf_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.main.arn
}

output "dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${local.name_prefix}-dashboard01"
}

output "target_group_arn" {
  description = "Target Group ARN (for health check verification)"
  value       = aws_lb_target_group.main.arn
}

output "hosted_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = data.aws_route53_zone.main.zone_id
}
```

**Action:** Save the file.

---

## PART 9: Fix Conflicting Outputs (Important!)

### Step 9.1: Check for Duplicate Outputs

If your existing `outputs.tf` file has an `app_url` output that references EC2 public IP, it will conflict with the new Bonus-B output.

**Action:** Open `outputs.tf` and look for this block:

```hcl
output "app_url" {
  description = "URL to access the application"
  value       = "http://${aws_instance.app.public_ip}"
}
```

**Action:** If found, DELETE this entire block (it's obsolete now — EC2 has no public IP).

**Also delete these if present (they reference the old public EC2):**

```hcl
output "ec2_public_ip" { ... }
output "ec2_public_dns" { ... }
output "init_url" { ... }
output "list_url" { ... }
```

**Action:** Save `outputs.tf`.

---

## PART 10: Deploy and Verify

### Step 10.1: Validate Configuration

**Action:** Run:

```bash
terraform validate
```

**Expected output:**
```
Success! The configuration is valid.
```

### Step 10.2: Preview Changes

**Action:** Run:

```bash
terraform plan
```

**Expected output:** Should show approximately 10-12 resources to add:
- `aws_security_group.alb`
- `aws_security_group_rule.ec2_from_alb`
- `aws_lb.main`
- `aws_lb_target_group.main`
- `aws_lb_target_group_attachment.main`
- `aws_lb_listener.https`
- `aws_lb_listener.http`
- `aws_wafv2_web_acl.main`
- `aws_wafv2_web_acl_association.main`
- `aws_cloudwatch_dashboard.main`
- `aws_cloudwatch_metric_alarm.alb_5xx`
- `aws_route53_record.app`

### Step 10.3: Apply Changes

**Action:** Run:

```bash
terraform apply
```

**Action:** Type `yes` when prompted.

**Expected output:**
```
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name = "chewbacca-alb01-1234567890.us-west-2.elb.amazonaws.com"
app_url = "https://www.yourdomain.com"
...
```

---

## PART 11: Verification Tests

### Step 11.1: Check Target Health (Critical First Test)

**Action:** Wait 30-60 seconds for health checks, then run:

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-west-2 \
  --query "TargetHealthDescriptions[].TargetHealth.State"
```

**Expected output:**
```
["healthy"]
```

**If you see `"unhealthy"` or `"initial"`:**
- Wait another 30 seconds and try again
- Check that your Flask app has a `/health` endpoint returning 200
- Verify EC2 security group allows traffic from ALB security group

### Step 11.2: Test HTTPS via Your Domain

**Action:** Run:

```bash
curl -I https://www.yourdomain.com
```

**Expected output:**
```
HTTP/2 200
date: ...
content-type: text/html; charset=utf-8
server: Werkzeug/...
```

> [!note] 404 is OK for Root Path
> If you see `HTTP/2 404`, that's actually fine — it means TLS is working but your Flask app doesn't have a `/` route. Test `/health` instead:
> ```bash
> curl https://www.yourdomain.com/health
> ```
> Expected: `OK`

### Step 11.3: Test HTTP→HTTPS Redirect

**Action:** Run:

```bash
curl -I http://www.yourdomain.com
```

**Expected output:**
```
HTTP/1.1 301 Moved Permanently
Location: https://www.yourdomain.com:443/
```

### Step 11.4: Verify WAF is Attached

**Action:** Run (replace with your ALB ARN from terraform output):

```bash
aws wafv2 get-web-acl-for-resource \
  --resource-arn "arn:aws:elasticloadbalancing:us-west-2:YOUR_ACCOUNT:loadbalancer/app/chewbacca-alb01/YOUR_ALB_ID" \
  --region us-west-2 \
  --query "WebACL.Name"
```

**Expected output:**
```
"chewbacca-waf01"
```

### Step 11.5: Verify Alarm Exists

**Action:** Run:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix chewbacca-alb-5xx \
  --region us-west-2 \
  --query "MetricAlarms[].AlarmName"
```

**Expected output:**
```
["chewbacca-alb-5xx-alarm01"]
```

### Step 11.6: Verify Dashboard Exists

**Action:** Run:

```bash
aws cloudwatch list-dashboards \
  --region us-west-2 \
  --query "DashboardEntries[?DashboardName=='chewbacca-dashboard01'].DashboardName"
```

**Expected output:**
```
["chewbacca-dashboard01"]
```

### Step 11.7: Test App Functionality

**Action:** Run:

```bash
# Health check
curl https://www.yourdomain.com/health

# List notes (from Lab 1C)
curl https://www.yourdomain.com/list
```

---

## Complete Verification Checklist

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | ALB active | `aws elbv2 describe-load-balancers --names chewbacca-alb01 --query "LoadBalancers[0].State.Code"` | `"active"` |
| 2 | Listeners exist | `aws elbv2 describe-listeners --load-balancer-arn <ALB_ARN> --query "Listeners[].Port"` | `[443, 80]` |
| 3 | Target healthy | `aws elbv2 describe-target-health --target-group-arn <TG_ARN> --query "TargetHealthDescriptions[].TargetHealth.State"` | `["healthy"]` |
| 4 | WAF attached | `aws wafv2 get-web-acl-for-resource --resource-arn <ALB_ARN> --query "WebACL.Name"` | `"chewbacca-waf01"` |
| 5 | Alarm exists | `aws cloudwatch describe-alarms --alarm-name-prefix chewbacca-alb-5xx --query "MetricAlarms[].AlarmName"` | `["chewbacca-alb-5xx-alarm01"]` |
| 6 | Dashboard exists | `aws cloudwatch list-dashboards --query "DashboardEntries[?DashboardName=='chewbacca-dashboard01'].DashboardName"` | `["chewbacca-dashboard01"]` |
| 7 | HTTPS works | `curl -I https://www.yourdomain.com` | `HTTP/2 200` or `HTTP/2 404` |
| 8 | HTTP redirects | `curl -I http://www.yourdomain.com` | `HTTP/1.1 301` |
| 9 | Health endpoint | `curl https://www.yourdomain.com/health` | `OK` |
| 10 | App works | `curl https://www.yourdomain.com/list` | Notes from database |

---

## Common Errors and Fixes

### Error: "Duplicate output definition"

**Cause:** Both `outputs.tf` and `bonus_b_outputs.tf` define `app_url`.

**Fix:** Delete the `app_url` output from `outputs.tf` (the old one referencing EC2 public IP).

### Error: "Reference to undeclared resource aws_vpc.chewbacca_vpc01"

**Cause:** Your VPC resource is named differently (probably `aws_vpc.main`).

**Fix:** Update all `aws_vpc.chewbacca_vpc01` references to `aws_vpc.main` (or whatever your VPC is named).

### Error: "SSL: no alternative certificate subject name matches"

**Cause:** Your ACM certificate doesn't cover the subdomain you're using.

**Fix:** 
1. Run `aws acm describe-certificate --certificate-arn YOUR_ARN --query "Certificate.SubjectAlternativeNames"`
2. Change `app_subdomain` in `variables.tf` to match a covered domain
3. Or request a new certificate with `*.yourdomain.com` (wildcard)

### Error: Target health shows "unhealthy"

**Cause:** Health check failing — app not responding on `/health`.

**Fix:**
1. Verify Flask app has `/health` route returning 200
2. Check EC2 security group allows traffic from ALB security group
3. SSH via Session Manager and test: `curl http://localhost/health`

### Error: curl returns "Connection refused"

**Cause:** DNS not propagated yet.

**Fix:** Wait 1-2 minutes, then retry. Or test directly via ALB DNS:
```bash
curl -Ik https://YOUR-ALB-DNS.us-west-2.elb.amazonaws.com
```
(The `-k` flag ignores certificate mismatch)

---

## What This Lab Proves About You

*If you complete this lab, you've demonstrated:*

- **Production ingress patterns** — ALB + TLS + WAF
- **Defense in depth** — Multiple security layers working together
- **Operational maturity** — Dashboards, alarms, health checks
- **Infrastructure as Code** — Entire stack reproducible via Terraform
- **Enterprise architecture** — This is how real companies ship

**Interview Statement:**

*"I can build, secure, and operate production-grade web infrastructure with TLS termination, WAF protection against OWASP Top 10 threats, and full observability using CloudWatch dashboards and alarms — all managed as Infrastructure as Code with Terraform."*

---

## What's Next

| Next Step | What You'll Learn |
|-----------|-------------------|
| **Bonus C** | Route53 + ACM DNS validation for apex domain |
| **Bonus D** | ALB access logs to S3 |
| **Lab 2** | CloudFront CDN + Origin Cloaking (WAF moves to edge) |

---

## Quick Reference: Files Created

| File | Resources |
|------|-----------|
| `variables.tf` | Added: `domain_name`, `app_subdomain`, `acm_certificate_arn`, `app_port` |
| `bonus_b.tf` | ALB, SG, Target Group, Listeners, WAF, Dashboard, Alarm, Route53 |
| `bonus_b_outputs.tf` | ALB DNS, app URL, WAF ARN, dashboard URL |
| `outputs.tf` | Removed: obsolete EC2 public IP outputs |
