# ゲートウェイ型VPCエンドポイント
resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_endpoints

  vpc_id            = var.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"

  route_table_ids = var.gateway_route_table_ids

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    },
    each.value.additional_tags
  )
}

# インターフェース型VPCエンドポイント
resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_endpoints

  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = var.security_group_ids
  private_dns_enabled = each.value.private_dns_enabled

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    },
    each.value.additional_tags
  )
}
