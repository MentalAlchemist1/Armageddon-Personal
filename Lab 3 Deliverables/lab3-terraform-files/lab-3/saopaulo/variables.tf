# variables.tf
# São Paulo - Stateless compute region (NO database, NO CloudFront)

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "chewbacca"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.1.101.0/24", "10.1.102.0/24"]
}

variable "app_port" {
  description = "Port the Flask app listens on"
  type        = number
  default     = 80
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Lab 3: Tokyo RDS endpoint - São Paulo EC2 connects here via TGW
variable "tokyo_rds_endpoint" {
  description = "Tokyo RDS endpoint for cross-region database access"
  type        = string
  default     = "chewbacca-rds01.cl02ec282asu.us-west-2.rds.amazonaws.com"
}

# DB credentials for Tokyo RDS connection (no local database)
variable "db_name" {
  description = "Database name on Tokyo RDS"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "Database username for Tokyo RDS"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database password for Tokyo RDS"
  type        = string
  sensitive   = true
}