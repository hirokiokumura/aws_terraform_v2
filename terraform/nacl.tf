# Network ACLモジュールの呼び出し
# デフォルトNACLに0.0.0.0/0のルールのみを設定
module "network_acl" {
  source = "./modules/network_acl"

  default_network_acl_id = aws_vpc.primary.default_network_acl_id
  name                   = "default-nacl"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
