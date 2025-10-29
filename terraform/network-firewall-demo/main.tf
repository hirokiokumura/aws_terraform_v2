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
# Variables
#####################################

variable "availability_zone" {
  description = "Availability Zone for all resources"
  type        = string
  default     = "ap-northeast-1a"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/22"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "firewall_subnet_cidr" {
  description = "CIDR block for firewall subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "s3_log_expiration_days" {
  description = "S3 log expiration period in days"
  type        = number
  default     = 90
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "network-firewall-demo"
}

variable "ec2_ami_id" {
  description = "AMI ID for EC2 instance (Amazon Linux 2023 recommended)"
  type        = string
  # デフォルト: ap-northeast-1リージョンのAmazon Linux 2023最新安定版
  # 他リージョンで使用する場合は、terraform.tfvarsで上書きしてください
  # 最新AMI ID確認方法:
  # aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" --region ap-northeast-1
  default = "ami-0091f05e4b8ee6709" # Amazon Linux 2023 (ap-northeast-1, 2024-01時点)
}

#####################################
# VPC
#####################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

#####################################
# Subnets
#####################################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-public-subnet"
    AZ   = var.availability_zone
  }
}

resource "aws_subnet" "firewall" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.firewall_subnet_cidr
  availability_zone = var.availability_zone
  tags = {
    Name = "${var.project_name}-firewall-subnet"
    AZ   = var.availability_zone
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
  tags = {
    Name = "${var.project_name}-private-subnet"
    AZ   = var.availability_zone
  }
}

#####################################
# Internet Gateway
#####################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "nfw-demo-igw" }
}

# IGW Route Table (Edge Association)
# IGWからPrivate Subnetへの戻りトラフィックをFirewall Endpointに転送
resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "igw-rtb" }
}

# IGW → Firewall Endpoint へのルート（Private Subnet宛て）
# インターネットからの戻りトラフィック（レスポンス）をFirewall経由でPrivate Subnetに転送
resource "aws_route" "igw_to_firewall" {
  count = local.firewall_endpoint_id != null ? 1 : 0

  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.private_subnet_cidr
  vpc_endpoint_id        = local.firewall_endpoint_id

  # タイミング問題を防ぐため、Firewall作成とIGW作成の両方を明示的に待機
  depends_on = [
    aws_networkfirewall_firewall.main,
    aws_internet_gateway.main
  ]
}

# IGWルートテーブルをIGWにアタッチ
resource "aws_route_table_association" "igw" {
  count = local.firewall_endpoint_id != null ? 1 : 0

  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw.id

  # IGWルート作成後にアタッチする
  depends_on = [
    aws_route.igw_to_firewall
  ]
}

#####################################
# NAT Gateway (Required for Private Subnet internet access)
#####################################
# NAT Gateway: Private Subnetからインターネットへのアウトバウンド通信を可能にする
# Network Firewallを経由したトラフィックをインターネットに転送する際、
# プライベートIPアドレスをパブリックIPアドレスに変換する役割を担う
#
# 通信経路:
# Private Subnet (EC2) → Firewall Endpoint → Firewall Subnet → NAT Gateway → IGW → Internet

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nfw-demo-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  # NAT GatewayはPublic Subnetに配置し、IGWへのルートが必要
  depends_on = [aws_internet_gateway.main]

  tags = { Name = "nfw-demo-nat" }
}

#####################################
# Route Tables
#####################################

# Public Subnet Route Table
# すべてのルートはaws_routeリソースで個別管理
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "public-rtb" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Public Subnet → IGW へのルート
# NAT Gatewayからのアウトバウンドトラフィックをインターネットへ転送
resource "aws_route" "public_to_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Firewall Subnet Route Table
# すべてのルートはaws_routeリソースで個別管理
resource "aws_route_table" "firewall" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "firewall-rtb" }
}

# Firewall Subnet → NAT Gateway へのルート
# Network Firewallで検査済みのトラフィックをNAT Gatewayに転送
# NAT GatewayがプライベートIPをパブリックIPに変換してからIGWへ転送
resource "aws_route" "firewall_to_nat" {
  route_table_id         = aws_route_table.firewall.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "firewall" {
  subnet_id      = aws_subnet.firewall.id
  route_table_id = aws_route_table.firewall.id
}

# Private Subnet Route Table
# すべてのルートはaws_routeリソースで個別管理
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "private-rtb" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Private Subnet → Firewall Endpoint へのルートは
# 782行目付近に定義されています

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

#####################################
# VPC Endpoint Security Group
#####################################

module "vpc_endpoint_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "vpc-endpoint-sg"
  description = "Security group for VPC endpoints (SSM, EC2messages, SSMmessages)"
  vpc_id      = aws_vpc.main.id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = aws_vpc.main.cidr_block
      description = "Allow HTTPS from VPC for VPC endpoints"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow all outbound traffic"
    }
  ]

  tags = {
    Name        = "vpc-endpoint-sg"
    Environment = "demo"
  }
}

