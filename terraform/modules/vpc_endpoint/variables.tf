variable "vpc_id" {
  description = "VPCエンドポイントを作成するVPCのID"
  type        = string
}

variable "gateway_endpoints" {
  description = <<-EOT
    作成するゲートウェイ型VPCエンドポイントのマップ。
    キー: エンドポイントの識別子
    値: {
      name            = エンドポイント名（タグに使用）
      service_name    = AWSサービス名（例: com.amazonaws.ap-northeast-1.s3）
      additional_tags = 追加のタグ（オプション）
    }
  EOT
  type = map(object({
    name            = string
    service_name    = string
    additional_tags = optional(map(string), {})
  }))
  default = {}
}

variable "interface_endpoints" {
  description = <<-EOT
    作成するインターフェース型VPCエンドポイントのマップ。
    キー: エンドポイントの識別子
    値: {
      name                = エンドポイント名（タグに使用）
      service_name        = AWSサービス名（例: com.amazonaws.ap-northeast-1.ssm）
      security_group_ids  = セキュリティグループIDのリスト（オプション、指定しない場合はモジュールレベルのデフォルト値を使用）
      private_dns_enabled = プライベートDNSを有効化するか（オプション、デフォルト: true）
      additional_tags     = 追加のタグ（オプション）
    }
  EOT
  type = map(object({
    name                = string
    service_name        = string
    security_group_ids  = optional(list(string))
    private_dns_enabled = optional(bool, true)
    additional_tags     = optional(map(string), {})
  }))
  default = {}
}

variable "gateway_route_table_ids" {
  description = "ゲートウェイ型エンドポイントに関連付けるルートテーブルIDのリスト"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "インターフェース型エンドポイントに関連付けるサブネットIDのリスト"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "インターフェース型エンドポイントに関連付けるデフォルトのセキュリティグループIDのリスト（各エンドポイントで個別に指定しない場合に使用）"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "すべてのVPCエンドポイントに適用する共通タグ"
  type        = map(string)
  default     = {}
}
