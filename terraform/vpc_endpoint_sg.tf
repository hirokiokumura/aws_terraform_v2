# VPCエンドポイント用セキュリティグループ
module "vpc_endpoint_security_group" {
  source = "./modules/security_group"

  name        = "vpc-endpoint-sg"
  description = "Security group for VPC Interface Endpoints (SSM, EC2, etc.)"
  vpc_id      = aws_vpc.primary.id

  # Ingressルール - Secondary CIDR (EC2配置先) からのHTTPSアクセスのみ
  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = aws_vpc_ipv4_cidr_block_association.secondary.cidr_block
      description = "Allow HTTPS from secondary VPC CIDR (EC2 subnet)"
    }
  ]

  # Egressルール - VPCエンドポイントからAWSサービスへの通信
  egress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow HTTPS to AWS services"
    }
  ]

  egress_with_prefix_list_ids = []

  tags = {
    Name        = "vpc-endpoint-sg"
    Environment = "production"
    ManagedBy   = "Terraform"
    Purpose     = "VPC Interface Endpoints"
  }
}
