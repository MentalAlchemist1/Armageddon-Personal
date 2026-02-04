# variables.tf
# All configurable inputs for your infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "chewbacca"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
  # NO DEFAULT - must be provided at runtime!
}

variable "alert_email" {
  description = "Email address for SNS alerts"
  type        = string
}

# ====================
# Bonus-B Variables
# ====================

variable "app_subdomain" {
  description = "Subdomain for the application (e.g., app)"
  type        = string
  default     = "www"
}

variable "app_port" {
  description = "Port the Flask app listens on"
  type        = number
  default     = 80
}

variable "domain_name" {
  default = "wheresjack.com"
}

variable "acm_certificate_arn" {
  default = "arn:aws:acm:us-west-2:262164343754:certificate/51fd15f7-16f4-450d-abb0-280fe573f799"
}