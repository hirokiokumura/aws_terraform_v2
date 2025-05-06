terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.97.0"
    }
  }
  backend "s3" {
    bucket = "apricot1224v1-terraform"
    key    = "state/terraform.tfstate"
    region = "ap-northeast-1"
  }
}