# ====================
# Bonus-B Outputs
# ====================

output "alb_dns_name" {
  description = "ALB DNS name (use for testing before DNS propagates)"
  value       = aws_lb.main.dns_name
}

output "app_url" {
  description = "Application URL (HTTPS)"
  value       = "https://${var.app_subdomain}.${var.domain_name}"
}

output "app_url_direct_alb" {
  description = "Direct ALB URL (for testing, will show certificate warning)"
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