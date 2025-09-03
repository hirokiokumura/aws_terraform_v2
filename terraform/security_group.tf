resource "aws_security_group" "this" {
  vpc_id = aws_vpc.primary.id
  name   = "internal-https-sg"

  tags = {
    Name = "internal-https-sg"
  }
}

resource "aws_security_group_rule" "ingress_https_from_admin_ip" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = ["${var.ip_address}/32"]
  description       = "Allow HTTPS from admin IP"
}

resource "aws_security_group_rule" "ingress_https_from_secondary_vpc" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = [aws_vpc_ipv4_cidr_block_association.secondary.cidr_block]
  description       = "Allow HTTPS from secondary VPC CIDR"
}

resource "aws_security_group_rule" "ingress_https_from_primary_vpc" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = [aws_vpc.primary.cidr_block]
  description       = "Allow HTTPS from primary VPC CIDR"
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
resource "aws_security_group_rule" "egress_https_s3" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  prefix_list_ids   = [data.aws_prefix_list.s3.id]
  description       = "Allow HTTPS to S3 via VPC Gateway Endpoint"
}

# Data source for S3 prefix list
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.ap-northeast-1.s3"
}