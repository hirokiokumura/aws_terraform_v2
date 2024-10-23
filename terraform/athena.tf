resource "aws_athena_workgroup" "workgroup" {
  name = "apricot1224-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://apricot1224/output/"
    }
  }
}