#####################################
# IAM for SSM
#####################################

resource "aws_iam_role" "ssm_role" {
  # 名前を動的生成してアカウント間での衝突を防止
  # アカウントIDとリージョンを含めることで一意性を確保
  name = "nfw-demo-ec2-ssm-role-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "nfw-demo-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  # インスタンスプロファイル名も動的生成
  name = "nfw-demo-ec2-ssm-profile-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  role = aws_iam_role.ssm_role.name

  tags = {
    Name = "nfw-demo-ec2-ssm-profile"
  }
}

#####################################
# EC2 Instance
#####################################

resource "aws_instance" "test" {
  # Amazon Linux 2023 AMI (変数で指定)
  # デフォルトはap-northeast-1リージョンの最新安定版
  ami                         = var.ec2_ami_id
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
  # SSM接続に必要なVPCエンドポイント
  # VPCエンドポイントを使用することで、インターネット経由せずにプライベートにSSM接続可能
  # コスト: 各エンドポイント約$7.3/月 × 3 = 約$22/月
  endpoints = {
    ssm = {
      service_name = "com.amazonaws.${data.aws_region.current.name}.ssm"
      description  = "SSM endpoint for Session Manager"
    }
    ssmmessages = {
      service_name = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
      description  = "SSM Messages endpoint for Session Manager"
    }
    ec2messages = {
      service_name = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
      description  = "EC2 Messages endpoint for SSM Agent"
    }
  }
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [module.vpc_endpoint_security_group.security_group_id]
  private_dns_enabled = true

  tags = {
    Name        = "nfw-demo-${each.key}-endpoint"
    Environment = "demo"
    Description = each.value.description
  }
}

#####################################
# Network Firewall Locals
#####################################

locals {
  # Network FirewallのエンドポイントIDを取得
  # Network Firewallは各AZにエンドポイントを作成する
  # この環境では1つのAZ (変数で指定) のみを使用
  # firewall_statusのデータ構造: list(object({ sync_states = set(object({ ... })) }))
  # sync_statesから最初のエンドポイントIDを取得
  firewall_endpoint_id = try(
    tolist(aws_networkfirewall_firewall.main.firewall_status[0].sync_states)[0].attachment[0].endpoint_id,
    null
  )
}

#####################################
# Network Firewall Rule Groups
#####################################
# ルールグループ: トラフィックの許可・拒否ルールを定義
# ルールグループは複数のルールをまとめたもので、Firewall Policyから参照されます

# --- ALLOWLIST Rule Group ---
# ホワイトリスト方式: 明示的に許可したドメインのみアクセス可能
# 許可ドメイン: b.hatena.ne.jp, aws.amazon.com
# Domain List形式でALLOWLISTを定義
resource "aws_networkfirewall_rule_group" "allowlist" {
  capacity = 100
  name     = "allowlist-domain-rules"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        targets = [
          "b.hatena.ne.jp",
          ".hatena.ne.jp",
          "aws.amazon.com",
          ".amazon.com"
        ]
      }
    }
  }

  tags = { Name = "allowlist-domain-rules" }
}

# --- DENYLIST Rule Group ---
# すべてのドメインを拒否（ALLOWLISTと組み合わせてホワイトリスト方式を実現）
# DEFAULT_ACTION_ORDERでは、PASS（ALLOWLIST）がDROP（DENYLIST）より優先される
resource "aws_networkfirewall_rule_group" "denylist" {
  capacity = 50
  name     = "denylist-all-domains"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "DENYLIST"
        target_types         = ["TLS_SNI", "HTTP_HOST"]
        # すべてのドメインにマッチするワイルドカード
        targets = [
          ".com",
          ".net",
          ".org",
          ".jp",
          ".io",
          ".co",
          ".edu",
          ".gov"
        ]
      }
    }
  }

  tags = { Name = "denylist-all-domains" }
}
# STRICT_ORDERモード + stateful_default_actions で
# ALLOWLISTにマッチしないトラフィックはデフォルトで拒否される

