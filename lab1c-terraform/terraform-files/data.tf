# ============================================
# DATA SOURCES
# ============================================
# Data sources query existing AWS information
# They don't create anything—they just look things up.

# Get current AWS account ID and caller identity
# Used for: S3 bucket naming (ensures globally unique names)
data "aws_caller_identity" "chewbacca_self01" {}

# Get current AWS region
# Used for: ARN construction, multi-region awareness
data "aws_region" "chewbacca_current01" {}

# ============================================
# OPTIONAL: Commonly needed data sources
# Uncomment as needed for your configuration
# ============================================

# # Get available AZs in current region
# data "aws_availability_zones" "chewbacca_azs01" {
#   state = "available"
# }

# # Get latest Amazon Linux 2023 AMI
# data "aws_ami" "chewbacca_amazon_linux01" {
#   most_recent = true
#   owners      = ["amazon"]
#
#   filter {
#     name   = "name"
#     values = ["al2023-ami-*-x86_64"]
#   }
#
#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
# }
