# parameters.tf
# Store non-sensitive configuration in Parameter Store

resource "aws_ssm_parameter" "db_endpoint" {
  name        = "/lab/db/endpoint"
  description = "RDS endpoint"
  type        = "String"
  value       = aws_db_instance.main.endpoint

  tags = local.common_tags
}

resource "aws_ssm_parameter" "db_port" {
  name        = "/lab/db/port"
  description = "RDS port"
  type        = "String"
  value       = tostring(aws_db_instance.main.port)

  tags = local.common_tags
}

resource "aws_ssm_parameter" "db_name" {
  name        = "/lab/db/name"
  description = "Database name"
  type        = "String"
  value       = var.db_name

  tags = local.common_tags
}