#####################################
# Firewall Policy
#####################################
# Firewall Policy: ルールグループを統合し、トラフィック処理の全体的なロジックを定義
# Network Firewallのコアとなる設定で、Stateless/Statefulの両方の処理フローを制御

resource "aws_networkfirewall_firewall_policy" "main" {
  name = "firewall-policy"

  firewall_policy {
    # --- Stateless処理の設定 ---
    # Stateless: パケット単位で高速に処理（コネクション状態を保持しない）
    # 用途: 基本的なフィルタリング、DDoS対策、初期トラフィック振り分け

    # stateless_default_actions: 通常のパケットのデフォルト動作
    # aws:forward_to_sfe = Stateful Engine（SFE）に転送
    # 他の選択肢: aws:pass（そのまま通過）, aws:drop（破棄）
    stateless_default_actions = ["aws:forward_to_sfe"]

    # stateless_fragment_default_actions: フラグメント化されたパケットの動作
    # フラグメント化パケット: MTUサイズを超えたパケットが分割されたもの
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    # --- Stateful処理の設定 ---
    # Stateful: コネクションの状態を追跡し、アプリケーション層まで検査
    # ホワイトリスト方式: 許可ドメインのみアクセス可、それ以外は拒否

    # stateful_engine_options: STRICT_ORDERモードで明示的優先度制御
    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    # stateful_default_actions: どのルールにもマッチしなかったトラフィックを拒否
    # aws:drop_strict: STRICT_ORDERモードで全てのマッチしないトラフィックを拒否
    stateful_default_actions = ["aws:drop_strict"]

    # --- ルールグループの参照 ---
    # STRICT_ORDERモード: priorityで評価順序を明示的に指定

    # ALLOWLIST - 許可ドメインのみを定義
    # b.hatena.ne.jp, aws.amazon.com のみ許可
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.allowlist.arn
      priority     = 1
    }

    # 処理フロー (STRICT_ORDERモード + stateful_default_actions):
    # 1. Statelessエンジンで基本フィルタリング → Stateful Engineに転送
    # 2. ALLOWLIST評価 → b.hatena.ne.jp/aws.amazon.com にマッチすれば許可（PASS）
    # 3. ALLOWLIST不一致 → stateful_default_actions で拒否（DROP）
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

  # バージョニング: 無効化（terraform destroy時の削除を簡単にするため）
  versioning = {
    enabled = false
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

  # ライフサイクルルール (ログ保持期間: 変数で設定可能、デフォルト90日)
  lifecycle_rule = [
    {
      id      = "log-expiration"
      enabled = true

      expiration = {
        days = var.s3_log_expiration_days
      }

      noncurrent_version_expiration = {
        days = 30
      }
    }
  ]

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = "demo"
    Purpose     = "network-firewall-logging"
  }
}

#####################################
# S3 Bucket Policy for Network Firewall Logs
#####################################
# Network Firewallがログを書き込むために必要なバケットポリシーを明示的に定義
# aws_iam_policy_documentを使用することで、型安全性と可読性を向上

