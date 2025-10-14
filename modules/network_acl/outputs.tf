# ============================================================================
# Network ACL Module - Outputs
# ============================================================================

output "network_acl_id" {
  description = "作成されたNetwork ACLのID"
  value       = aws_network_acl.this.id
}

output "network_acl_arn" {
  description = "作成されたNetwork ACLのARN"
  value       = aws_network_acl.this.arn
}

output "subnet_associations" {
  description = "サブネットとNACLの関連付けリスト"
  value = {
    for k, v in aws_network_acl_association.this : k => {
      subnet_id      = v.subnet_id
      network_acl_id = v.network_acl_id
    }
  }
}
