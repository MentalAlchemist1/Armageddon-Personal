# saopaulo_tgw.tf
# Liberdade is São Paulo's Japanese district - local compute, remote data.

resource "aws_ec2_transit_gateway" "liberdade_tgw01" {
  description = "liberdade-tgw01 (Sao Paulo spoke)"
  tags        = { Name = "liberdade-tgw01" }
}

# Connect São Paulo VPC to its local TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "liberdade_attach_sp_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id
  vpc_id             = aws_vpc.main.id
  subnet_ids         = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  tags               = { Name = "liberdade-attach-sp-vpc01" }
}

# ⚠️ COMMENT THIS OUT FOR FIRST PASS
# Tokyo hasn't sent the peering invitation yet (peering attachment commented out there too).
# Uncomment after Tokyo creates the peering attachment, then paste the attachment ID.
#
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "liberdade_accept_shinjuku01" {
   transit_gateway_attachment_id = "tgw-attach-088f83c0824af2304"  # ← paste Tokyo peering attachment ID here
   tags                         = { Name = "liberdade-accept-shinjuku01" }
 }