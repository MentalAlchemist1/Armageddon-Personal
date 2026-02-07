# Lab 2A - Route53 records pointing to CloudFront (replaces ALB records)

# Apex domain → CloudFront
resource "aws_route53_record" "apex_to_cloudfront" {
  zone_id = local.chewbacca_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# App subdomain → CloudFront
resource "aws_route53_record" "app_to_cloudfront" {
  zone_id = local.chewbacca_zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_to_cloudfront_ipv6" {
  zone_id = local.chewbacca_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}