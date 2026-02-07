# outputs.tf
# Values displayed after terraform apply

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.app.public_dns
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS alert topic"
  value       = aws_sns_topic.alerts.arn
}

output "init_url" {
  description = "URL to initialize the database"
  value       = "http://${aws_instance.app.public_ip}/init"
}

output "list_url" {
  description = "URL to list all notes"
  value       = "http://${aws_instance.app.public_ip}/list"
}

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

# ============================================
# WAF LOGGING OUTPUTS (Bonus E)
# Append these to your existing outputs.tf
# ============================================

output "waf_log_destination" {
  description = "Which WAF log destination is active"
  value       = var.waf_log_destination
}

output "waf_cw_log_group_name" {
  description = "CloudWatch Log Group name for WAF logs (if cloudwatch destination)"
  value       = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.waf_logs[0].name : null
}

output "waf_cw_log_group_arn" {
  description = "CloudWatch Log Group ARN for WAF logs (if cloudwatch destination)"
  value       = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.waf_logs[0].arn : null
}

output "waf_logs_s3_bucket" {
  description = "S3 bucket name for WAF logs (if s3 destination)"
  value       = var.waf_log_destination == "s3" ? aws_s3_bucket.waf_logs[0].bucket : null
}

output "waf_firehose_name" {
  description = "Firehose stream name for WAF logs (if firehose destination)"
  value       = var.waf_log_destination == "firehose" ? aws_kinesis_firehose_delivery_stream.waf_logs[0].name : null
}

output "waf_firehose_dest_bucket" {
  description = "S3 bucket where Firehose delivers WAF logs (if firehose destination)"
  value       = var.waf_log_destination == "firehose" ? aws_s3_bucket.waf_firehose_dest[0].bucket : null
}
