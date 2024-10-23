terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.72.1"
    }
  }
  backend "s3" {
    bucket = "apricot1224-terraform"
    key    = "state/terraform.tfstate"
    region = "ap-northeast-1"
  }
}