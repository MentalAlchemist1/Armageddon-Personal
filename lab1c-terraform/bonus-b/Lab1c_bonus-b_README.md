
# LAB 1C BONUS-B: ALB + TLS + WAF + Dashboard

*Enhanced Socratic Q&A Guide*

---

> [!warning] PREREQUISITE
> Lab 1C with Bonus-A must be completed and verified before starting Bonus-B. You must have:
> - VPC with public and private subnets
> - VPC Endpoints (SSM, CloudWatch Logs, Secrets Manager, S3)
> - Private EC2 instance (no public IP) accessible via Session Manager
> - RDS MySQL in private subnet
> - SNS Topic for alerts
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

**This is exactly how modern companies ship: IaC + private compute + managed ingress + TLS + WAF + monitoring + paging.**

*If you can Terraform this, you're no longer "a student who clicked around" — you're a junior cloud engineer.*

---

## Target Architecture - In Progress

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

## Terraform File Structure for Bonus-B

| File | Purpose |
|------|---------|
| `variables.tf` | Add domain and certificate variables |
| `bonus_b.tf` | ALB, Target Group, Listeners, WAF, Dashboard, Alarm |
| `bonus_b_outputs.tf` | ALB DNS, WAF ARN, Dashboard URL |
| `route53.tf` (optional) | DNS records if using Route53 |

---

## PART 1: Variables Setup

### Step 1.1: Add Bonus-B Variables

**Action:** Append these to your existing `variables.tf`:

```hcl
# ====================
# Bonus-B Variables
# ====================

variable "domain_name" {
  description = "Root domain name (e.g., chewbacca-growl.com)"
  type        = string
  default     = "chewbacca-growl.com"
}

variable "app_subdomain" {
  description = "Subdomain for the application (e.g., app)"
  type        = string
  default     = "app"
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for TLS (must be validated)"
  type        = string
  # You'll get this after creating the certificate
}

variable "app_port" {
  description = "Port the Flask app listens on"
  type        = number
  default     = 80
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why do we use variables instead of hardcoding the domain name directly in the resources?*
> 
> **A (Explain Like I'm 10):** Imagine you're writing a recipe that you want to share with friends. If you write "use ALEX'S OVEN at 350°F," only Alex can use it! But if you write "use YOUR OVEN at 350°F," anyone can follow the recipe with their own oven. Variables are like "YOUR OVEN" — they let the same Terraform code work for different domains, different environments (dev/staging/prod), and different team members.
> 
> **Evaluator Question:** *How do variables support the DRY (Don't Repeat Yourself) principle in Terraform?*
> 
> **Model Answer:** Variables centralize values that might change or be reused. If `domain_name` appears in 10 resources, changing the variable once updates all 10. Without variables, you'd search-and-replace across files — error-prone and time-consuming. Variables also enable environment-specific `.tfvars` files (dev.tfvars, prod.tfvars) that deploy the same infrastructure to different domains.

---

## PART 2: TLS Certificate (ACM)

### Step 2.1: Understanding TLS and ACM

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why do we need TLS (HTTPS)? HTTP works fine for testing.*
> 
> **A (Explain Like I'm 10):** Imagine sending a postcard vs. a sealed letter. A postcard (HTTP) can be read by anyone who handles it — the mail carrier, the sorting facility, nosy neighbors. A sealed letter (HTTPS/TLS) is locked in an envelope that only you and the recipient can open. When you type your password on a website, do you want everyone in the coffee shop WiFi to see it? TLS keeps your secrets secret.
> 
> **Evaluator Question:** *What compliance requirements mandate TLS for web applications?*
> 
> **Model Answer:** Nearly all modern compliance frameworks require encryption in transit: PCI-DSS (credit cards), HIPAA (healthcare), SOC 2 (security), GDPR (EU privacy). Even without compliance, browsers mark HTTP sites as "Not Secure," destroying user trust. Google ranks HTTPS sites higher in search results. TLS is table stakes for any production application.

### Step 2.2: Request ACM Certificate

> [!warning] IMPORTANT
> ACM certificates for ALB must be in the **same region** as your ALB. (This is different from CloudFront, which requires us-east-1.)

**Option A: Console (Quick Start)**
1. AWS Console → Certificate Manager → Request certificate
2. Request a public certificate
3. Domain name: `chewbacca-growl.com`
4. Add another name: `*.chewbacca-growl.com` (wildcard for subdomains)
5. Validation method: **DNS validation** (recommended)
6. Copy the certificate ARN for your `variables.tf`

**Option B: Terraform (Full IaC)**

```hcl
# ====================
# ACM Certificate
# ====================

