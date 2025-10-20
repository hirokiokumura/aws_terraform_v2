variable "vpc_id" {
  description = "VPCエンドポイントを作成するVPCのID"
  type        = string
}

variable "endpoints" {
  description = <<-EOT
    作成するVPCエンドポイントのマップ。
    キー: エンドポイントの識別子
    値: {
      name         = エンドポイント名（タグに使用）
      service_name = AWSサービス名（例: com.amazonaws.ap-northeast-1.s3）
      type         = エンドポイントタイプ（"Gateway" または "Interface"）
      private_dns_enabled = プライベートDNSを有効化するか（Interface型の場合のみ、オプション、デフォルト: true）
      additional_tags = 追加のタグ（オプション）
    }
  EOT
  type = map(object({
    name                = string
    service_name        = string
    type                = string
    private_dns_enabled = optional(bool, true)
    additional_tags     = optional(map(string), {})
  }))
}

variable "route_table_ids" {
  description = "Gateway型エンドポイントに関連付けるルートテーブルIDのリスト"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "Interface型エンドポイントに関連付けるサブネットIDのリスト"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Interface型エンドポイントに関連付けるセキュリティグループIDのリスト"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "すべてのVPCエンドポイントに適用する共通タグ"
  type        = map(string)
  default     = {}
}
