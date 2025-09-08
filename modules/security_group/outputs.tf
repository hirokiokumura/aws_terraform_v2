output "security_group_id" {
  description = "セキュリティグループのID"
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "セキュリティグループのARN"
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "セキュリティグループの名前"
  value       = aws_security_group.this.name
}