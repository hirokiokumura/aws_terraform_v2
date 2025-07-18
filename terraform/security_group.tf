resource "aws_security_group" "this" {
  vpc_id = aws_vpc.primary.id
  name   = "security_group_v1"

  tags = {
    Name = "security_group_v1"
  }
}

resource "aws_security_group_rule" "ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = ["${var.ip_address}/32"]
  description       = "Allow HTTPS from home IP"
}

resource "aws_security_group_rule" "ingress_https_secondary" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = [aws_vpc_ipv4_cidr_block_association.secondary.cidr_block]
}

resource "aws_security_group_rule" "ingress_https_v2" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = [aws_vpc.primary.cidr_block]
}

# resource "aws_security_group_rule" "engress_https" {
#   type              = "egress"
#   from_port         = 443
#   to_port           = 443
#   protocol          = "tcp"
#   security_group_id = aws_security_group.this.id
#   cidr_blocks       = [aws_vpc.primary.cidr_block]
# }

# S3 Gateway Endpoint Security Group Rule
resource "aws_security_group_rule" "egress_https_vpc" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS to VPC only"
}