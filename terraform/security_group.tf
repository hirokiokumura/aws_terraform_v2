resource "aws_security_group" "this" {
  vpc_id = aws_vpc.primary.id
  name   = "security_group_v1"

  tags = {
    Name = "security_group_v1"
  }
}

resource "aws_security_group_rule" "private_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = ["${var.ip_address}/32"]
  description       = "Allow HTTPS from home IP"
}