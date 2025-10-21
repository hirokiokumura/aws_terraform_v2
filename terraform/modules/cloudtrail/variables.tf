variable "bucket_name" {
  type = string
}
variable "cloudtrail_name" {
  type = string
}

variable "bucket_policy" {
  type = string
}

variable "insight_selectors" {
  type    = list(string)
  default = []
}

variable "aws_account_id" {
  type = string
}

variable "environment" {
  type    = string
  default = "stg"
}
