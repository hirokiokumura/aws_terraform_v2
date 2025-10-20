output "gateway_endpoint_ids" {
  description = "作成されたゲートウェイ型VPCエンドポイントのIDマップ"
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "gateway_endpoint_arns" {
  description = "作成されたゲートウェイ型VPCエンドポイントのARNマップ"
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.arn }
}

output "interface_endpoint_ids" {
  description = "作成されたインターフェース型VPCエンドポイントのIDマップ"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "interface_endpoint_arns" {
  description = "作成されたインターフェース型VPCエンドポイントのARNマップ"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.arn }
}

output "interface_endpoint_dns_entries" {
  description = "作成されたインターフェース型VPCエンドポイントのDNSエントリマップ"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.dns_entry }
}

output "interface_endpoint_network_interface_ids" {
  description = "作成されたインターフェース型VPCエンドポイントのネットワークインターフェースIDマップ"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.network_interface_ids }
}

output "all_endpoint_ids" {
  description = "すべてのVPCエンドポイント（ゲートウェイ型とインターフェース型）のIDマップ"
  value = merge(
    { for k, v in aws_vpc_endpoint.gateway : k => v.id },
    { for k, v in aws_vpc_endpoint.interface : k => v.id }
  )
}
