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

# Public Subnet Route Table (IGW用)
# Network Firewallからの戻りトラフィック用のルートは後から追加
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "public-rtb" }

  lifecycle {
    ignore_changes = [route]
  }
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

  # Network Firewallが作成されるまでルートを追加しない
  # ルートは aws_route.private_to_firewall で後から追加される
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

#####################################
# Security Groups
#####################################

# EC2用セキュリティグループ
module "ec2_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "nfw-demo-ec2-sg"
  description = "Security group for EC2 instance - Network Firewall demo"
  vpc_id      = aws_vpc.main.id

  # Egress: すべて許可 (Network Firewallでフィルタリング)
  egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow all outbound (filtered by Network Firewall)"
    }
  ]

  # Ingress: VPC内から許可 (SSM用)
  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      cidr_blocks = aws_vpc.main.cidr_block
      description = "Allow HTTPS from VPC for SSM"
    }
  ]

  tags = {
    Name        = "ec2-sg"
    Environment = "demo"
  }
}

# VPCエンドポイント用セキュリティグループ
module "vpc_endpoint_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "nfw-demo-vpc-endpoint-sg"
  description = "Security group for VPC Endpoints (SSM)"
  vpc_id      = aws_vpc.main.id

  # Ingress: EC2からのHTTPS接続を許可
  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "https-443-tcp"
      source_security_group_id = module.ec2_security_group.security_group_id
      description              = "Allow HTTPS from EC2"
    }
  ]

  number_of_computed_ingress_with_source_security_group_id = 1

  tags = {
    Name        = "vpc-endpoint-sg"
    Environment = "demo"
  }
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
  vpc_security_group_ids      = [module.ec2_security_group.security_group_id]
  associate_public_ip_address = false
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2を強制
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name        = "firewall-test-ec2"
    Environment = "demo"
  }
}

#####################################
# VPC Endpoints for SSM
#####################################

locals {
  # SSM VPCエンドポイント用
  endpoints = {
    ssm         = "com.amazonaws.ap-northeast-1.ssm"
    ssmmessages = "com.amazonaws.ap-northeast-1.ssmmessages"
    ec2messages = "com.amazonaws.ap-northeast-1.ec2messages"
  }

  # Network FirewallのエンドポイントIDを取得
  # Network Firewallは各AZにエンドポイントを作成する
  # この環境では1つのAZ (ap-northeast-1a) のみを使用しているため、
  # sync_statesから最初のエンドポイントIDを取得
  firewall_endpoint_id = try(
    values(aws_networkfirewall_firewall.main.firewall_status[0].sync_states)[0].attachment[0].endpoint_id,
    null
  )
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = local.endpoints
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [module.vpc_endpoint_security_group.security_group_id]
  private_dns_enabled = true

  tags = {
    Name        = "ssm-${each.key}-endpoint"
    Environment = "demo"
  }
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
# Data Sources
#####################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#####################################
# S3 Bucket for Network Firewall Logs
#####################################

module "s3_firewall_logs" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "nfw-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # バージョニング
  versioning = {
    enabled = true
  }

  # 暗号化
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # パブリックアクセスブロック
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # ライフサイクルルール (ログ保持期間90日)
  lifecycle_rule = [
    {
      id      = "log-expiration"
      enabled = true

      expiration = {
        days = 90
      }

      noncurrent_version_expiration = {
        days = 30
      }
    }
  ]

  tags = {
    Name        = "network-firewall-logs"
    Environment = "demo"
    Purpose     = "network-firewall-logging"
  }
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
# Network Firewall Logging Configuration
#####################################

resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {
    # ALERTログ: ルールにマッチしたトラフィックの詳細
    log_destination_config {
      log_destination = {
        bucketName = module.s3_firewall_logs.s3_bucket_id
        prefix     = "alert"
      }
      log_destination_type = "S3"
      log_type             = "ALERT"
    }

    # FLOWログ: すべてのトラフィックフロー情報
    log_destination_config {
      log_destination = {
        bucketName = module.s3_firewall_logs.s3_bucket_id
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
module "s3_athena_results" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "athena-results-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # 暗号化
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # パブリックアクセスブロック
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # ライフサイクルルール (クエリ結果は30日で削除)
  lifecycle_rule = [
    {
      id      = "query-results-expiration"
      enabled = true

      expiration = {
        days = 30
      }
    }
  ]

  tags = {
    Name        = "athena-query-results"
    Environment = "demo"
    Purpose     = "athena-query-results"
  }
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
      output_location = "s3://${module.s3_athena_results.s3_bucket_id}/query-results/"

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

# Private Subnet → Firewall Endpoint へのルート
# EC2からのすべてのインターネット向けトラフィックをFirewallに送る
resource "aws_route" "private_to_firewall" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_id

  depends_on = [aws_networkfirewall_firewall.main]
}

# IGW Edge Association (インターネットからの戻りトラフィック用)
# インターネット → IGW → Firewall → Private Subnet の経路を確立
# 注意: IGWにEdge Associationを設定することで、
# インターネットからの戻りパケットをPrivate Subnetに直接送らず、
# 必ずFirewallを経由させることができます
resource "aws_route" "igw_to_firewall" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = aws_subnet.private.cidr_block
  vpc_endpoint_id        = local.firewall_endpoint_id

  depends_on = [aws_networkfirewall_firewall.main]
}

#####################################
# Outputs
#####################################

output "firewall_endpoint_id" {
  description = "Network Firewall Endpoint ID"
  value       = local.firewall_endpoint_id
}

output "ec2_instance_id" {
  description = "EC2 Instance ID for SSM connection"
  value       = aws_instance.test.id
}

output "s3_log_bucket" {
  description = "S3 bucket for Network Firewall logs"
  value       = module.s3_firewall_logs.s3_bucket_id
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
    aws s3 ls s3://${module.s3_firewall_logs.s3_bucket_id}/alert/ --recursive

    # FLOWログの確認
    aws s3 ls s3://${module.s3_firewall_logs.s3_bucket_id}/flow/ --recursive


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
    LOCATION 's3://${module.s3_firewall_logs.s3_bucket_id}/alert/'
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
    LOCATION 's3://${module.s3_firewall_logs.s3_bucket_id}/flow/'
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
