resource "aws_vpc" "primary" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "primary_vpc"
  }
}

resource "aws_subnet" "primary_1a" {
  vpc_id            = aws_vpc.primary.id
  availability_zone = "ap-northeast-1a"
  cidr_block        = "10.0.0.0/23"

  tags = {
    Name = "subnet_primary_1a"
  }
}

resource "aws_subnet" "primary_1c" {
  vpc_id            = aws_vpc.primary.id
  availability_zone = "ap-northeast-1c"
  cidr_block        = "10.0.2.0/23"

  tags = {
    Name = "subnet_primary_1c"
  }
}

# # ルートテーブル for subnet1
resource "aws_route_table" "rtb_subnet_primary_1a" {
  vpc_id = aws_vpc.primary.id


  tags = {
    Name = "rtb-subnet_primary_1a"
  }
}

resource "aws_route_table" "rtb_subnet_primary_1c" {
  vpc_id = aws_vpc.primary.id

  tags = {
    Name = "rtb-subnet_primary_1c"
  }
}

# # サブネットとルートテーブルの紐付け
resource "aws_route_table_association" "assoc_subnet_primary_1a" {
  subnet_id      = aws_subnet.primary_1a.id
  route_table_id = aws_route_table.rtb_subnet_primary_1a.id
}

resource "aws_route_table_association" "assoc_subnet_primary_1c" {
  subnet_id      = aws_subnet.primary_1c.id
  route_table_id = aws_route_table.rtb_subnet_primary_1c.id
}

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.1.4.0/24"
}

resource "aws_subnet" "secondary_1a" {
  vpc_id            = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id
  availability_zone = "ap-northeast-1a"
  cidr_block        = "10.1.4.0/25"

  tags = {
    Name = "subnet_secondary_1a"
  }
}

resource "aws_subnet" "secondary_1c" {
  vpc_id            = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id
  availability_zone = "ap-northeast-1c"
  cidr_block        = "10.1.4.128/25"


  tags = {
    Name = "subnet_secondary_1c"
  }
}

resource "aws_route_table" "rtb_subnet_secondary_1a" {
  vpc_id = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id


  tags = {
    Name = "rtb-subnet_secondary_1a"
  }
}

resource "aws_route_table" "rtb_subnet_secondary_1c" {
  vpc_id = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id

  tags = {
    Name = "rtb-subnet_secondary_1c"
  }
}

# サブネットとルートテーブルの紐付け
resource "aws_route_table_association" "assoc_subnet_secondary_1a" {
  subnet_id      = aws_subnet.secondary_1a.id
  route_table_id = aws_route_table.rtb_subnet_secondary_1a.id
  depends_on     = [aws_route_table.rtb_subnet_secondary_1a]
}


resource "aws_route_table_association" "assoc_subnet_secondary_1c" {
  subnet_id      = aws_subnet.secondary_1c.id
  route_table_id = aws_route_table.rtb_subnet_secondary_1c.id
  depends_on     = [aws_route_table.rtb_subnet_secondary_1c]
}

# VPCエンドポイントモジュールの呼び出し
module "vpc_endpoints" {
  source = "./modules/vpc_endpoint"

  vpc_id = aws_vpc.primary.id

  # ゲートウェイ型エンドポイントの定義
  gateway_endpoints = {
    s3 = {
      name         = "primary-gateway-s3"
      service_name = "com.amazonaws.ap-northeast-1.s3"
    }
  }

  # インターフェース型エンドポイントの定義（必要に応じてコメントを外す）
  interface_endpoints = {
    # ssm = {
    #   name                = "primary-interface-ssm"
    #   service_name        = "com.amazonaws.ap-northeast-1.ssm"
    #   private_dns_enabled = true
    # }

    # ssmmessages = {
    #   name                = "primary-interface-ssmmessages"
    #   service_name        = "com.amazonaws.ap-northeast-1.ssmmessages"
    #   private_dns_enabled = true
    # }

    # secretsmanager = {
    #   name                = "primary-interface-secretsmanager"
    #   service_name        = "com.amazonaws.ap-northeast-1.secretsmanager"
    #   private_dns_enabled = true
    # }

    # ec2 = {
    #   name                = "primary-interface-ec2"
    #   service_name        = "com.amazonaws.ap-northeast-1.ec2"
    #   private_dns_enabled = true
    # }
  }

  # ゲートウェイ型エンドポイント用のルートテーブル
  gateway_route_table_ids = [
    aws_route_table.rtb_subnet_primary_1a.id,
    aws_route_table.rtb_subnet_primary_1c.id,
    aws_route_table.rtb_subnet_secondary_1a.id,
    aws_route_table.rtb_subnet_secondary_1c.id
  ]

  # インターフェース型エンドポイント用のサブネット（必要に応じてコメントを外す）
  # subnet_ids = [
  #   aws_subnet.primary_1a.id,
  #   aws_subnet.primary_1c.id
  # ]

  # インターフェース型エンドポイント用のセキュリティグループ（必要に応じてコメントを外す）
  # security_group_ids = [
  #   aws_security_group.this.id
  # ]

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
