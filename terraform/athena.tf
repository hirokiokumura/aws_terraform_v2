data "aws_iam_account_alias" "current" {}

locals {
  account_alias         = data.aws_iam_account_alias.current.account_alias
  athena_engine_version = "Athena engine version 3"
}


resource "aws_athena_workgroup" "workgroup" {
  name = local.account_alias

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = local.athena_engine_version
    }

    result_configuration {
      output_location = "s3://apricot1224/output/"
    }
  }
}