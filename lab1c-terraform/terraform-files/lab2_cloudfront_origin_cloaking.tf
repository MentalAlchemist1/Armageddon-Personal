# Lab 2A - Origin Cloaking: Prefix List + Secret Header

# Reference AWS-managed prefix list for CloudFront origin-facing IPs
data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Only CloudFront origin-facing IPs may reach the ALB on 443
resource "aws_security_group_rule" "alb_ingress_cloudfront" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"

  prefix_list_ids = [
    data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
  ]
}

# Generate random secret header value
resource "random_password" "origin_header_secret" {
  length  = 32
  special = false
}

# ALB listener rule: IF secret header present → forward to target group
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

# ALB listener rule: ELSE → return 403 Forbidden
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
    path_pattern { values = ["*"] }
  }
}