resource "aws_acm_certificate" "chewbacca_cert01" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-cert01"
  }
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** What's the difference between DNS validation and Email validation for ACM certificates?*
> 
> **A (Explain Like I'm 10):** Imagine proving you own a house. **Email validation** is like the bank calling a phone number they found online for that address — if you answer, they believe you. **DNS validation** is like the bank sending an inspector to check if you can actually unlock the front door and change the locks. DNS validation proves you CONTROL the domain's settings, which is stronger proof than just receiving emails.
> 
> **Evaluator Question:** *Why is DNS validation preferred for Terraform/IaC workflows?*
> 
> **Model Answer:** DNS validation can be fully automated in Terraform — you create the validation records, and ACM automatically validates when they propagate. Email validation requires manual human action (clicking a link), which breaks the IaC automation promise. DNS validation also supports automatic certificate renewal without human intervention, critical for production systems.

### Step 2.3: DNS Validation with Route53

If you're using Route53 for DNS, add this to complete automated validation:

```hcl
# ====================
# Route53 Hosted Zone (if not exists)
# ====================

resource "aws_route53_zone" "chewbacca_zone01" {
  name = var.domain_name

  tags = {
    Name = "${local.name_prefix}-zone01"
  }
}

# ====================
# ACM DNS Validation Records
# ====================

resource "aws_route53_record" "chewbacca_cert_validation01" {
  for_each = {
    for dvo in aws_acm_certificate.chewbacca_cert01.domain_validation_options : dvo.domain_name => {
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
  zone_id         = aws_route53_zone.chewbacca_zone01.zone_id
}

# ====================
# Wait for Certificate Validation
# ====================

resource "aws_acm_certificate_validation" "chewbacca_cert_validation01" {
  certificate_arn         = aws_acm_certificate.chewbacca_cert01.arn
  validation_record_fqdns = [for record in aws_route53_record.chewbacca_cert_validation01 : record.fqdn]
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** What does `for_each` do in the validation records resource? Why not just create one record?*
> 
> **A (Explain Like I'm 10):** Remember we asked for both `chewbacca-growl.com` AND `*.chewbacca-growl.com`? AWS needs to verify BOTH. `for_each` is like a copy machine — it looks at the certificate's validation requirements and automatically creates one DNS record for EACH domain that needs proving. If you add more domains later, the same code handles them without changes.
> 
> **Evaluator Question:** *What happens if `aws_acm_certificate_validation` times out?*
> 
> **Model Answer:** The validation resource polls until the certificate status becomes `ISSUED`. Timeout typically means DNS records aren't propagating correctly. Debug steps: (1) Verify Route53 records exist with `aws route53 list-resource-record-sets`, (2) Test DNS propagation with `dig <record_name> CNAME`, (3) Check if using the correct hosted zone. If DNS is managed outside Route53, validation records must be created manually in that provider.

### Step 2.4: Configure Certificate ARN in Variables

> [!warning] REQUIRED FOR CONSOLE/PRE-EXISTING CERTIFICATES
> 
> If you created your certificate via the console OR already have an issued certificate:
> 
> 1. **Go to ACM Console** → Click on your certificate
> 2. **Copy the ARN** (looks like `arn:aws:acm:us-west-2:123456789012:certificate/xxxxx`)
> 3. **Update `variables.tf`:**
>    ```hcl
>    variable "acm_certificate_arn" {
>      description = "ARN of ACM certificate for TLS"
>      type        = string
>      default     = "arn:aws:acm:us-west-2:YOUR_ACCOUNT:certificate/YOUR-CERT-ID"
>    }
>    ```
>
> If you used **Option B (Full Terraform)**, skip this — the ARN is referenced automatically via `aws_acm_certificate_validation.chewbacca_cert_validation01.certificate_arn`.

---

## PART 3: Application Load Balancer (ALB)

### Step 3.1: Create ALB Security Group

**Action:** Add to `bonus_b.tf`:

```hcl
# ====================
# ALB Security Group
# ====================

resource "aws_security_group" "chewbacca_alb_sg01" {
  name        = "${local.name_prefix}-alb-sg01"
  description = "Security group for ALB - allows HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.chewbacca_vpc01.id

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

  # Outbound to targets
  egress {
    description     = "To EC2 targets"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.chewbacca_ec2_sg01.id]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg01"
  }
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why does the ALB security group allow 0.0.0.0/0 when we said that's dangerous for SSH?*
> 
> **A (Explain Like I'm 10):** Remember, 0.0.0.0/0 means "anyone in the world." For SSH (your server's control panel), that's terrifying — like leaving your house keys under the welcome mat. But for HTTP/HTTPS (your website), that's the POINT! You WANT anyone in the world to visit your website. The ALB is like your store's front door — it should be open to customers. SSH is like the store's back office — only employees allowed.
> 
> **Evaluator Question:** *Why do we allow HTTP (port 80) if we want HTTPS-only traffic?*
> 
> **Model Answer:** We allow HTTP to implement a redirect. Users who type `http://` should be automatically redirected to `https://` rather than seeing a connection error. The ALB listener rule will handle the redirect — no actual HTTP traffic reaches the EC2. This improves user experience while maintaining security. Without the port 80 rule, users typing URLs without `https://` would get "connection refused."

### Step 3.2: Update EC2 Security Group

Your EC2 should ONLY accept traffic from the ALB, not the internet:

```hcl
# ====================
# Update EC2 SG - Allow ALB Traffic
# ====================

resource "aws_security_group_rule" "chewbacca_ec2_from_alb01" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.chewbacca_ec2_sg01.id
  source_security_group_id = aws_security_group.chewbacca_alb_sg01.id
  description              = "Allow traffic from ALB only"
}
```

[!warning] OPTIONAL BUT RECOMMENDED

For true "private EC2" architecture, you should **remove** the `0.0.0.0/0` HTTP ingress rule from `security_groups.tf`. This forces ALL traffic through the ALB. But you can do that cleanup later — the lab will still work with both rules present.

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why use `source_security_group_id` instead of the ALB's IP address?*
> 
> **A (Explain Like I'm 10):** ALBs don't have one fixed IP address — they have MANY that can change! It's like trying to allowlist a delivery company by their truck license plates — they have hundreds of trucks, and the plates change. Instead, you say "anyone wearing a FedEx uniform" (the ALB security group) can deliver. AWS automatically knows which IPs belong to that uniform at any moment.
> 
> **Evaluator Question:** *What's the security implication if you accidentally left 0.0.0.0/0 on port 80 in the EC2 security group?*
> 
> **Model Answer:** Attackers could bypass the ALB entirely and hit EC2 directly. This bypasses: (1) WAF rules attached to ALB, (2) TLS encryption (they'd use HTTP), (3) Access logging at ALB, (4) Rate limiting at ALB. The whole point of this architecture is funneling ALL traffic through the ALB. Direct EC2 access destroys that security model.

### Step 3.3: Create the Application Load Balancer

```hcl
# ====================
# Application Load Balancer
# ====================

resource "aws_lb" "chewbacca_alb01" {
  name               = "${local.name_prefix}-alb01"
  internal           = false  # Internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.chewbacca_alb_sg01.id]
  
  # ALB goes in PUBLIC subnets (needs internet access)
  subnets = [
    aws_subnet.chewbacca_public_subnet01.id,
    aws_subnet.chewbacca_public_subnet02.id
  ]

  enable_deletion_protection = false  # Set true in production

  tags = {
    Name = "${local.name_prefix}-alb01"
  }
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why does the ALB go in PUBLIC subnets when the EC2 is in PRIVATE subnets?*
> 
> **A (Explain Like I'm 10):** Think of a hotel. The **lobby** (ALB in public subnet) faces the street — anyone can walk in from outside. The **guest rooms** (EC2 in private subnet) are deeper inside — you can only reach them THROUGH the lobby. The lobby is designed to handle strangers; the rooms are protected. The ALB is your lobby — it meets the internet so your servers don't have to.
> 
> **Evaluator Question:** *Why does the ALB require subnets in at least two Availability Zones?*
> 
> **Model Answer:** ALBs are designed for high availability. AWS distributes ALB nodes across the specified AZs. If one AZ has an outage (data center failure, network issue), the ALB continues serving traffic from the other AZ. This is why production architectures always span multiple AZs — it's AWS's fundamental resilience pattern. Terraform will error if you provide only one subnet.

### Step 3.4: Create Target Group

The Target Group defines WHERE the ALB sends traffic:

```hcl
# ====================
# Target Group
# ====================

resource "aws_lb_target_group" "chewbacca_tg01" {
  name        = "${local.name_prefix}-tg01"
  port        = var.app_port
  protocol    = "HTTP"  # ALB → EC2 is HTTP (TLS terminates at ALB)
  vpc_id      = aws_vpc.chewbacca_vpc01.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"  # Your app needs this endpoint!
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name = "${local.name_prefix}-tg01"
  }
}

# ====================
# Register EC2 with Target Group
# ====================

resource "aws_lb_target_group_attachment" "chewbacca_tg_attach01" {
  target_group_arn = aws_lb_target_group.chewbacca_tg01.arn
  target_id        = aws_instance.chewbacca_ec201_private_bonus.id
  port             = var.app_port
}
```

At this point, your Flask app already has:
- ✅ `/health` endpoint returning 200
- ✅ Listening on port 80
- ✅ Running in private subnet

No application changes needed!

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why does the Target Group use HTTP when we're setting up HTTPS? Isn't that insecure?*
> 
> **A (Explain Like I'm 10):** The HTTPS "envelope" gets opened at the ALB (TLS termination). From ALB to EC2, the traffic is INSIDE your VPC — like passing notes inside your own house. It's already protected by the VPC walls (no internet access to private subnet). Re-encrypting would slow things down and the certificate management on EC2 adds complexity. Think of it as: locked mailbox on the street (TLS), but once inside your house, you just carry the letter normally.
> 
> **Evaluator Question:** *What is a health check, and why is the path `/health` important?*
> 
> **Model Answer:** Health checks let the ALB verify targets are functioning. The ALB periodically hits `/health` on each EC2. If it gets a 200 response, the target is "healthy" and receives traffic. If it fails `unhealthy_threshold` times, the ALB stops sending traffic to that target. The `/health` endpoint should be lightweight (no DB calls) and return 200 if the app is running. This is how ALB provides automatic failover — it only sends traffic to working servers.

### Step 3.5: Create ALB Listeners

Listeners define HOW the ALB handles incoming requests:

```hcl
# ====================
# HTTPS Listener (443)
# ====================

resource "aws_lb_listener" "chewbacca_https_listener01" {
  load_balancer_arn = aws_lb.chewbacca_alb01.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.chewbacca_cert_validation01.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chewbacca_tg01.arn
  }

  tags = {
    Name = "${local.name_prefix}-https-listener01"
  }
}

# ====================
# HTTP Listener (80) - Redirect to HTTPS
# ====================

resource "aws_lb_listener" "chewbacca_http_listener01" {
  load_balancer_arn = aws_lb.chewbacca_alb01.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"  # Permanent redirect
    }
  }

  tags = {
    Name = "${local.name_prefix}-http-listener01"
  }
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** What's the difference between HTTP_301 and HTTP_302 redirects?*
> 
> **A (Explain Like I'm 10):** Imagine you moved to a new house. **301 (Permanent)** is like telling the post office "I moved forever, update all your records." **302 (Temporary)** is like "I'm staying at a friend's for a week, but my real address is still the old one." For HTTP→HTTPS, we use 301 because we ALWAYS want HTTPS. Browsers remember 301 redirects and go directly to HTTPS next time, saving a round trip.
> 
> **Evaluator Question:** *What does the `ssl_policy` parameter control, and why does it matter?*
> 
> **Model Answer:** The SSL policy defines which TLS versions and cipher suites the ALB accepts. `ELBSecurityPolicy-TLS13-1-2-2021-06` supports TLS 1.2 and 1.3 with modern ciphers. Older policies allow TLS 1.0/1.1, which have known vulnerabilities. Compliance frameworks (PCI-DSS, HIPAA) require disabling old TLS versions. The policy name includes the date AWS published it — newer policies reflect current security best practices.

---

## PART 4: Web Application Firewall (WAF)

### Step 4.1: Understanding WAF

> [!question] SOCRATIC Q&A
> 
> ***Q:** We have security groups already. Why do we need WAF too?*
> 
> **A (Explain Like I'm 10):** Security groups are like a bouncer checking IDs at the door — "Are you on the list? What's your IP address?" But they can't read what's INSIDE your bag. WAF is like an X-ray machine — it looks at the CONTENT of each request. "Are you trying to sneak in SQL injection? Is this a known attack pattern? Are you a bot?" Security groups filter WHO can connect; WAF filters WHAT they're sending.
> 
> **Evaluator Question:** *What types of attacks does WAF protect against that security groups cannot?*
> 
> **Model Answer:** WAF protects against Layer 7 (application layer) attacks: SQL injection, cross-site scripting (XSS), path traversal, request smuggling, known CVE exploits, bad bots, and rate limiting abuse. Security groups only operate at Layer 4 (IP/port) — they can't inspect HTTP content. A valid IP on an allowed port could still send malicious SQL in a form field; only WAF catches that.

### Step 4.2: Create WAF Web ACL

```hcl
# ====================
# WAF Web ACL
# ====================

resource "aws_wafv2_web_acl" "chewbacca_waf01" {
  name        = "${local.name_prefix}-waf01"
  description = "WAF for ALB - blocks common attacks"
  scope       = "REGIONAL"  # REGIONAL for ALB, CLOUDFRONT for CloudFront

  default_action {
    allow {}  # Allow by default, block specific threats
  }

  # AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}  # Use rule group's actions as-is
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

  # AWS Managed Rules - SQL Injection
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

  # AWS Managed Rules - Known Bad Inputs
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

  tags = {
    Name = "${local.name_prefix}-waf01"
  }
}

# ====================
# Associate WAF with ALB
# ====================

resource "aws_wafv2_web_acl_association" "chewbacca_waf_alb_assoc01" {
  resource_arn = aws_lb.chewbacca_alb01.arn
  web_acl_arn  = aws_wafv2_web_acl.chewbacca_waf01.arn
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** What's the difference between `scope = "REGIONAL"` and `scope = "CLOUDFRONT"`?*
> 
> **A (Explain Like I'm 10):** Think of it like local police vs. federal agents. **REGIONAL** WAF protects resources in ONE specific region (your ALB in us-east-1). **CLOUDFRONT** WAF protects CloudFront, which is GLOBAL — it exists everywhere at once. AWS literally stores them in different places. CloudFront WAF must live in us-east-1 (AWS's "headquarters" for global services). Regional WAF lives wherever your ALB is.
> 
> **Evaluator Question:** *Why use AWS Managed Rules instead of writing custom rules?*
> 
> **Model Answer:** AWS Managed Rules are maintained by AWS security researchers who track emerging threats, CVEs, and attack patterns. They're updated automatically without your intervention. Writing custom rules requires deep security expertise and constant maintenance. Managed Rules cover 80%+ of common threats immediately. Custom rules add value for application-specific logic (rate limiting specific endpoints, blocking specific countries), but shouldn't replace the foundational managed rules.

---

## PART 5: CloudWatch Dashboard

### Step 5.1: Create Operational Dashboard

```hcl
# ====================
# CloudWatch Dashboard
# ====================

resource "aws_cloudwatch_dashboard" "chewbacca_dashboard01" {
  dashboard_name = "${local.name_prefix}-dashboard01"

  dashboard_body = jsonencode({
    widgets = [
      # ALB Request Count
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
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.chewbacca_alb01.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      # ALB 5xx Errors
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
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.chewbacca_alb01.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.chewbacca_alb01.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      # Target Health
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Healthy/Unhealthy Targets"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.chewbacca_tg01.arn_suffix, "LoadBalancer", aws_lb.chewbacca_alb01.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.chewbacca_tg01.arn_suffix, "LoadBalancer", aws_lb.chewbacca_alb01.arn_suffix]
          ]
          period = 60
          stat   = "Average"
        }
      },
      # WAF Blocked Requests
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "WAF Blocked Requests"
          region = var.aws_region
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", "${local.name_prefix}-waf01", "Rule", "ALL"]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      # Response Time
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title  = "Target Response Time"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.chewbacca_alb01.arn_suffix]
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
> ***Q:** Why do we need a dashboard when we have alarms?*
> 
> **A (Explain Like I'm 10):** Alarms are like smoke detectors — they scream when there's a fire, but they don't tell you anything when things are normal. A dashboard is like a car's dashboard — you can see your speed, fuel, engine temperature ANYTIME, even when nothing's wrong. During an incident, dashboards show the CONTEXT: "Is this spike normal? Was traffic already high? Did WAF start blocking more?" Alarms say "problem!"; dashboards say "here's the whole picture."
> 
> **Evaluator Question:** *What metrics would you add to detect a DDoS attack vs. a legitimate traffic spike?*
> 
> **Model Answer:** DDoS indicators: (1) WAF blocked requests spike dramatically, (2) Request count increases but unique client IPs don't, (3) Specific URIs targeted repeatedly, (4) Geographic concentration from unusual regions. Legitimate spike indicators: (1) Even distribution across endpoints, (2) Request count and unique IPs increase proportionally, (3) No WAF blocks increase, (4) Matches expected events (marketing campaign, product launch). Add widgets for unique client IPs and geographic distribution to distinguish.

---

## PART 6: ALB 5xx Error Alarm

### Step 6.1: Create SNS Alarm for Server Errors

```hcl
# ====================
# ALB 5xx Error Alarm
# ====================

resource "aws_cloudwatch_metric_alarm" "chewbacca_alb_5xx_alarm01" {
  alarm_name          = "${local.name_prefix}-alb-5xx-alarm01"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10  # Alert if > 10 5xx errors in 2 consecutive minutes
  alarm_description   = "ALB target 5xx errors exceeding threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.chewbacca_alb01.arn_suffix
  }

  alarm_actions = [aws_sns_topic.chewbacca_sns_topic01.arn]
  ok_actions    = [aws_sns_topic.chewbacca_sns_topic01.arn]

  tags = {
    Name = "${local.name_prefix}-alb-5xx-alarm01"
  }
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why do we alert on 5xx errors specifically? What about 4xx errors?*
> 
> **A (Explain Like I'm 10):** Error codes tell you WHO made the mistake. **4xx errors** (400, 401, 403, 404) mean the USER did something wrong — asked for a page that doesn't exist, forgot their password, etc. **5xx errors** (500, 502, 503) mean YOUR SERVER did something wrong — crashed, can't reach the database, ran out of memory. You can't fix users being confused, but you CAN fix your server breaking. 5xx = "your problem to fix NOW."
> 
> **Evaluator Question:** *What's the difference between `HTTPCode_ELB_5XX_Count` and `HTTPCode_Target_5XX_Count`?*
> 
> **Model Answer:** `HTTPCode_ELB_5XX_Count` means the ALB ITSELF generated the error — typically when all targets are unhealthy or timing out. `HTTPCode_Target_5XX_Count` means the EC2 returned a 5xx to the ALB, which passed it through. ELB 5xx = infrastructure problem (no healthy targets). Target 5xx = application problem (your code crashed). Both are serious, but the root cause differs. Monitor both, but Target 5xx usually requires code investigation.

---

## PART 7: DNS Records (Route53)

### Step 7.1: Point Domain to ALB

```hcl
# ====================
# Route53 Record - App Subdomain → ALB
# ====================

resource "aws_route53_record" "chewbacca_app_record01" {
  zone_id = aws_route53_zone.chewbacca_zone01.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"  # app.chewbacca-growl.com
  type    = "A"

  alias {
    name                   = aws_lb.chewbacca_alb01.dns_name
    zone_id                = aws_lb.chewbacca_alb01.zone_id
    evaluate_target_health = true
  }
}
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why use an ALIAS record instead of a CNAME record for the ALB?*
> 
> **A (Explain Like I'm 10):** A CNAME is like a forwarding address: "app.chewbacca-growl.com → send to alb123.us-east-1.elb.amazonaws.com." The problem? DNS rules say you CAN'T have a CNAME at the "root" of your domain (chewbacca-growl.com without "app"). ALIAS is AWS's special trick — it looks like an A record (direct IP) but AWS updates the IPs automatically when the ALB changes. ALIAS works at root AND subdomains, and it's FREE for AWS resources (no extra DNS queries billed).
> 
> **Evaluator Question:** *What does `evaluate_target_health = true` do?*
> 
> **Model Answer:** When true, Route53 checks if the ALB has healthy targets before returning its IP addresses. If all targets are unhealthy, Route53 can return SERVFAIL or route to a backup (if you have failover routing). This integrates DNS with your health checks — users don't get directed to a broken endpoint. For single-ALB setups, it's informational; for multi-region failover, it's critical.

---

## PART 8: Outputs

### Step 8.1: Create Bonus-B Outputs

**Action:** Create `bonus_b_outputs.tf`:

```hcl
# ====================
# Bonus-B Outputs
# ====================

output "alb_dns_name" {
  description = "ALB DNS name (use for testing before DNS propagates)"
  value       = aws_lb.chewbacca_alb01.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 ALIAS records)"
  value       = aws_lb.chewbacca_alb01.zone_id
}

output "app_url" {
  description = "Application URL (HTTPS)"
  value       = "https://${var.app_subdomain}.${var.domain_name}"
}

output "waf_arn" {
  description = "WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.chewbacca_waf01.arn
}

output "dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${local.name_prefix}-dashboard01"
}

output "target_group_arn" {
  description = "Target Group ARN (for health check verification)"
  value       = aws_lb_target_group.chewbacca_tg01.arn
}
```

---

terraform validate
terraform plan
terraform apply

## Application Requirements

> [!warning] CRITICAL - YOUR APP MUST SUPPORT THIS
> 
> Your Flask application needs these capabilities:
> 
> 1. **Listen on port 80** (or whatever `var.app_port` is set to)
> 2. **Health check endpoint**: `/health` that returns HTTP 200
> 3. **Running with proper permissions**: `sudo python3 app.py` or systemd service

### Sample Health Check Endpoint

Add this to your Flask app:

```python
@app.route('/health')
def health():
    """Health check endpoint for ALB"""
    return 'OK', 200
```

> [!question] SOCRATIC Q&A
> 
> ***Q:** Why does the health check endpoint just return "OK"? Shouldn't it check the database?*
> 
> **A (Explain Like I'm 10):** Imagine you're a doctor doing a quick checkup. A HEALTH check asks "Are you alive and basically functioning?" (heartbeat, breathing). A READINESS check asks "Are you ready to work?" (including dependencies like database). ALB health checks should be FAST — every 30 seconds times hundreds of targets adds up. If the health check calls the database and the DB is slow, the ALB thinks your app is unhealthy when really the DB is just busy. Keep health checks lightweight; use separate endpoints for deeper checks.
> 
> **Evaluator Question:** *When would you want the health check to verify database connectivity?*
> 
> **Model Answer:** When the application is USELESS without the database. If every request needs DB access and the DB is down, routing traffic to that instance wastes resources and creates user errors. In this case, include a simple DB ping (SELECT 1) in the health check. Balance: Fast health checks keep routing responsive; deeper health checks ensure meaningful availability. Many systems use two endpoints: `/health` (am I running?) and `/ready` (can I serve requests?).

---

## Verification Commands

### Verify ALB Exists and Is Active

```bash
# ALB exists and is active
aws elbv2 describe-load-balancers \
  --names chewbacca-alb01 \
  --query "LoadBalancers[0].State.Code"
# Expected: "active"
```

### Verify HTTPS Listener

```bash
# HTTPS listener exists on 443
aws elbv2 describe-listeners \
  --load-balancer-arn <ALB_ARN> \
  --query "Listeners[].{Port:Port,Protocol:Protocol}"
# Expected: [{Port:443,Protocol:HTTPS}, {Port:80,Protocol:HTTP}]
```

### Verify Target Health

```bash
# Targets are healthy
aws elbv2 describe-target-health \
  --target-group-arn <TG_ARN>
# Expected: State = "healthy"
```

### Verify WAF Attachment

```bash
# WAF attached to ALB
aws wafv2 get-web-acl-for-resource \
  --resource-arn <ALB_ARN>
# Expected: WebACL details returned (not empty)
```

### Verify Alarm Exists

```bash
# 5xx alarm exists
aws cloudwatch describe-alarms \
  --alarm-name-prefix chewbacca-alb-5xx
# Expected: Alarm configuration returned
```

### Verify Dashboard Exists

```bash
# Dashboard exists
aws cloudwatch list-dashboards \
  --dashboard-name-prefix chewbacca
# Expected: Dashboard name returned
```

### Test HTTPS Access

```bash
# Test HTTPS (after DNS propagates)
curl -I https://app.chewbacca-growl.com
# Expected: HTTP/2 200 (or 301 redirect first)

# Test HTTP redirect
curl -I http://app.chewbacca-growl.com
# Expected: HTTP/1.1 301 Moved Permanently, Location: https://...
```

### Test ALB Direct (Before DNS)

```bash
# Use ALB DNS directly (bypasses your domain)
curl -I https://<ALB_DNS_NAME> --insecure
# Note: --insecure because cert is for your domain, not the ALB DNS
```

---

## Common Failure Modes & Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| ALB returns 502 Bad Gateway | Target not responding on health check port | Verify app is running and listening on correct port |
| ALB returns 503 Service Unavailable | All targets unhealthy | Check health check path exists (`/health`) and returns 200 |
| Certificate validation stuck "Pending" | DNS validation records not created | Verify Route53 records or create manually in your DNS provider |
| HTTPS shows "Not Secure" | Certificate doesn't match domain | Verify ACM cert covers the domain you're accessing |
| WAF not blocking test attacks | Web ACL not associated | Verify `aws_wafv2_web_acl_association` exists |
| Alarm not triggering | Wrong metric dimensions | Verify `LoadBalancer` dimension matches ALB ARN suffix |

---

## Deliverables Checklist

| Requirement | Proof Command |
|-------------|---------------|
| ALB exists and active | `aws elbv2 describe-load-balancers --names chewbacca-alb01` |
| HTTPS listener on 443 | `aws elbv2 describe-listeners --load-balancer-arn <ARN>` |
| HTTP redirect to HTTPS | `curl -I http://app.chewbacca-growl.com` |
| Targets healthy | `aws elbv2 describe-target-health --target-group-arn <ARN>` |
| WAF attached | `aws wafv2 get-web-acl-for-resource --resource-arn <ALB_ARN>` |
| Alarm exists | `aws cloudwatch describe-alarms --alarm-name-prefix chewbacca-alb-5xx` |
| Dashboard exists | `aws cloudwatch list-dashboards --dashboard-name-prefix chewbacca` |
| App accessible via HTTPS | `curl https://app.chewbacca-growl.com/health` returns 200 |

---

## What This Lab Proves About You

*If you complete this lab, you've demonstrated:*

- **Production ingress patterns** — ALB + TLS + WAF
- **Defense in depth** — Multiple security layers working together
- **Operational maturity** — Dashboards, alarms, health checks
- **Infrastructure as Code** — Entire stack reproducible via Terraform
- **Enterprise architecture** — This is how real companies ship

**"I can build, secure, and operate production-grade web infrastructure using code."**

*This is exactly how modern companies ship. You're doing real cloud engineering.*

---

## What's Next: Lab 2

**Lab 2: CloudFront, Origin Cloaking & Caching**

In Lab 2, you'll add CloudFront in front of this ALB to:
- Hide the ALB from direct internet access (origin cloaking)
- Move WAF to the edge (CloudFront instead of ALB)
- Implement correct caching policies
- Enable global edge delivery

This architecture becomes:
```
Internet → CloudFront (+ WAF) → ALB (locked) → Private EC2 → RDS
```

*You're building toward a complete enterprise architecture.*