# ポリシードキュメントの定義
data "aws_iam_policy_document" "firewall_logs" {
  # Network Firewallサービスがログを書き込むことを許可
  statement {
    sid    = "AWSNetworkFirewallLogging"
    effect = "Allow"

    # Network Firewallサービスプリンシパル
    principals {
      type        = "Service"
      identifiers = ["network-firewall.amazonaws.com"]
    }

    # ログファイルの書き込み権限
    actions = [
      "s3:PutObject"
    ]

    # AWSLogs配下のすべてのオブジェクトへの書き込みを許可
    resources = [
      "${module.s3_firewall_logs.s3_bucket_arn}/AWSLogs/*"
    ]

    # セキュリティ強化: 同一アカウントからのリクエストのみ許可
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # バケットACL取得権限（Network Firewallがバケットの存在を確認するために必要）
  statement {
    sid    = "AWSNetworkFirewallBucketACL"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["network-firewall.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      module.s3_firewall_logs.s3_bucket_arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# バケットポリシーの適用
resource "aws_s3_bucket_policy" "firewall_logs" {
  bucket = module.s3_firewall_logs.s3_bucket_id
  policy = data.aws_iam_policy_document.firewall_logs.json

  # S3バケット作成完了後にポリシーを適用
  depends_on = [module.s3_firewall_logs]
}

#####################################
# Network Firewall
#####################################
# Network Firewall: VPC内にデプロイされる実際のファイアウォールインスタンス
# Firewall Endpointを作成し、トラフィックを検査・フィルタリング

resource "aws_networkfirewall_firewall" "main" {
  # name: ファイアウォールの識別名
  name = "vpc-firewall"

  # firewall_policy_arn: 適用するFirewall Policyの指定
  # このPolicyが実際のトラフィック処理ロジックを定義
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn

  # vpc_id: ファイアウォールをデプロイするVPC
  # このVPC内のトラフィックを検査対象とする
  vpc_id = aws_vpc.main.id

  # subnet_mapping: ファイアウォールエンドポイントを配置するサブネット
  # 各AZに1つのエンドポイントを配置するのがベストプラクティス
  # このハンズオンではシングルAZ構成のため1つのみ
  # エンドポイントID: aws_networkfirewall_firewall.main.firewall_status[0].sync_states[<AZ>].attachment[0].endpoint_id
  subnet_mapping {
    subnet_id = aws_subnet.firewall.id
  }

  # 補足: マルチAZ構成の場合
  # subnet_mapping {
  #   subnet_id = aws_subnet.firewall_az1.id
  # }
  # subnet_mapping {
  #   subnet_id = aws_subnet.firewall_az2.id
  # }

  tags = { Name = "nfw-demo" }
}

#####################################
# Network Firewall Logging Configuration
#####################################
# ログ設定: Network Firewallが生成するログの出力先と形式を定義
# ログは複数の宛先に同時出力可能（S3 + CloudWatch Logsなど）

resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {
    # S3へのALERTログ出力（許可・拒否ログ）
    # プレフィックス形式: alert/yyyy/mm/dd/
    log_destination_config {
      log_destination = {
        bucketName = module.s3_firewall_logs.s3_bucket_id
        # プレフィックスに日付を含めてパーティション分割
        # AWSは自動的にyyyy/mm/dd/hh/の形式でログを保存
        prefix = "alert"
      }
      log_destination_type = "S3"

      # log_type: ALERT
      # ALERT: ルールにマッチしたトラフィックのみ（許可・拒否）
      # - ドメイン名
      # - アクション（allowed/blocked）
      # - ルール情報
      # - タイムスタンプ
      log_type = "ALERT"
    }
  }
}

# CloudWatch Logsとメトリクスフィルターは監視不要のため削除

# Athenaは不要のため削除

#####################################
# Route: Private Subnet → Firewall Endpoint
#####################################

# Private Subnet → Firewall Endpoint へのルート
# EC2からのすべてのインターネット向けトラフィックをFirewallに送る
resource "aws_route" "private_to_firewall" {
  count = local.firewall_endpoint_id != null ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_id

  # Network Firewallのエンドポイント作成完了を明示的に待機
  depends_on = [aws_networkfirewall_firewall.main]
}

# IGW Edge Association (アウトバウンド通信の戻りトラフィック用)
#
# このルートは「インバウンド」通信用ではなく、「アウトバウンド通信の戻りパケット」用です。
#
# シナリオ: EC2 (10.0.2.5) が example.com にHTTPSリクエストを送信
#
# 往路 (EC2 → インターネット):
#   EC2 (10.0.2.5) → Firewall → IGW → example.com
#
# 復路 (インターネット → EC2):
#   example.com → IGW → ??? → EC2 (10.0.2.5)
#
#   問題: IGWは宛先10.0.2.5へのルートを知らない
# 重複削除: IGW Edge Associationは150行目で定義済み

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
  description = "S3 bucket for Network Firewall ALERT logs"
  value       = module.s3_firewall_logs.s3_bucket_id
}

output "test_commands" {
  description = "Commands to test Network Firewall whitelist rules"
  value       = <<-EOT
    # SSM接続
    aws ssm start-session --target ${aws_instance.test.id} --region ap-northeast-1

    # ホワイトリスト許可ドメインのテスト:

    # b.hatena.ne.jp - 許可されるはず
    curl -I https://b.hatena.ne.jp --max-time 10

    # aws.amazon.com - 許可されるはず
    curl -I https://aws.amazon.com --max-time 10

    # google.com - 拒否されるはず（タイムアウト）
    curl -I https://google.com --max-time 10

    # S3 ALERTログの確認（yyyy/mm/dd形式）:
    aws s3 ls s3://${module.s3_firewall_logs.s3_bucket_id}/alert/ --recursive
  EOT
}
