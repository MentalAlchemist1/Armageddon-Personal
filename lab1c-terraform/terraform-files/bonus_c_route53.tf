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