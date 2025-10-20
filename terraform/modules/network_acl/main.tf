# デフォルトNACLを管理
# 0.0.0.0/0のルールのみを設定
resource "aws_default_network_acl" "this" {
  default_network_acl_id = var.default_network_acl_id

  # Ingressルール: ICMPエコー応答（Pingレスポンス）
  ingress {
    rule_no    = 90
    protocol   = "icmp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    icmp_type  = 0 # Echo Reply
    icmp_code  = -1
  }

  # Ingressルール: ICMP Destination Unreachable（Path MTU Discovery用）
  ingress {
    rule_no    = 91
    protocol   = "icmp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    icmp_type  = 3 # Destination Unreachable
    icmp_code  = -1
  }

  # Ingressルール: ICMP Time Exceeded（traceroute用）
  ingress {
    rule_no    = 92
    protocol   = "icmp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    icmp_type  = 11 # Time Exceeded
    icmp_code  = -1
  }

  # Ingressルール: HTTPS
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Ingressルール: エフェメラルポート（HTTPSレスポンス用）
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }

  # Ingressルール: DNS TCP レスポンス
  ingress {
    rule_no    = 210
    protocol   = "tcp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  # Ingressルール: DNS UDP レスポンス
  ingress {
    rule_no    = 220
    protocol   = "udp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  # Egressルール: ICMPエコー要求（Ping送信）
  egress {
    rule_no    = 90
    protocol   = "icmp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    icmp_type  = 8 # Echo Request
    icmp_code  = -1
  }

  # Egressルール: HTTPS
  egress {
    rule_no    = 100
    protocol   = "tcp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Egressルール: DNS TCP
  egress {
    rule_no    = 110
    protocol   = "tcp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  # Egressルール: DNS UDP
  egress {
    rule_no    = 120
    protocol   = "udp"
    rule_action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}
