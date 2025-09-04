module "internal_https_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "internal-https-sg"
  description = "Security group for internal HTTPS access"
  vpc_id      = aws_vpc.primary.id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from admin IP"
      cidr_blocks = "${var.ip_address}/32"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from secondary VPC CIDR"
      cidr_blocks = aws_vpc_ipv4_cidr_block_association.secondary.cidr_block
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from primary VPC CIDR"
      cidr_blocks = aws_vpc.primary.cidr_block
    }
  ]

  egress_with_prefix_list_ids = [
    {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      description     = "Allow HTTPS to S3 via VPC Gateway Endpoint"
      prefix_list_ids = [data.aws_prefix_list.s3.id]
    }
  ]

  tags = {
    Name = "internal-https-sg"
  }
}

# Data source for S3 prefix list
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.ap-northeast-1.s3"
}