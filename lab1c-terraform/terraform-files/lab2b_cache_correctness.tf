# Lab 2B - Cache Correctness: Policies for Static vs API

#################################################
# 1) Cache policy for static content (aggressive)
#################################################

resource "aws_cloudfront_cache_policy" "static" {
  name        = "${var.project_name}-cache-static"
  comment     = "Aggressive caching for /static/*"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

#################################################
# 2) Cache policy for API (safe default: disabled)
# Note: When TTL=0, all cache params must be minimal/disabled
#################################################

resource "aws_cloudfront_cache_policy" "api_disabled" {
  name        = "${var.project_name}-cache-api-disabled"
  comment     = "Disable caching for /api/* by default"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}

#################################################
# 3) Origin request policy for API
#################################################

resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${var.project_name}-orp-api"
  comment = "Forward necessary values for API calls"

  cookies_config {
    cookie_behavior = "all"
  }

  query_strings_config {
    query_string_behavior = "all"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Content-Type", "Origin", "Host", "Accept"]
    }
  }
}

#################################################
# 4) Origin request policy for static (minimal)
#################################################

resource "aws_cloudfront_origin_request_policy" "static" {
  name    = "${var.project_name}-orp-static"
  comment = "Minimal forwarding for static assets"

  cookies_config {
    cookie_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "none"
  }

  headers_config {
    header_behavior = "none"
  }
}

#################################################
# 5) Response headers policy for static
#################################################

resource "aws_cloudfront_response_headers_policy" "static" {
  name    = "${var.project_name}-rsp-static"
  comment = "Add explicit Cache-Control for static content"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = true
      value    = "public, max-age=86400, immutable"
    }
  }
}
