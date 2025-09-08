module "security_group" {
  source = "../modules/security_group"

  name        = "internal-https-sg"
  description = "Security group for internal HTTPS traffic with S3 access"
  vpc_id      = aws_vpc.primary.id
  environment = "prod"
  project     = "aws_terraform_v2"

  ingress_rules = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["${var.ip_address}/32"]
      description = "Allow HTTPS from trusted admin IP address"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [aws_vpc_ipv4_cidr_block_association.secondary.cidr_block]
      description = "Allow HTTPS from secondary VPC CIDR block"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [aws_vpc.primary.cidr_block]
      description = "Allow HTTPS from primary VPC CIDR block"
    }
  ]

  egress_rules = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow outbound HTTPS to internet"
    },
    {
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow outbound DNS queries"
    },
    {
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow outbound DNS queries over TCP"
    }
  ]

  tags = {
    Name        = "internal-https-sg"
    Owner       = "Infrastructure Team"
    CostCenter  = "Engineering"
    Compliance  = "SOC2"
  }
}

# S3 Gateway Endpoint Security Group Rule (using traditional AWS provider for prefix list support)
resource "aws_security_group_rule" "egress_https_s3" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = module.security_group.security_group_id
  prefix_list_ids   = [data.aws_prefix_list.s3.id]
  description       = "Allow HTTPS to S3 via VPC Gateway Endpoint"
}

# Data source for S3 prefix list
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.ap-northeast-1.s3"
}