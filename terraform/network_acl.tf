# ============================================================================
# カスタムNetwork ACL（モジュール使用）
# ============================================================================
# modules/network_aclモジュールを使用してカスタムNACLを作成し、
# すべてのサブネットに関連付けます。
#
# アーキテクチャ:
#   Primary CIDR (10.0.0.0/22): VPCエンドポイント、NAT Gateway、Aurora PostgreSQL
#   Secondary CIDR (10.1.4.0/24): EC2インスタンス、ECSタスク
#
# 通信要件:
#   1. HTTPS (443): VPC ⇄ インターネット、EC2/ECS → VPCエンドポイント
#   2. DNS (53): VPC → インターネットDNS、VPC内部DNS
#   3. PostgreSQL (5432): EC2/ECS → Aurora PostgreSQL
#   4. ICMP: Ping、Path MTU Discovery、traceroute
# ============================================================================

module "custom_nacl" {
  source = "../modules/network_acl"

  vpc_id    = aws_vpc.primary.id
  nacl_name = "custom-nacl"

  # すべてのサブネットをカスタムNACLに関連付け
  subnet_ids = [
    aws_subnet.primary_1a.id,
    aws_subnet.primary_1c.id,
    aws_subnet.secondary_1a.id,
    aws_subnet.secondary_1c.id,
  ]

  # プロトコルの有効化
  enable_https      = true # HTTPS通信を許可
  enable_dns        = true # DNS通信を許可
  enable_postgresql = true # PostgreSQL通信を許可（Aurora用）
  enable_icmp       = true # ICMP通信を許可

  # VPC内部通信専用ポート（PostgreSQL等）のCIDR制限
  vpc_cidr_blocks = [
    "10.0.0.0/22",  # Primary CIDR (VPCエンドポイント、NAT Gateway、Aurora)
    "10.1.4.0/24",  # Secondary CIDR (EC2、ECS)
  ]

  tags = {
    Name        = "custom-nacl"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# デフォルトNACLの管理
# ============================================================================
# デフォルトNACLを明示的に管理し、すべての通信を拒否します。
# これにより、誤ってデフォルトNACLに関連付けられたサブネットは通信できなくなり、
# セキュリティインシデントを防止します。

resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.primary.default_network_acl_id

  # ルールを定義しない = すべて拒否（デフォルトのdenyルールのみ）
  # これによりデフォルトNACLに誤って関連付けられたサブネットは通信できなくなる

  tags = {
    Name = "default-nacl-deny-all"
  }
}

# ============================================================================
# 出力
# ============================================================================

output "custom_nacl_id" {
  description = "カスタムNetwork ACLのID"
  value       = module.custom_nacl.network_acl_id
}

output "custom_nacl_arn" {
  description = "カスタムNetwork ACLのARN"
  value       = module.custom_nacl.network_acl_arn
}
