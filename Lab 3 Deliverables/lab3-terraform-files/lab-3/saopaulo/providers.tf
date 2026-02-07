# providers.tf
# This tells Terraform which cloud provider to use and where to deploy
provider "aws" {
  region = var.aws_region
}

