# outputs.tf
# São Paulo - Stateless compute outputs only

output "vpc_id" {
  description = "ID of the São Paulo VPC"
  value       = aws_vpc.main.id
}

output "sp_vpc_cidr" {
  description = "São Paulo VPC CIDR - Tokyo needs this for routing and SG rules"
  value       = aws_vpc.main.cidr_block
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.app.public_dns
}

output "init_url" {
  description = "URL to initialize the database (via TGW to Tokyo RDS)"
  value       = "http://${aws_instance.app.public_ip}/init"
}

output "list_url" {
  description = "URL to list all notes (via TGW to Tokyo RDS)"
  value       = "http://${aws_instance.app.public_ip}/list"
}

# Lab 3: TGW outputs - Tokyo needs the SP TGW ID for peering
output "sp_tgw_id" {
  description = "São Paulo TGW ID - Tokyo needs this for peering request"
  value       = aws_ec2_transit_gateway.liberdade_tgw01.id
}