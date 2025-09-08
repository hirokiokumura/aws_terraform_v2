output "security_group_id" {
  description = "The ID of the security group"
  value       = awscc_ec2_security_group.this.group_id
}

output "security_group_name" {
  description = "The name of the security group"
  value       = awscc_ec2_security_group.this.group_name
}

output "security_group_arn" {
  description = "The ARN of the security group"
  value       = "arn:aws:ec2:*:*:security-group/${awscc_ec2_security_group.this.group_id}"
}

output "vpc_id" {
  description = "The VPC ID where the security group is created"
  value       = awscc_ec2_security_group.this.vpc_id
}