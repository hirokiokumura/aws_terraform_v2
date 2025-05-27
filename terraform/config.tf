data "aws_caller_identity" "self" {}

locals {
  account_id            = data.aws_caller_identity.self.account_id
}

resource "aws_s3_bucket" "this" {
  bucket = "${local.account_alias}-config-bucket"
}

resource "aws_s3_bucket_policy" "config-service" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.config-service.json
}

data "aws_iam_policy_document" "config-service" {
  version = "2012-10-17"
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = [
      "s3:GetBucketAcl"
    ]
    resources = [
      "${aws_s3_bucket.this.arn}"
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = ["${local.account_id}"]
    }
  }
  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      "${aws_s3_bucket.this.arn}"
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = ["${local.account_id}"]
    }
  }
  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.this.arn}/AWSLogs/${local.account_id}/Config/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = ["${local.account_id}"]
    }
  }
}

# S3 Public Access Block
resource "aws_s3_bucket_public_access_block" "config-service" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}