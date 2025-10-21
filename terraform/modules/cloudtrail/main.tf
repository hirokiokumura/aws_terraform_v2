module "bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.1.0"

  bucket = var.bucket_name

  attach_policy = true
  policy        = var.bucket_policy

  # S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudwatch_log_group" "example" {
  count = var.environment == "prod" ? 1 : 0
  name  = "aws-cloudtrail-logs-${var.aws_account_id}"
}

resource "aws_cloudtrail" "this" {
  depends_on = [module.bucket]

  name           = var.cloudtrail_name
  s3_bucket_name = var.bucket_name

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }

  dynamic "insight_selector" {
    for_each = var.insight_selectors
    content {
      insight_type = insight_selector.value
    }
  }

  cloud_watch_logs_group_arn = var.environment == "prod" ? "${aws_cloudwatch_log_group.example[0].arn}:*" : null
  cloud_watch_logs_role_arn  = var.environment == "prod" ? aws_iam_role.cloudtrail_cloudwatch_events_role[0].arn : null
}

resource "aws_iam_role" "cloudtrail_cloudwatch_events_role" {
  count = var.environment == "prod" ? 1 : 0

  name               = "cloudtrail_events_role"
  assume_role_policy = data.aws_iam_policy_document.assume_policy.json
}

resource "aws_iam_role_policy" "policy" {
  count = var.environment == "prod" ? 1 : 0

  name   = "cloudtrail_cloudwatch_events_policy"
  role   = aws_iam_role.cloudtrail_cloudwatch_events_role[0].id
  policy = data.aws_iam_policy_document.policy[0].json
}

data "aws_iam_policy_document" "policy" {
  count = var.environment == "prod" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream"]
    resources = ["${aws_cloudwatch_log_group.example[0].arn}:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.example[0].arn}:*"]
  }
}

data "aws_iam_policy_document" "assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

# metric-filter.tfで定義したカスタムメトリクス用のアラーム
resource "aws_cloudwatch_metric_alarm" "test-alarm" {


  alarm_name          = "aalarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "error"
  namespace           = "CloudTrail/LogMetrics"
  period              = "120"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors error occurence"

  # データ不足時のアクションを指定
  insufficient_data_actions = []

  # arnを指定すること
  alarm_actions = [aws_sns_topic.athena_alert_topic2.arn]

  treat_missing_data = "breaching"
}

resource "aws_sns_topic" "athena_alert_topic2" {
  name = "athena_alert_topic2"
}

resource "aws_sns_topic_subscription" "athena_alert_subscription" {
  topic_arn = aws_sns_topic.athena_alert_topic2.arn
  protocol  = "email"
  endpoint  = "ouji.info@gmail.com"
}

resource "aws_cloudwatch_log_metric_filter" "error_alarm" {

  name           = "error"
  pattern        = "ERROR"
  log_group_name = aws_cloudwatch_log_group.example[0].name

  metric_transformation {
    name      = "LogMetrics"
    namespace = "CloudTrail"
    value     = 1
  }

}
