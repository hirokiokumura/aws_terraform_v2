# Data source for S3 prefix list
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.ap-northeast-1.s3"
}

# セキュリティグループモジュール
module "security_group" {
  source = "./modules/security_group"

  name        = "internal-https-sg"
  description = "Security group for internal HTTPS access and DNS"
  vpc_id      = aws_vpc.primary.id

  # Ingressルール
  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "${var.ip_address}/32"
      description = "Allow HTTPS from admin IP"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = aws_vpc_ipv4_cidr_block_association.secondary.cidr_block
      description = "Allow HTTPS from secondary VPC CIDR"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = aws_vpc.primary.cidr_block
      description = "Allow HTTPS from primary VPC CIDR"
    }
  ]

  # Egressルール (CIDR ブロック)
  egress_with_cidr_blocks = [
    {
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      cidr_blocks = "169.254.169.253/32"
      description = "Allow DNS TCP to Amazon DNS server"
    },
    {
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      cidr_blocks = "169.254.169.253/32"
      description = "Allow DNS UDP to Amazon DNS server"
    }
  ]

  # Egressルール (Prefix List ID)
  egress_with_prefix_list_ids = [
    {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = data.aws_prefix_list.s3.id
      description     = "Allow HTTPS to S3 via VPC Gateway Endpoint"
    }
  ]

  tags = {
    Name        = "internal-https-sg"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
