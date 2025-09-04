module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "main-vpc"
  cidr = "10.0.0.0/22"

  azs             = ["ap-northeast-1a", "ap-northeast-1c"]
  private_subnets = ["10.0.0.0/23", "10.0.2.0/23", "10.1.4.0/25", "10.1.4.128/25"]

  # セカンダリCIDRブロック
  secondary_cidr_blocks = ["10.1.4.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPCエンドポイントは個別に手動作成

  tags = {
    Name = "main-vpc"
  }
}

# セカンダリサブネットは上記のVPCモジュール内で管理

# S3 VPCエンドポイント（Gateway型）
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.ap-northeast-1.s3"
  vpc_endpoint_type = "Gateway"

  # 全プライベートサブネットのルートテーブルを参照
  route_table_ids = module.vpc.private_route_table_ids

  tags = {
    Name = "vpc-endpoint-s3"
  }
}

# Interface VPCエンドポイント（セキュリティグループ参照が必要）
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.ap-northeast-1.ssm"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
  private_dns_enabled = true
  subnet_ids          = [module.vpc.private_subnets[0]]

  tags = {
    Name = "vpc-endpoint-ssm"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.ap-northeast-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
  private_dns_enabled = true
  subnet_ids          = [module.vpc.private_subnets[0]]

  tags = {
    Name = "vpc-endpoint-ssmmessages"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.ap-northeast-1.secretsmanager"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
  private_dns_enabled = true
  subnet_ids          = [module.vpc.private_subnets[0]]

  tags = {
    Name = "vpc-endpoint-secretsmanager"
  }
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.ap-northeast-1.ec2"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.vpc_endpoint_sg.security_group_id]
  private_dns_enabled = true
  subnet_ids          = [module.vpc.private_subnets[0]]

  tags = {
    Name = "vpc-endpoint-ec2"
  }
}

# VPCとサブネット参照用のlocal変数
locals {
  # プライマリサブネット（0-1番目）
  primary_subnet_1a_id = module.vpc.private_subnets[0]
  primary_subnet_1c_id = module.vpc.private_subnets[1]
  
  # セカンダリサブネット（2-3番目）
  secondary_subnet_1a_id = module.vpc.private_subnets[2]
  secondary_subnet_1c_id = module.vpc.private_subnets[3]
  
  # VPC情報
  primary_vpc_id   = module.vpc.vpc_id
  primary_vpc_cidr = module.vpc.vpc_cidr_block
  secondary_cidr   = "10.1.4.0/24"
}