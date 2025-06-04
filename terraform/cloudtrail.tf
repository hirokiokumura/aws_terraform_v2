data "aws_caller_identity" "current" {}
# data "aws_iam_account_alias" "current" {}

locals {
  # account_id    = data.aws_caller_identity.current.account_id
  # account_alias = data.aws_iam_account_alias.current.account_alias
  bucket_name   = "cloudtrail"
}

module "cloudtrail" {
  source = "../modules/cloudtrail/"

  cloudtrail_name   = "${local.account_alias}-cloudtrail"
  bucket_name       = "${local.account_alias}-${local.bucket_name}"
  insight_selectors = ["ApiCallRateInsight", "ApiErrorRateInsight"]
  bucket_policy = templatefile(
    "${path.module}/policy.json",
    {
      bucket         = "${local.account_alias}-${local.bucket_name}",
      aws_account_id = "${local.account_id}"
    }
  )
  aws_account_id = local.account_id

  environment = "prod"
}