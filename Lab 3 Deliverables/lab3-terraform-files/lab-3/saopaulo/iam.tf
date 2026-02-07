# iam.tf
# IAM Role for São Paulo EC2 - minimal permissions (stateless compute)

# Trust policy - who can assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# The IAM Role
resource "aws_iam_role" "ec2_app" {
  name               = "${local.name_prefix}-sp-ec2-role01"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.common_tags
}

# SSM Session Manager - so we can connect to verify TGW connectivity
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile - the "container" that attaches role to EC2
resource "aws_iam_instance_profile" "ec2_app" {
  name = "${local.name_prefix}-sp-instance-profile01"
  role = aws_iam_role.ec2_app.name

  tags = local.common_tags
}