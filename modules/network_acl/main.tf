# ============================================================================
# Network ACL Module - Main Configuration
# ============================================================================
# このモジュールは、カスタムNetwork ACLを作成し、指定されたサブネットに関連付けます。
#
# 設計方針:
#   - 0.0.0.0/0でポート制御を行い、VPC内部CIDR特定のルールは不要
#   - NACLはステートレスなため、リクエストとレスポンスの両方向を考慮
#   - 最小権限の原則に基づき、必要なポートのみを明示的に許可
#
# 通信パターン:
#   1. VPC → インターネット: HTTPS(443), DNS(53)
#   2. インターネット → VPC: Ephemeral ports (HTTPSレスポンス)
#   3. VPC内部: HTTPS(VPCE接続), PostgreSQL(5432), DNS, ICMP
#
# ルール番号体系:
#   Ingress:
#     100-199: 主要サービスポート (HTTPS: 100, PostgreSQL: 140)
#     200-299: エフェメラル、DNS (Ephemeral: 110, DNS: 120-130)
#     300-399: ICMP (150-152)
#     400-499: 追加ルール用（予約）
#   Egress:
#     100-199: 主要サービスポート (HTTPS: 100, PostgreSQL: 130)
#     200-299: DNS (110-120)
#     300-399: ICMP (140)
#     400-499: 追加ルール用（予約）
# ============================================================================

# ============================================================================
# Network ACL リソース
# ============================================================================

resource "aws_network_acl" "this" {
  vpc_id = var.vpc_id

  tags = merge(
    {
      Name = var.nacl_name
    },
    var.tags
  )
}

# ============================================================================
# Ingressルール（受信）
# ============================================================================

# Ingressルール: HTTPS（443）を許可
# 用途:
#   - VPC内部通信: EC2/ECS → VPCエンドポイント
#   - インターネット通信: ロードバランサー等（将来の拡張用）
resource "aws_network_acl_rule" "ingress_https" {
  count = var.enable_https ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 100
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
  egress         = false
}

# Ingressルール: エフェメラルポート（HTTPSレスポンス用）
# AWS推奨範囲: 32768-65535
# 用途:
#   - VPCからのHTTPSリクエストに対するレスポンス受信
#   - Linuxカーネルデフォルト: 32768-60999
#   - Windowsデフォルト: 49152-65535
#   - NAT Gateway互換性のため、AWS推奨の全範囲を許可
resource "aws_network_acl_rule" "ingress_ephemeral" {
  count = var.enable_https ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 110
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 32768
  to_port        = 65535
  egress         = false
}

# Ingressルール: DNS TCP レスポンス
resource "aws_network_acl_rule" "ingress_dns_tcp" {
  count = var.enable_dns ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 120
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 53
  to_port        = 53
  egress         = false
}

# Ingressルール: DNS UDP レスポンス
resource "aws_network_acl_rule" "ingress_dns_udp" {
  count = var.enable_dns ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 130
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 53
  to_port        = 53
  egress         = false
}

# Ingressルール: PostgreSQL（5432）を許可
# 用途:
#   - VPC内部通信: EC2/ECS → Aurora PostgreSQL
resource "aws_network_acl_rule" "ingress_postgresql" {
  count = var.enable_postgresql ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 140
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 5432
  to_port        = 5432
  egress         = false
}

# Ingressルール: ICMPエコー応答（Pingレスポンス）
# VPCからインターネットへのPingに対する応答を受信
resource "aws_network_acl_rule" "ingress_icmp_echo_reply" {
  count = var.enable_icmp ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 150
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  icmp_type      = 0 # Echo Reply
  icmp_code      = -1
  egress         = false
}

# Ingressルール: ICMP Destination Unreachable
# Path MTU Discoveryに必須（特にCode 4: Fragmentation Needed）
resource "aws_network_acl_rule" "ingress_icmp_dest_unreachable" {
  count = var.enable_icmp ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 151
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  icmp_type      = 3 # Destination Unreachable
  icmp_code      = -1
  egress         = false
}

# Ingressルール: ICMP Time Exceeded
# tracerouteコマンドに必要
resource "aws_network_acl_rule" "ingress_icmp_time_exceeded" {
  count = var.enable_icmp ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 152
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  icmp_type      = 11 # Time Exceeded
  icmp_code      = -1
  egress         = false
}

# 追加のIngressルール
resource "aws_network_acl_rule" "additional_ingress" {
  for_each = { for rule in var.additional_ingress_rules : rule.rule_number => rule }

  network_acl_id = aws_network_acl.this.id
  rule_number    = each.value.rule_number
  protocol       = each.value.protocol
  rule_action    = each.value.rule_action
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
  icmp_type      = each.value.icmp_type
  icmp_code      = each.value.icmp_code
  egress         = false
}

# ============================================================================
# Egressルール（送信）
# ============================================================================

# Egressルール: HTTPS（443）を許可
# 用途:
#   - インターネット通信: VPC → インターネット (NAT Gateway経由)
#   - VPC内部通信: EC2/ECS → VPCエンドポイント
resource "aws_network_acl_rule" "egress_https" {
  count = var.enable_https ? 1 : 0

  network_acl_id = aws_network_acl.this.id
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
  count = var.enable_dns ? 1 : 0

  network_acl_id = aws_network_acl.this.id
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
  count = var.enable_dns ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 120
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 53
  to_port        = 53
  egress         = true
}

# Egressルール: PostgreSQL（5432）を許可
# 用途:
#   - VPC内部通信: EC2/ECS → Aurora PostgreSQL
resource "aws_network_acl_rule" "egress_postgresql" {
  count = var.enable_postgresql ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 130
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 5432
  to_port        = 5432
  egress         = true
}

# Egressルール: ICMPエコー要求（Ping送信）
# VPCからインターネットへPingを送信
resource "aws_network_acl_rule" "egress_icmp_echo_request" {
  count = var.enable_icmp ? 1 : 0

  network_acl_id = aws_network_acl.this.id
  rule_number    = 140
  protocol       = "icmp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  icmp_type      = 8 # Echo Request
  icmp_code      = -1
  egress         = true
}

# 追加のEgressルール
resource "aws_network_acl_rule" "additional_egress" {
  for_each = { for rule in var.additional_egress_rules : rule.rule_number => rule }

  network_acl_id = aws_network_acl.this.id
  rule_number    = each.value.rule_number
  protocol       = each.value.protocol
  rule_action    = each.value.rule_action
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
  icmp_type      = each.value.icmp_type
  icmp_code      = each.value.icmp_code
  egress         = true
}

# ============================================================================
# サブネット関連付け
# ============================================================================

resource "aws_network_acl_association" "this" {
  for_each = toset(var.subnet_ids)

  subnet_id      = each.value
  network_acl_id = aws_network_acl.this.id
}
