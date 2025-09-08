module "security_group" {
  source = "../modules/security_group"

  name   = "security_group_v1"
  vpc_id = aws_vpc.primary.id

  ingress_rules = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["${var.ip_address}/32"]
      description = "Allow HTTPS from home IP"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [aws_vpc_ipv4_cidr_block_association.secondary.cidr_block]
      description = "Allow HTTPS from secondary CIDR"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [aws_vpc.primary.cidr_block]
      description = "Allow HTTPS from VPC"
    }
  ]

  egress_rules = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTPS to VPC only"
    }
  ]

  tags = {
    Name = "security_group_v1"
  }
}