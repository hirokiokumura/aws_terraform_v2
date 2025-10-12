# ============================================================================
# カスタムネットワークACL
# ============================================================================
# ルール番号体系:
#   Ingress:
#     50-89:   VPC内部通信 (Primary CIDR: 50, Secondary CIDR: 51)
#     90-99:   ICMP (Echo Reply: 90)
#     100-199: インターネットからの特定サービス (HTTPS: 100)
#     200-299: エフェメラルポート、DNS応答など
#   Egress:
#     50-89:   VPC内部通信 (Primary CIDR: 50, Secondary CIDR: 51)
#     90-99:   ICMP (Echo Request: 90)
#     100-199: インターネットへの特定サービス (HTTPS: 100, DNS: 110-120)
#     200-299: エフェメラルポート、その他
# ============================================================================

resource "aws_network_acl" "custom" {
  vpc_id = aws_vpc.primary.id

  tags = {
    Name = "custom-nacl"
  }
}

# ============================================================================
# Ingressルール: VPC内部通信
# ============================================================================
# 注意: VPCエンドポイント（S3 Gateway等）経由の通信もVPC内部通信として扱われるため、
#       これらのルールでカバーされます

# Ingressルール: VPC内部通信（Primary CIDR）
resource "aws_network_acl_rule" "ingress_vpc_primary" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 50
  protocol       = "-1"  # All protocols
  rule_action    = "allow"
  cidr_block     = "10.0.0.0/22"
  egress         = false
}

# Ingressルール: VPC内部通信（Secondary CIDR）
resource "aws_network_acl_rule" "ingress_vpc_secondary" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 51
  protocol       = "-1"  # All protocols
  rule_action    = "allow"
  cidr_block     = "10.1.4.0/24"
  egress         = false
}

# ============================================================================
# Ingressルール: インターネットからの通信
# ============================================================================

# Ingressルール: ICMPエコー応答（Pingレスポンス）
# VPCからインターネットへのPingに対する応答を受信
resource "aws_network_acl_rule" "ingress_icmp_echo_reply" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 90
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  icmp_type      = 0  # Echo Reply
  icmp_code      = -1
  egress         = false
}

# Ingressルール: HTTPS（443）を許可
resource "aws_network_acl_rule" "ingress_https" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
  egress         = false
}

# Ingressルール: エフェメラルポート（HTTPSレスポンス用）
# Linuxカーネルデフォルト: 32768-60999 を使用
# セキュリティのため、必要最小限の範囲に限定
resource "aws_network_acl_rule" "ingress_ephemeral" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 200
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 32768
  to_port        = 60999
  egress         = false
}

# Ingressルール: DNS TCP レスポンス
resource "aws_network_acl_rule" "ingress_dns_tcp" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 210
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 53
  to_port        = 53
  egress         = false
}

# Ingressルール: DNS UDP レスポンス
resource "aws_network_acl_rule" "ingress_dns_udp" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 220
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 53
  to_port        = 53
  egress         = false
}

# ============================================================================
# Egressルール: VPC内部通信
# ============================================================================
# 注意: VPCエンドポイント（S3 Gateway等）経由の通信もVPC内部通信として扱われるため、
#       これらのルールでカバーされます

# Egressルール: VPC内部通信（Primary CIDR）
resource "aws_network_acl_rule" "egress_vpc_primary" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 50
  protocol       = "-1"  # All protocols
  rule_action    = "allow"
  cidr_block     = "10.0.0.0/22"
  egress         = true
}

# Egressルール: VPC内部通信（Secondary CIDR）
resource "aws_network_acl_rule" "egress_vpc_secondary" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 51
  protocol       = "-1"  # All protocols
  rule_action    = "allow"
  cidr_block     = "10.1.4.0/24"
  egress         = true
}

# ============================================================================
# Egressルール: インターネットへの通信
# ============================================================================

# Egressルール: ICMPエコー要求（Ping送信）
# VPCからインターネットへPingを送信
resource "aws_network_acl_rule" "egress_icmp_echo_request" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 90
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  icmp_type      = 8  # Echo Request
  icmp_code      = -1
  egress         = true
}

# Egressルール: HTTPS（443）を許可
resource "aws_network_acl_rule" "egress_https" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
  egress         = true
}

# Egressルール: DNS TCP（53）を許可
resource "aws_network_acl_rule" "egress_dns_tcp" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 110
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 53
  to_port        = 53
  egress         = true
}

# Egressルール: DNS UDP（53）を許可
resource "aws_network_acl_rule" "egress_dns_udp" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 120
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 53
  to_port        = 53
  egress         = true
}

# Egressルール: エフェメラルポート（HTTPSリクエスト送信用）
# クライアントからHTTPSリクエストを送信する際、送信元ポートとしてエフェメラルポートを使用
# Linuxカーネルデフォルト: 32768-60999 を使用
resource "aws_network_acl_rule" "egress_ephemeral" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 200
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 32768
  to_port        = 60999
  egress         = true
}

# サブネットにカスタムNACLを関連付け
resource "aws_network_acl_association" "primary_1a" {
  subnet_id      = aws_subnet.primary_1a.id
  network_acl_id = aws_network_acl.custom.id
}

resource "aws_network_acl_association" "primary_1c" {
  subnet_id      = aws_subnet.primary_1c.id
  network_acl_id = aws_network_acl.custom.id
}

resource "aws_network_acl_association" "secondary_1a" {
  subnet_id      = aws_subnet.secondary_1a.id
  network_acl_id = aws_network_acl.custom.id
}

resource "aws_network_acl_association" "secondary_1c" {
  subnet_id      = aws_subnet.secondary_1c.id
  network_acl_id = aws_network_acl.custom.id
}

# デフォルトNACLを明示的に管理（すべて拒否に設定）
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.primary.default_network_acl_id

  # ルールを定義しない = すべて拒否（デフォルトのdenyルールのみ）
  # これによりデフォルトNACLに誤って関連付けられたサブネットは通信できなくなる

  tags = {
    Name = "default-nacl-deny-all"
  }
}
