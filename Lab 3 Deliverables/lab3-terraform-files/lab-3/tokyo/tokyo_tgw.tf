# tokyo_tgw.tf
# Explanation: Shinjuku Station is the hub — Tokyo is the data authority.

resource "aws_ec2_transit_gateway" "shinjuku_tgw01" {
  description = "shinjuku-tgw01 (Tokyo hub)"
  tags        = { Name = "shinjuku-tgw01" }
}

# Explanation: Shinjuku connects to the Tokyo VPC — this is the gate to the medical records vault.
resource "aws_ec2_transit_gateway_vpc_attachment" "shinjuku_attach_tokyo_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.shinjuku_tgw01.id
  vpc_id             = aws_vpc.main.id
  subnet_ids         = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  tags               = { Name = "shinjuku-attach-tokyo-vpc01" }
}

# ⚠️ COMMENT THIS OUT FOR FIRST PASS — São Paulo's TGW doesn't exist yet.
# Uncomment after São Paulo TGW is deployed, then replace the ID.
#
resource "aws_ec2_transit_gateway_peering_attachment" "shinjuku_to_liberdade_peer01" {
  transit_gateway_id      = aws_ec2_transit_gateway.shinjuku_tgw01.id
  peer_region             = "sa-east-1"
  peer_transit_gateway_id = "tgw-0f01d1f9dc23b25cf"  # ← paste SP TGW ID here after SP deploy
  tags                    = { Name = "shinjuku-to-liberdade-peer01" }
}