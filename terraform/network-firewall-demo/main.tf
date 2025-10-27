#####################################
# Terraform Backend (S3)
#####################################

terraform {
  backend "s3" {
    bucket = "pricot1224v1-terraform"
    key    = "network-firewall-demo/terraform.tfstate"
    region = "ap-northeast-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

#####################################
# VPC
#####################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "nfw-demo-vpc" }
}

#####################################
# Subnets
#####################################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet" }
}

resource "aws_subnet" "firewall" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"
  tags              = { Name = "firewall-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags              = { Name = "private-subnet" }
}

#####################################
# Internet Gateway
#####################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "nfw-demo-igw" }
}

#####################################
# NAT Gateway (Optional - for outbound only)
#####################################

# resource "aws_eip" "nat" {
#   domain = "vpc"
#   tags   = { Name = "nfw-demo-nat-eip" }
# }
#
# resource "aws_nat_gateway" "main" {
#   allocation_id = aws_eip.nat.id
#   subnet_id     = aws_subnet.public.id
#   tags          = { Name = "nfw-demo-nat" }
# }

#####################################
# Route Tables
#####################################

# Public Subnet Route Table (IGW → Firewall Endpoint)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "public-rtb" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Firewall Subnet Route Table (Firewall → IGW)
resource "aws_route_table" "firewall" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "firewall-rtb" }
}

resource "aws_route" "firewall_to_igw" {
  route_table_id         = aws_route_table.firewall.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "firewall" {
  subnet_id      = aws_subnet.firewall.id
  route_table_id = aws_route_table.firewall.id
}

# Private Subnet Route Table (Private → Firewall Endpoint)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "private-rtb" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# This route will be added after firewall endpoint is created
# 0.0.0.0/0 -> Firewall Endpoint (added below after firewall resource)

#####################################
# Security Group
#####################################

resource "aws_security_group" "ec2" {
  name        = "ec2-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTPS and HTTP for Network Firewall domain rule test"

  # Allow all outbound traffic (Network Firewall will filter)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound from VPC (for SSM)
  ingress {
    description = "Allow all from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = { Name = "ec2-sg" }
}

#####################################
# IAM for SSM
#####################################

resource "aws_iam_role" "ssm_role" {
  name = "ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

#####################################
# EC2 Instance
#####################################

resource "aws_instance" "test" {
  ami                         = "ami-0c3fd0f5d33134a76" # Amazon Linux 2
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  security_groups             = [aws_security_group.ec2.id]
  associate_public_ip_address = false

  tags = { Name = "firewall-test-ec2" }
}

#####################################
# VPC Endpoints for SSM
#####################################

locals {
  endpoints = {
    ssm         = "com.amazonaws.ap-northeast-1.ssm"
    ssmmessages = "com.amazonaws.ap-northeast-1.ssmmessages"
    ec2messages = "com.amazonaws.ap-northeast-1.ec2messages"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = local.endpoints
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.ec2.id]
  private_dns_enabled = true
}

#####################################
# Network Firewall Rule Groups
#####################################

# --- ALLOWLIST ---
# 許可するドメイン: example.com, amazonaws.com
resource "aws_networkfirewall_rule_group" "allowlist" {
  capacity = 100
  name     = "allowlist-domain-rules"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        targets              = [".example.com", ".amazonaws.com"]
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        generated_rules_type = "ALLOWLIST"
      }
    }
  }

  tags = { Name = "allowlist-domain-rules" }
}

# --- DENYLIST ---
# 拒否するドメイン: google.com (テスト用)
resource "aws_networkfirewall_rule_group" "denylist" {
  capacity = 100
  name     = "denylist-domain-rules"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        targets              = [".google.com"]
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        generated_rules_type = "DENYLIST"
      }
    }
  }

  tags = { Name = "denylist-domain-rules" }
}

#####################################
# Firewall Policy
#####################################

resource "aws_networkfirewall_firewall_policy" "main" {
  name = "firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.allowlist.arn
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.denylist.arn
    }
  }

  tags = { Name = "firewall-policy" }
}

#####################################
# Network Firewall
#####################################

resource "aws_networkfirewall_firewall" "main" {
  name                = "vpc-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.main.id

  subnet_mapping {
    subnet_id = aws_subnet.firewall.id
  }

  tags = { Name = "nfw-demo" }
}

#####################################
# Route: Private Subnet → Firewall Endpoint
#####################################

# Firewall Endpointが作成された後にルートを追加
resource "aws_route" "private_to_firewall" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = one([for endpoint in aws_networkfirewall_firewall.main.firewall_status[0].sync_states : endpoint.attachment[0].endpoint_id])

  depends_on = [aws_networkfirewall_firewall.main]
}

# IGW Route Table: インターネットからの戻りトラフィックをFirewallに送る
resource "aws_route" "igw_to_firewall" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = aws_subnet.private.cidr_block
  vpc_endpoint_id        = one([for endpoint in aws_networkfirewall_firewall.main.firewall_status[0].sync_states : endpoint.attachment[0].endpoint_id])

  depends_on = [aws_networkfirewall_firewall.main]
}

#####################################
# Outputs
#####################################

output "firewall_endpoint_id" {
  description = "Network Firewall Endpoint ID"
  value       = one([for endpoint in aws_networkfirewall_firewall.main.firewall_status[0].sync_states : endpoint.attachment[0].endpoint_id])
}

output "ec2_instance_id" {
  description = "EC2 Instance ID for SSM connection"
  value       = aws_instance.test.id
}

output "test_commands" {
  description = "Commands to test Network Firewall domain rules"
  value       = <<-EOT
    # SSM接続
    aws ssm start-session --target ${aws_instance.test.id} --region ap-northeast-1

    # 許可されるドメイン (example.com)
    curl -I https://example.com

    # 拒否されるドメイン (google.com)
    curl -I https://google.com

    # 許可されるドメイン (amazonaws.com)
    curl -I https://aws.amazon.com

    # Network Firewallログの確認 (CloudWatch Logs)
    # ログは作成後、CloudWatch Logsで確認可能
  EOT
}
