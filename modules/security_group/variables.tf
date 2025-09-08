variable "name" {
  description = "Name of the security group"
  type        = string
  
  validation {
    condition     = length(var.name) <= 255 && length(var.name) > 0
    error_message = "Security group name must be between 1 and 255 characters."
  }
}

variable "description" {
  description = "Description of the security group"
  type        = string
  default     = "Managed by Terraform"
  
  validation {
    condition     = length(var.description) <= 255 && length(var.description) > 0
    error_message = "Security group description must be between 1 and 255 characters."
  }
}

variable "vpc_id" {
  description = "ID of the VPC where to create the security group"
  type        = string
  
  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier starting with 'vpc-'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "project" {
  description = "Project name for resource identification"
  type        = string
  default     = "default"
}

variable "ingress_rules" {
  description = "List of ingress rules to create"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
  
  validation {
    condition = alltrue([
      for rule in var.ingress_rules : 
      rule.from_port >= 0 && rule.from_port <= 65535 &&
      rule.to_port >= 0 && rule.to_port <= 65535 &&
      rule.from_port <= rule.to_port &&
      contains(["tcp", "udp", "icmp", "-1"], rule.protocol)
    ])
    error_message = "Invalid port range or protocol in ingress rules. Ports must be 0-65535, from_port <= to_port, and protocol must be tcp, udp, icmp, or -1."
  }
}

variable "egress_rules" {
  description = "List of egress rules to create"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
  
  validation {
    condition = alltrue([
      for rule in var.egress_rules : 
      rule.from_port >= 0 && rule.from_port <= 65535 &&
      rule.to_port >= 0 && rule.to_port <= 65535 &&
      rule.from_port <= rule.to_port &&
      contains(["tcp", "udp", "icmp", "-1"], rule.protocol)
    ])
    error_message = "Invalid port range or protocol in egress rules. Ports must be 0-65535, from_port <= to_port, and protocol must be tcp, udp, icmp, or -1."
  }
}

variable "tags" {
  description = "Additional tags to apply to the security group"
  type        = map(string)
  default     = {}
}