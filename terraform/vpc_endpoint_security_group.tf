# VPCエンドポイント専用セキュリティグループ（循環依存を避けるため分離）
module "vpc_endpoint_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name        = "vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from VPC CIDR"
      cidr_blocks = "10.0.0.0/22"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from secondary VPC CIDR"
      cidr_blocks = "10.1.4.0/24"
    }
  ]

  egress_rules = ["https-443-tcp"]

  tags = {
    Name = "vpc-endpoints-sg"
  }
}