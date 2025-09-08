resource "awscc_ec2_security_group" "this" {
  group_name        = var.name
  group_description = var.description
  vpc_id            = var.vpc_id

  tags = local.tags_list
}

resource "awscc_ec2_security_group_ingress" "this" {
  count = length(var.ingress_rules)

  group_id    = awscc_ec2_security_group.this.group_id
  from_port   = var.ingress_rules[count.index].from_port
  to_port     = var.ingress_rules[count.index].to_port
  ip_protocol = var.ingress_rules[count.index].protocol
  cidr_ip     = length(var.ingress_rules[count.index].cidr_blocks) > 0 ? var.ingress_rules[count.index].cidr_blocks[0] : null
  description = var.ingress_rules[count.index].description
}

resource "awscc_ec2_security_group_egress" "this" {
  count = length(var.egress_rules)

  group_id    = awscc_ec2_security_group.this.group_id
  from_port   = var.egress_rules[count.index].from_port
  to_port     = var.egress_rules[count.index].to_port
  ip_protocol = var.egress_rules[count.index].protocol
  cidr_ip     = length(var.egress_rules[count.index].cidr_blocks) > 0 ? var.egress_rules[count.index].cidr_blocks[0] : null
  description = var.egress_rules[count.index].description
}

locals {
  default_tags = {
    Name        = var.name
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "Terraform"
  }
  
  merged_tags = merge(local.default_tags, var.tags)
  
  tags_list = [
    for key, value in local.merged_tags : {
      key   = key
      value = value
    }
  ]
}