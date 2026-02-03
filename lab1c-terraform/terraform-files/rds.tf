# rds.tf
# RDS MySQL database in private subnet

# Subnet group tells RDS which subnets it can use
resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Subnet group for RDS"
  subnet_ids  = aws_subnet.private[*].id # All private subnets

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# The RDS MySQL instance
resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-rds01"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100 # Enable storage autoscaling
  storage_type          = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # CRITICAL: Keep it private!
  publicly_accessible = false

  # For lab - skip final snapshot on destroy
  skip_final_snapshot = true

  # Enable enhanced monitoring (optional but recommended)
  monitoring_interval = 0 # Set to 60 for production

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds01"
  })
}