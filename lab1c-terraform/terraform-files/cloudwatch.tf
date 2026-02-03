# cloudwatch.tf
# Observability: Logs, Alarms, and Dashboards

# Log group for application logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${local.name_prefix}-app"
  retention_in_days = 7

  tags = local.common_tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"

  tags = local.common_tags
}

# Email subscription (requires manual confirmation!)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Metric filter to extract DB connection errors from logs
resource "aws_cloudwatch_log_metric_filter" "db_errors" {
  name           = "${local.name_prefix}-db-connection-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "?ERROR ?\"DB connection\" ?timeout ?refused ?\"Access denied\""

  metric_transformation {
    name          = "DBConnectionErrors"
    namespace     = "Lab/RDSApp"
    value         = "1"
    default_value = "0"
  }
}

# Alarm when DB errors exceed threshold
resource "aws_cloudwatch_metric_alarm" "db_connection_failure" {
  alarm_name          = "${local.name_prefix}-db-connection-failure"
  alarm_description   = "Triggers when DB connection errors exceed 3 in 5 minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 3

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}