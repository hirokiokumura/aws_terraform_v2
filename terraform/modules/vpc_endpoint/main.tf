locals {
  # エンドポイントをタイプ別に分類
  gateway_endpoints   = { for k, v in var.endpoints : k => v if v.type == "Gateway" }
  interface_endpoints = { for k, v in var.endpoints : k => v if v.type == "Interface" }
}

# ゲートウェイ型VPCエンドポイント
resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoints

  vpc_id            = var.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"

  route_table_ids = var.route_table_ids

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    },
    lookup(each.value, "additional_tags", {})
  )
}

# インターフェース型VPCエンドポイント
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = var.security_group_ids
  private_dns_enabled = lookup(each.value, "private_dns_enabled", true)

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    },
    lookup(each.value, "additional_tags", {})
  )
}
