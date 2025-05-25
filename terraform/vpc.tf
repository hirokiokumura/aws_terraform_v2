resource "aws_vpc" "primary" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "primary_vpc"
  }
}

resource "aws_subnet" "primary_v1" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.0.0.0/23"

  tags = {
    Name = "subnet_primary_v1"
  }
}

resource "aws_subnet" "primary_v2" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.0.2.0/23"

  tags = {
    Name = "subnet_primary_v2"
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  vpc_id     = aws_vpc.primary.id
  cidr_block = "10.1.4.0/24"
}

resource "aws_subnet" "secondary_v1" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id
  cidr_block = "10.1.4.0/25"

  tags = {
    Name = "subnet_secondary_v1"
  }
}

resource "aws_subnet" "secondary_v2" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.secondary.vpc_id
  cidr_block = "10.1.4.128/25"

  tags = {
    Name = "subnet_secondary_v2"
  }
}