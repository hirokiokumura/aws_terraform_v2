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

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.primary.id
  service_name      = "com.amazonaws.ap-northeast-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.rtb_subnet_primary_1a.id,
    aws_route_table.rtb_subnet_primary_1c.id,
    aws_route_table.rtb_subnet_secondary_1a.id,
    aws_route_table.rtb_subnet_secondary_1c.id
  ]
  tags = {
    "Name" = "primary-gateway-s3"
  }
}

# resource "aws_vpc_endpoint" "ssm" {
#   vpc_id            = aws_vpc.primary.id
#   service_name      = "com.amazonaws.ap-northeast-1.ssm"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.this.id,
#   ]

#   private_dns_enabled = true

#   subnet_ids = [
#     aws_subnet.primary_1a.id
#   ]
#   tags = {
#     Name = "primary-1a-ssm"
#   }
# }

# resource "aws_vpc_endpoint" "ssmmessages" {
#   vpc_id            = aws_vpc.primary.id
#   service_name      = "com.amazonaws.ap-northeast-1.ssmmessages"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.this.id,
#   ]

#   private_dns_enabled = true

#   subnet_ids = [
#     aws_subnet.primary_1a.id
#   ]
#   tags = {
#     Name = "primary-1a-ssmmessages"
#   }
# }

# resource "aws_vpc_endpoint" "secretsmanager" {
#   vpc_id            = aws_vpc.primary.id
#   service_name      = "com.amazonaws.ap-northeast-1.secretsmanager"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.this.id,
#   ]

#   private_dns_enabled = true

#   subnet_ids = [
#     aws_subnet.primary_1a.id
#   ]
#   tags = {
#     Name = "primary-1a-secretsmanager"
#   }
# }

# resource "aws_vpc_endpoint" "ec2" {
#   vpc_id            = aws_vpc.primary.id
#   service_name      = "com.amazonaws.ap-northeast-1.ec2"
#   vpc_endpoint_type = "Interface"

#   security_group_ids = [
#     aws_security_group.this.id,
#   ]

#   private_dns_enabled = true

#   subnet_ids = [
#     aws_subnet.primary_1a.id
#   ]
#   tags = {
#     Name = "primary-1a-ec2"
#   }
# }

# sudo yum install -y postgresql17