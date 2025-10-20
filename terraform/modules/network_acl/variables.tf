variable "default_network_acl_id" {
  description = "VPCのデフォルトNetwork ACL ID"
  type        = string
}

variable "name" {
  description = "デフォルトNetwork ACLの名前タグ"
  type        = string
  default     = "default-nacl"
}

variable "tags" {
  description = "デフォルトNetwork ACLに適用する共通タグ"
  type        = map(string)
  default     = {}
}
