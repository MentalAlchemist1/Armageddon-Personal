# security_groups.tf
# Firewall rules for EC2 and RDS

# EC2 Security Group
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg01"
  description = "Security group for EC2 application server"
  vpc_id      = aws_vpc.main.id

  # HTTP from anywhere (for the web app)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH from anywhere (TIGHTEN THIS IN PRODUCTION!)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Replace with your IP
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-sg01"
  })
}