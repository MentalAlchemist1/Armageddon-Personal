# providers.tf
# This tells Terraform which cloud provider to use and where to deploy
provider "aws" {
  region = var.aws_region
}

# Required for CloudFront WAF (scope=CLOUDFRONT) and CloudFront ACM certificates
# These MUST be in us-east-1 regardless of where your other resources live
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
