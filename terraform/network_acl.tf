# ============================================================================
# カスタムネットワークACL
# ============================================================================
# ルール番号体系:
#   Ingress:
#     100-199: 特定サービス用 (HTTPS: 100, SSH: 110など)
#     200-299: エフェメラルポート、DNS応答など
#   Egress:
#     100-199: 特定サービス用 (HTTPS: 100, DNS: 110-120など)
#     200-299: エフェメラルポート、その他
# ============================================================================

resource "aws_network_acl" "custom" {
  vpc_id = aws_vpc.primary.id

  tags = {
    Name = "custom-nacl"
  }
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
# Linuxカーネルデフォルト: 32768-60999
# Windowsデフォルト: 49152-65535
# 両方をカバーするため32768-65535を許可
resource "aws_network_acl_rule" "ingress_ephemeral" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 200
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 32768
  to_port        = 65535
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
resource "aws_network_acl_rule" "egress_ephemeral" {
  network_acl_id = aws_network_acl.custom.id
  rule_number    = 200
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 32768
  to_port        = 65535
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
