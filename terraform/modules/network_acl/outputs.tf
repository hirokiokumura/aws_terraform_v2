output "network_acl_id" {
  description = "デフォルトNetwork ACLのID"
  value       = aws_default_network_acl.this.id
}

output "network_acl_arn" {
  description = "デフォルトNetwork ACLのARN"
  value       = aws_default_network_acl.this.arn
}
