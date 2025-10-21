# セキュリティグループモジュール
# terraform-aws-modules/security-group/awsを使用

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  # Ingressルール
  ingress_with_cidr_blocks = concat(
    var.ingress_with_cidr_blocks,
    var.additional_ingress_rules
  )

  # Egressルール
  egress_with_cidr_blocks = var.egress_with_cidr_blocks

  # Prefix Listを使用したEgressルール
  egress_with_prefix_list_ids = var.egress_with_prefix_list_ids

  tags = var.tags
}
