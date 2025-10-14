# ============================================================================
# Network ACL Module - Input Variables
# ============================================================================

variable "vpc_id" {
  description = "VPCのID"
  type        = string
}

variable "subnet_ids" {
  description = "NACLを関連付けるサブネットIDのリスト"
  type        = list(string)
}

variable "nacl_name" {
  description = "Network ACLの名前"
  type        = string
  default     = "custom-nacl"
}

variable "enable_https" {
  description = "HTTPS (443) を許可するか"
  type        = bool
  default     = true
}

variable "enable_dns" {
  description = "DNS (53) を許可するか"
  type        = bool
  default     = true
}

variable "enable_postgresql" {
  description = "PostgreSQL (5432) を許可するか"
  type        = bool
  default     = false
}

variable "vpc_cidr_blocks" {
  description = "VPC CIDRブロックのリスト（PostgreSQL等のVPC内部通信専用ポート制限用）"
  type        = list(string)
  default     = []
}

variable "enable_icmp" {
  description = "ICMP (Ping, Path MTU Discovery, traceroute) を許可するか"
  type        = bool
  default     = true
}

variable "additional_ingress_rules" {
  description = "追加のIngressルール"
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = optional(number)
    to_port     = optional(number)
    icmp_type   = optional(number)
    icmp_code   = optional(number)
  }))
  default = []
}

variable "additional_egress_rules" {
  description = "追加のEgressルール"
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = optional(number)
    to_port     = optional(number)
    icmp_type   = optional(number)
    icmp_code   = optional(number)
  }))
  default = []
}

variable "tags" {
  description = "リソースに付与するタグ"
  type        = map(string)
  default     = {}
}
