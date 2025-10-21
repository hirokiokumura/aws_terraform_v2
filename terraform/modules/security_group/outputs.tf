output "security_group_id" {
  description = "セキュリティグループのID"
  value       = module.security_group.security_group_id
}

output "security_group_arn" {
  description = "セキュリティグループのARN"
  value       = module.security_group.security_group_arn
}

output "security_group_name" {
  description = "セキュリティグループの名前"
  value       = module.security_group.security_group_name
}

output "security_group_vpc_id" {
  description = "セキュリティグループが属するVPC ID"
  value       = module.security_group.security_group_vpc_id
}
