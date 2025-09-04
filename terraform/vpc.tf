module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "main-vpc"
  cidr = "10.0.0.0/22"

  azs             = ["ap-northeast-1a", "ap-northeast-1c"]
  private_subnets = ["10.0.0.0/23", "10.0.2.0/23"]

  # セカンダリCIDRブロック
  secondary_cidr_blocks = ["10.1.4.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPCエンドポイントは個別に手動作成

  tags = {
    Name = "main-vpc"
  }
}

# セカンダリCIDRブロックのサブネット
resource "aws_subnet" "secondary_1a" {
  vpc_id            = module.vpc.vpc_id
  availability_zone = "ap-northeast-1a"
  cidr_block        = "10.1.4.0/25"

  tags = {
    Name = "subnet_secondary_1a"
  }

  depends_on = [module.vpc]
}

resource "aws_subnet" "secondary_1c" {
  vpc_id            = module.vpc.vpc_id
  availability_zone = "ap-northeast-1c"
  cidr_block        = "10.1.4.128/25"

  tags = {
    Name = "subnet_secondary_1c"
  }

  depends_on = [module.vpc]
}

# セカンダリサブネット用のルートテーブル
resource "aws_route_table" "rtb_subnet_secondary_1a" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "rtb-subnet_secondary_1a"
  }

  depends_on = [module.vpc]
}

resource "aws_route_table" "rtb_subnet_secondary_1c" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "rtb-subnet_secondary_1c"
  }

  depends_on = [module.vpc]
}

# セカンダリサブネットとルートテーブルの紐付け
resource "aws_route_table_association" "assoc_subnet_secondary_1a" {
  subnet_id      = aws_subnet.secondary_1a.id
  route_table_id = aws_route_table.rtb_subnet_secondary_1a.id
}

resource "aws_route_table_association" "assoc_subnet_secondary_1c" {
  subnet_id      = aws_subnet.secondary_1c.id
  route_table_id = aws_route_table.rtb_subnet_secondary_1c.id
}

# S3 VPCエンドポイント（Gateway型）
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.ap-northeast-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    module.vpc.private_route_table_ids[0],
    module.vpc.private_route_table_ids[1],
    aws_route_table.rtb_subnet_secondary_1a.id,
    aws_route_table.rtb_subnet_secondary_1c.id
  ]

  tags = {
    Name = "vpc-endpoint-s3"
  }
}

# Interface VPCエンドポイント（セキュリティグループ参照が必要）
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.ap-northeast-1.ssm"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.internal_https_sg.security_group_id]
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
  security_group_ids  = [module.internal_https_sg.security_group_id]
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
  security_group_ids  = [module.internal_https_sg.security_group_id]
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
  security_group_ids  = [module.internal_https_sg.security_group_id]
  private_dns_enabled = true
  subnet_ids          = [module.vpc.private_subnets[0]]

  tags = {
    Name = "vpc-endpoint-ec2"
  }
}

# VPCエンドポイントの参照（他のファイルからの参照用に出力を設定）
# プライマリサブネットの参照
locals {
  primary_subnet_1a_id = module.vpc.private_subnets[0]
  primary_subnet_1c_id = module.vpc.private_subnets[1]
  primary_vpc_id       = module.vpc.vpc_id
  primary_vpc_cidr     = module.vpc.vpc_cidr_block
  secondary_cidr       = "10.1.4.0/24"
}