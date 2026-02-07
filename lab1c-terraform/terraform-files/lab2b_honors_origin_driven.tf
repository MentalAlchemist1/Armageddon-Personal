############################################
# Lab 2B-Honors - Origin Driven Caching (Managed Policies)
############################################

# AWS-managed cache policy: Honor Cache-Control headers from origin
data "aws_cloudfront_cache_policy" "use_origin_cache_headers" {
  name = "Managed-CachingOptimized"
}

# AWS-managed origin request policy: Forward all viewer headers except Host
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}
