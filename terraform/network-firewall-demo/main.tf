#####################################
# Terraform Backend (S3)
#####################################

terraform {
  backend "s3" {
    bucket = "apricot1224v1-terraform"
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
  name        = "nfw-demo-ec2-sg"
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
  name = "nfw-demo-ec2-ssm-role"

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
  name = "nfw-demo-ec2-ssm-profile"
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
# S3 Bucket for Network Firewall Logs
#####################################

resource "aws_s3_bucket" "firewall_logs" {
  bucket = "nfw-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  tags = { Name = "network-firewall-logs" }
}

resource "aws_s3_bucket_versioning" "firewall_logs" {
  bucket = aws_s3_bucket.firewall_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firewall_logs" {
  bucket = aws_s3_bucket.firewall_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "firewall_logs" {
  bucket = aws_s3_bucket.firewall_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Data sources for S3 bucket naming
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
# Network Firewall Logging Configuration
#####################################

resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {
    # ALERTログ: ルールにマッチしたトラフィックの詳細
    log_destination_config {
      log_destination = {
        bucketName = aws_s3_bucket.firewall_logs.id
        prefix     = "alert"
      }
      log_destination_type = "S3"
      log_type             = "ALERT"
    }

    # FLOWログ: すべてのトラフィックフロー情報
    log_destination_config {
      log_destination = {
        bucketName = aws_s3_bucket.firewall_logs.id
        prefix     = "flow"
      }
      log_destination_type = "S3"
      log_type             = "FLOW"
    }
  }
}

#####################################
# Athena for Log Analysis
#####################################

# Athena結果格納用S3バケット
resource "aws_s3_bucket" "athena_results" {
  bucket = "athena-results-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  tags = { Name = "athena-query-results" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Athenaデータベース
resource "aws_glue_catalog_database" "firewall_logs" {
  name        = "network_firewall_logs"
  description = "Database for Network Firewall logs analysis"
}

# Athenaワークグループ
resource "aws_athena_workgroup" "firewall_analysis" {
  name = "network-firewall-analysis"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = { Name = "network-firewall-analysis" }
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

output "s3_log_bucket" {
  description = "S3 bucket for Network Firewall logs"
  value       = aws_s3_bucket.firewall_logs.id
}

output "athena_database" {
  description = "Athena database name for log analysis"
  value       = aws_glue_catalog_database.firewall_logs.name
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.firewall_analysis.name
}

output "test_commands" {
  description = "Commands to test Network Firewall domain rules and analyze logs"
  value       = <<-EOT
    ### 1. ドメインルールのテスト ###

    # SSM接続
    aws ssm start-session --target ${aws_instance.test.id} --region ap-northeast-1

    # 許可されるドメイン (example.com) - 成功するはず
    curl -I https://example.com

    # 拒否されるドメイン (google.com) - タイムアウトするはず
    curl -I https://google.com

    # 許可されるドメイン (amazonaws.com) - 成功するはず
    curl -I https://aws.amazon.com


    ### 2. S3ログの確認 ###

    # ALERTログの確認
    aws s3 ls s3://${aws_s3_bucket.firewall_logs.id}/alert/ --recursive

    # FLOWログの確認
    aws s3 ls s3://${aws_s3_bucket.firewall_logs.id}/flow/ --recursive


    ### 3. Athenaでログ分析 ###

    # 以下のDDLをAthenaで実行してテーブル作成
    # ワークグループ: ${aws_athena_workgroup.firewall_analysis.name}
    # データベース: ${aws_glue_catalog_database.firewall_logs.name}
  EOT
}

output "athena_ddl_alert" {
  description = "Athena DDL to create ALERT logs table"
  value       = <<-EOT
    CREATE EXTERNAL TABLE IF NOT EXISTS ${aws_glue_catalog_database.firewall_logs.name}.alert_logs (
      firewall_name string,
      availability_zone string,
      event_timestamp bigint,
      event struct<
        timestamp:string,
        flow_id:bigint,
        event_type:string,
        src_ip:string,
        src_port:int,
        dest_ip:string,
        dest_port:int,
        proto:string,
        alert:struct<
          action:string,
          signature_id:bigint,
          rev:bigint,
          signature:string,
          category:string,
          severity:bigint
        >
      >
    )
    ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
    LOCATION 's3://${aws_s3_bucket.firewall_logs.id}/alert/'
  EOT
}

output "athena_ddl_flow" {
  description = "Athena DDL to create FLOW logs table"
  value       = <<-EOT
    CREATE EXTERNAL TABLE IF NOT EXISTS ${aws_glue_catalog_database.firewall_logs.name}.flow_logs (
      firewall_name string,
      availability_zone string,
      event_timestamp bigint,
      event struct<
        timestamp:string,
        flow_id:bigint,
        event_type:string,
        src_ip:string,
        src_port:int,
        dest_ip:string,
        dest_port:int,
        proto:string,
        netflow:struct<
          pkts:bigint,
          bytes:bigint,
          start:string,
          end:string,
          age:bigint,
          min_ttl:bigint,
          max_ttl:bigint
        >
      >
    )
    ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
    LOCATION 's3://${aws_s3_bucket.firewall_logs.id}/flow/'
  EOT
}

output "athena_sample_queries" {
  description = "Sample Athena queries for log analysis"
  value       = <<-EOT
    -- 拒否されたドメイン(ALERT)の確認
    SELECT
      from_unixtime(event_timestamp) as timestamp,
      event.src_ip,
      event.dest_ip,
      event.dest_port,
      event.alert.signature,
      event.alert.action
    FROM ${aws_glue_catalog_database.firewall_logs.name}.alert_logs
    WHERE event.alert.action = 'blocked'
    ORDER BY event_timestamp DESC
    LIMIT 100;

    -- トラフィックフロー(FLOW)の統計
    SELECT
      event.dest_ip,
      event.dest_port,
      event.proto,
      COUNT(*) as connection_count,
      SUM(event.netflow.bytes) as total_bytes,
      SUM(event.netflow.pkts) as total_packets
    FROM ${aws_glue_catalog_database.firewall_logs.name}.flow_logs
    GROUP BY event.dest_ip, event.dest_port, event.proto
    ORDER BY total_bytes DESC
    LIMIT 20;

    -- 時間帯別トラフィック分析
    SELECT
      date_trunc('hour', from_unixtime(event_timestamp)) as hour,
      COUNT(*) as flow_count,
      SUM(event.netflow.bytes) as total_bytes
    FROM ${aws_glue_catalog_database.firewall_logs.name}.flow_logs
    GROUP BY date_trunc('hour', from_unixtime(event_timestamp))
    ORDER BY hour DESC;
  EOT
}
