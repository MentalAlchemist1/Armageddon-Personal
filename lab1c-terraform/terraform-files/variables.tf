# variables.tf
# All configurable inputs for your infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "chewbacca"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
  # NO DEFAULT - must be provided at runtime!
}

variable "alert_email" {
  description = "Email address for SNS alerts"
  type        = string
}

# ====================
# Bonus-B Variables
# ====================

variable "app_subdomain" {
  description = "Subdomain for the application (e.g., app)"
  type        = string
  default     = "www"
}

variable "app_port" {
  description = "Port the Flask app listens on"
  type        = number
  default     = 80
}

variable "domain_name" {
  default = "wheresjack.com"
}

variable "acm_certificate_arn" {
  default = "arn:aws:acm:us-west-2:262164343754:certificate/51fd15f7-16f4-450d-abb0-280fe573f799"
}

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

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

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