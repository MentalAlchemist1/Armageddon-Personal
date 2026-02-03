# iam.tf
# IAM Role for EC2 to access Secrets Manager and Parameter Store

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
  name               = "${local.name_prefix}-ec2-role01"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.common_tags
}

# Permission policy - what the role can do (LEAST PRIVILEGE!)
data "aws_iam_policy_document" "ec2_permissions" {
  # Read specific secret only
  statement {
    sid    = "ReadSpecificSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = [
      aws_secretsmanager_secret.db_credentials.arn
    ]
  }

  # Read parameters under /lab/db/*
  statement {
    sid    = "ReadDBParameters"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]

    resources = [
      "arn:aws:ssm:${var.aws_region}:*:parameter/lab/db/*"
    ]
  }

  # CloudWatch Logs permissions
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = [
      "${aws_cloudwatch_log_group.app.arn}:*"
    ]
  }
}

# Attach the permissions to the role
resource "aws_iam_role_policy" "ec2_permissions" {
  name   = "${local.name_prefix}-ec2-permissions"
  role   = aws_iam_role.ec2_app.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}

# Instance profile - the "container" that attaches role to EC2
resource "aws_iam_instance_profile" "ec2_app" {
  name = "${local.name_prefix}-instance-profile01"
  role = aws_iam_role.ec2_app.name

  tags = local.common_tags
}