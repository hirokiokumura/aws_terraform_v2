variable "name" {
  description = "セキュリティグループの名前"
  type        = string
}

variable "description" {
  description = "セキュリティグループの説明"
  type        = string
  default     = "Managed by Terraform"
}

variable "vpc_id" {
  description = "セキュリティグループを作成するVPC ID"
  type        = string
}

variable "ingress_with_cidr_blocks" {
  description = "CIDR ブロックを使用したIngressルールのリスト"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = string
    description = optional(string)
  }))
  default = []
}

variable "egress_with_cidr_blocks" {
  description = "CIDR ブロックを使用したEgressルールのリスト"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = string
    description = optional(string)
  }))
  default = []
}

variable "egress_with_prefix_list_ids" {
  description = "Prefix List IDを使用したEgressルールのリスト"
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    prefix_list_ids = string
    description     = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "リソースに付与するタグ"
  type        = map(string)
  default     = {}
}
