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
  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.private_subnet_cidr
  vpc_endpoint_id        = local.firewall_endpoint_id

  depends_on = [aws_networkfirewall_firewall.main]
}

# IGWルートテーブルをIGWにアタッチ
resource "aws_route_table_association" "igw" {
  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw.id
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
  # 明示的にAZ名を指定してエンドポイントIDを取得することで、
  # どのAZのエンドポイントを使用しているか明確にする
  # try()でnullを許容し、ルート作成時に検証
  firewall_endpoint_id = try(
    aws_networkfirewall_firewall.main.firewall_status[0].sync_states[var.availability_zone].attachment[0].endpoint_id,
    null
  )
}

#####################################
# Network Firewall Rule Groups
#####################################
# ルールグループ: トラフィックの許可・拒否ルールを定義
# ルールグループは複数のルールをまとめたもので、Firewall Policyから参照されます

# --- ALLOWLIST Rule Group ---
# 目的: 許可するドメインへのアクセスを明示的に定義
# 用途: ホワイトリスト方式でアクセス制御を行う場合に使用
resource "aws_networkfirewall_rule_group" "allowlist" {
  # capacity: ルールグループが保持できるルールの最大数
  # 一度設定すると変更不可のため、将来の拡張を見越して設定
  # ドメインルールの場合、1ドメイン=約1 capacity消費
  capacity = 100
  name     = "allowlist-domain-rules"

  # type: ルールグループのタイプ
  # STATEFUL: コネクションの状態を追跡し、双方向のトラフィックを管理
  # STATELESS: パケット単位で評価（状態追跡なし）
  type = "STATEFUL"

  rule_group {
    rules_source {
      # rules_source_list: ドメインベースのフィルタリング用
      # Suricataルール形式よりも簡潔にドメインルールを定義可能
      rules_source_list {
        # targets: 許可するドメインのリスト
        # 先頭のドット(.)はワイルドカードを意味（例: .example.com は www.example.com, api.example.com などを含む）
        #
        # 許可ドメイン:
        # - .amazonaws.com: AWSサービスエンドポイント（SSM, EC2messages, SSMmessages等）
        # - .amazon.com: Amazon.comドメイン（aws.amazon.com等）
        # - .example.com: テスト用ドメイン
        targets = [
          ".example.com",
          ".amazonaws.com",
          ".amazon.com"
        ]

        # target_types: 検査対象のプロトコル層
        # HTTP_HOST: HTTPリクエストのHostヘッダーを検査
        # TLS_SNI: TLSハンドシェイクのSNI（Server Name Indication）を検査
        # 両方指定することでHTTP/HTTPS両方のトラフィックを検査
        target_types = ["HTTP_HOST", "TLS_SNI"]

        # generated_rules_type: ルールの動作タイプ
        # ALLOWLIST: マッチしたトラフィックを許可、それ以外は次のルールへ
        # DENYLIST: マッチしたトラフィックを拒否
        generated_rules_type = "ALLOWLIST"
      }
    }
  }

  tags = { Name = "allowlist-domain-rules" }
}

# --- DENYLIST Rule Group ---
# 目的: 拒否するドメインへのアクセスをブロック
# 用途: 特定のドメインを明示的にブロックする場合に使用（例: マルウェアC2サーバー、不適切なサイトなど）
# 注意: Firewall Policyで優先度1に設定され、ALLOWLISTより先に評価される
resource "aws_networkfirewall_rule_group" "denylist" {
  capacity = 100
  name     = "denylist-domain-rules"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        # targets: 拒否するドメインのリスト
        # このハンズオンでは google.com を使用して動作確認
        # 本番環境では既知の悪性ドメインやポリシー違反ドメインを指定
        targets      = [".google.com"]
        target_types = ["HTTP_HOST", "TLS_SNI"]

        # DENYLIST: マッチしたトラフィックは即座に拒否され、ALERTログに記録
        generated_rules_type = "DENYLIST"
      }
    }
  }

  tags = { Name = "denylist-domain-rules" }
}

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
    # 用途: ドメインフィルタリング、IPS/IDS、プロトコル検査

    # stateful_default_actions: どのルールにもマッチしなかった場合の動作
    # aws:drop_strict = ルールにマッチしないトラフィックを拒否
    # 他の選択肢: aws:drop_established（確立済み接続は許可）, aws:alert_strict（アラートのみ）
    # このハンズオンでは厳格なドロップポリシーを採用
    stateful_default_actions = ["aws:drop_strict"]

    # stateful_engine_options: Statefulエンジンの動作モード
    stateful_engine_options {
      # rule_order: ルールの評価順序を制御
      # DEFAULT_ACTION_ORDER: アクション優先度で自動評価（DENYLIST > ALLOWLIST）
      # STRICT_ORDER: 明示的なpriorityで評価（Suricataルール用、rules_source_listでは使用不可）
      #
      # rules_source_list (ALLOWLIST/DENYLIST) を使用する場合は DEFAULT_ACTION_ORDER が必須
      # このモードでは、DENYLISTが自動的にALLOWLISTより優先されるため、
      # 明示的なpriority設定は不要（設定するとエラーになる）
      rule_order = "DEFAULT_ACTION_ORDER"
    }

    # --- ルールグループの参照 ---
    # DEFAULT_ACTION_ORDERモードでは、priorityフィールドは使用しない
    # ルールの優先順位は自動的に決定される: DENYLIST > ALLOWLIST > stateful_default_actions

    # DENYLIST ルールグループ
    # マッチしたトラフィックを即座に拒否し、ALERTログに記録
    # ALLOWLISTより優先して評価される
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.denylist.arn
    }

    # ALLOWLIST ルールグループ
    # マッチしたトラフィックを許可
    # DENYLISTの後に評価される
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.allowlist.arn
    }

    # 処理フロー:
    # 1. Statelessエンジンで基本フィルタリング → SFEに転送
    # 2. StatefulエンジンでDENYLISTを評価 → マッチしたら拒否
    # 3. ALLOWLISTを評価 → マッチしたら許可
    # 4. どちらにもマッチしない → aws:drop_strictで拒否
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
    # --- S3へのFLOWログ出力 ---
    # 用途: トラフィック統計分析、ネットワーク可視化
    log_destination_config {
      log_destination = {
        bucketName = module.s3_firewall_logs.s3_bucket_id
        prefix     = "AWSLogs/NetworkFirewall/flow"
      }
      log_destination_type = "S3"

      # log_type: FLOW
      # FLOW: すべてのトラフィックフローの統計情報（ルールマッチに関係なく）
      # - 送信元/宛先IP、ポート
      # - プロトコル（TCP/UDP）
      # - パケット数、バイト数
      # - 接続の開始/終了時刻
      # 注意: ALERTログよりもデータ量が多い
      log_type = "FLOW"
    }

    # --- CloudWatch Logsへのログ出力 (メトリクス用) ---
    # 用途: リアルタイム監視、CloudWatch Metricsでのアラート設定
    log_destination_config {
      log_destination = {
        # logGroup: CloudWatch Logsのロググループ名
        # Metric Filterを適用して、ブロック回数などをメトリクス化
        logGroup = aws_cloudwatch_log_group.network_firewall_alert.name
      }
      log_destination_type = "CloudWatchLogs"

      # ALERTログのみをCloudWatch Logsに送信
      # 理由: メトリクス抽出にはALERTログで十分、FLOWログは大量すぎる
      log_type = "ALERT"
    }

    # ログ出力のベストプラクティス:
    # 1. S3 (ALERT + FLOW): 長期保管と詳細分析用
    # 2. CloudWatch Logs (ALERTのみ): リアルタイム監視とアラート用
    # 3. KinesisDataFirehose (オプション): SIEM連携など
  }
}

#####################################
# CloudWatch Logs for Metrics
#####################################
# CloudWatch Logsロググループ: メトリクスフィルター適用のためのログ受け皿
# S3ログは長期保管用、CloudWatch Logsはリアルタイム監視用

resource "aws_cloudwatch_log_group" "network_firewall_alert" {
  # name: ロググループの名前（AWS命名規則に従う）
  name = "/aws/network-firewall/alert"

  # retention_in_days: ログ保持期間
  # メトリクス抽出が目的のため短期保持（デフォルト7日）
  # 長期保管はS3で行うため、CloudWatch Logsはコスト最適化
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name        = "${var.project_name}-alert-logs"
    Environment = "demo"
  }
}

#####################################
# CloudWatch Metric Filters
#####################################
# メトリクスフィルター: ログからメトリクスを抽出し、CloudWatch Metricsとして可視化
# アラーム設定、ダッシュボード表示、自動スケーリングなどに活用可能

# --- ブロックされたドメインアクセスのカウント ---
# 用途: セキュリティ監視、攻撃検知、ポリシー違反の把握
resource "aws_cloudwatch_log_metric_filter" "blocked_domains" {
  name           = "NetworkFirewall-BlockedDomains"
  log_group_name = aws_cloudwatch_log_group.network_firewall_alert.name

  # pattern: ログからメトリクスを抽出するパターン
  # JSONフィールドベースのフィルタリングで、ブロックされたログのみを抽出
  # $.event.alert.action = "blocked" にマッチするログのみカウント
  pattern = "{ $.event.alert.action = \"blocked\" }"

  # metric_transformation: 抽出したログをメトリクスに変換
  metric_transformation {
    # name: メトリクス名（CloudWatch Metricsで表示される名前）
    name = "BlockedDomainCount"

    # namespace: メトリクスの名前空間（複数メトリクスをグループ化）
    # カスタムメトリクスは任意の名前空間を使用可能
    namespace = "NetworkFirewall"

    # value: メトリクスの値
    # "1" = ログが1件見つかるたびにカウント+1
    # 他の例: "$.event.netflow.bytes" でバイト数を抽出
    value = "1"

    # unit: メトリクスの単位
    # Count: 回数、Bytes: バイト数、Seconds: 秒など
    unit = "Count"
  }

  # このメトリクスの活用例:
  # - CloudWatch Alarmでしきい値超過時に通知
  # - ダッシュボードで時系列グラフ表示
  # - 異常な増加パターンの検知
}

# --- 許可されたドメインアクセスのカウント ---
# 用途: 通常トラフィック量の把握、ベースライン作成
resource "aws_cloudwatch_log_metric_filter" "allowed_domains" {
  name           = "NetworkFirewall-AllowedDomains"
  log_group_name = aws_cloudwatch_log_group.network_firewall_alert.name

  # pattern: JSONフィールドベースのフィルタリング
  # $.event.alert.action = "allowed" にマッチするログのみ抽出
  # ALERTログのJSON構造に基づいたパターンマッチング
  pattern = "{ $.event.alert.action = \"allowed\" }"

  metric_transformation {
    name      = "AllowedDomainCount"
    namespace = "NetworkFirewall"
    value     = "1"
    unit      = "Count"
  }

  # このメトリクスの活用例:
  # - 許可/拒否の比率を監視
  # - 通常時のトラフィックパターンを把握
  # - ポリシー変更前後の影響分析
}

# 補足: CloudWatch Metricsの確認方法
# 1. CloudWatchコンソール → メトリクス → NetworkFirewall 名前空間
# 2. メトリクス名: BlockedDomainCount, AllowedDomainCount
# 3. グラフ化して時系列で表示
# 4. アラーム設定でしきい値超過時にSNS通知

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

  # GitHub ActionsのIAMロールがglue:GetTags権限を持たない場合に
  # Terraform refreshエラーを回避するため、タグ変更を無視
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
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

  # Network Firewallのエンドポイント作成完了を明示的に待機
  depends_on = [aws_networkfirewall_firewall.main]

  # Firewall Endpoint IDがnullでないことを検証
  # Firewallのデプロイが完了していない場合はエラーで停止
  lifecycle {
    precondition {
      condition     = local.firewall_endpoint_id != null
      error_message = "Network Firewall endpoint ID is null. Firewall deployment may have failed or is not yet complete in availability zone ${var.availability_zone}."
    }
  }
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
#
#   解決: このルートがIGWに「10.0.2.0/24宛のパケットはFirewallへ送れ」と指示
#   example.com → IGW → Firewall → EC2 (10.0.2.5)
#
# 注意: EC2はプライベートIPのみでパブリックIPを持たないため、
# インターネットからの新規インバウンド接続は受け付けません。
# これは確立済み接続(ESTABLISHED)の戻りパケット用です。
resource "aws_route" "igw_to_firewall" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = aws_subnet.private.cidr_block
  vpc_endpoint_id        = local.firewall_endpoint_id

  # Network Firewallのエンドポイント作成完了を明示的に待機
  depends_on = [aws_networkfirewall_firewall.main]

  # Firewall Endpoint IDがnullでないことを検証
  lifecycle {
    precondition {
      condition     = local.firewall_endpoint_id != null
      error_message = "Network Firewall endpoint ID is null. Firewall deployment may have failed or is not yet complete in availability zone ${var.availability_zone}."
    }
  }
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

    # FLOWログの確認 (S3に保存されるのはFLOWログのみ)
    aws s3 ls s3://${module.s3_firewall_logs.s3_bucket_id}/AWSLogs/NetworkFirewall/flow/ --recursive


    ### 3. CloudWatch Logsでアラート確認 ###

    # ALERTログはCloudWatch Logsに保存
    aws logs tail ${aws_cloudwatch_log_group.network_firewall_alert.name} --follow


    ### 4. Athenaでログ分析 ###

    # 以下のDDLをAthenaで実行してテーブル作成
    # ワークグループ: ${aws_athena_workgroup.firewall_analysis.name}
    # データベース: ${aws_glue_catalog_database.firewall_logs.name}
  EOT
}

output "athena_ddl_flow" {
  description = "Athena DDL to create FLOW logs table with partitions"
  value       = <<-EOT
    -- パーティション対応のFLOWログテーブル作成
    -- FLOWログはALERTログより大量のため、パーティション化が特に重要

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
    PARTITIONED BY (
      year string,
      month string,
      day string,
      hour string
    )
    ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
    LOCATION 's3://${module.s3_firewall_logs.s3_bucket_id}/AWSLogs/NetworkFirewall/flow/'
    TBLPROPERTIES (
      'projection.enabled' = 'true',
      'projection.year.type' = 'integer',
      'projection.year.range' = '2020,2035',
      'projection.month.type' = 'integer',
      'projection.month.range' = '01,12',
      'projection.month.digits' = '2',
      'projection.day.type' = 'integer',
      'projection.day.range' = '01,31',
      'projection.day.digits' = '2',
      'projection.hour.type' = 'integer',
      'projection.hour.range' = '00,23',
      'projection.hour.digits' = '2',
      'storage.location.template' = 's3://${module.s3_firewall_logs.s3_bucket_id}/AWSLogs/NetworkFirewall/flow/$${year}/$${month}/$${day}/$${hour}'
    );

    -- パーティションプロジェクション使用時の利点:
    -- 1. MSCK REPAIR TABLE不要（自動でパーティション認識）
    -- 2. クエリ時に WHERE year='2025' AND month='01' AND day='15' などでフィルタ可能
    -- 3. スキャンデータ量削減 = コスト削減 & 高速化
  EOT
}

output "athena_sample_queries" {
  description = "Sample Athena queries for FLOW log analysis with partition filters"
  value       = <<-EOT
    注意: ALERTログはCloudWatch Logsに保存されています。
    ALERTログの分析はCloudWatch Logs Insightsを使用してください。
    S3に保存されているのはFLOWログのみです。

    -- ========================================
    -- 1. トラフィックフロー(FLOW)の統計 - 特定日のみ
    -- ========================================
    -- FLOWログは大量のため、パーティションフィルタが必須
    -- WHERE句にパーティションカラム(year, month, day)を含めることで高速化

    SELECT
      event.dest_ip,
      event.dest_port,
      event.proto,
      COUNT(*) as connection_count,
      SUM(event.netflow.bytes) as total_bytes,
      SUM(event.netflow.pkts) as total_packets
    FROM ${aws_glue_catalog_database.firewall_logs.name}.flow_logs
    WHERE year = '2025'
      AND month = '01'
      AND day = '15'
    GROUP BY event.dest_ip, event.dest_port, event.proto
    ORDER BY total_bytes DESC
    LIMIT 20;

    -- ========================================
    -- 2. 時間帯別トラフィック分析（週単位）
    -- ========================================
    -- パーティションフィルタで週単位のデータのみ集計

    SELECT
      date_trunc('hour', from_unixtime(event_timestamp)) as hour,
      COUNT(*) as flow_count,
      SUM(event.netflow.bytes) as total_bytes
    FROM ${aws_glue_catalog_database.firewall_logs.name}.flow_logs
    WHERE year = '2025'
      AND month = '01'
      AND day BETWEEN '15' AND '21'
    GROUP BY date_trunc('hour', from_unixtime(event_timestamp))
    ORDER BY hour DESC;

    -- ========================================
    -- 3. パーティション別のログ件数確認
    -- ========================================
    -- 各パーティションにどれだけのログがあるかを確認

    SELECT
      year,
      month,
      day,
      hour,
      COUNT(*) as log_count
    FROM ${aws_glue_catalog_database.firewall_logs.name}.flow_logs
    WHERE year = '2025'
      AND month = '01'
    GROUP BY year, month, day, hour
    ORDER BY year, month, day, hour;

    -- ========================================
    -- パーティションフィルタ利用のベストプラクティス:
    -- ========================================
    -- 1. 常にWHERE句にyear, month, dayを含める
    -- 2. 範囲指定時は BETWEEN を使用
    -- 3. 全期間スキャンが必要な場合は集計範囲を限定
    -- 4. クエリ実行前に「Data scanned」を確認

    -- ========================================
    -- CloudWatch Logs Insightsでのアラート分析例:
    -- ========================================
    -- ロググループ: ${aws_cloudwatch_log_group.network_firewall_alert.name}
    --
    -- fields @timestamp, event.src_ip, event.dest_ip, event.alert.signature, event.alert.action
    -- | filter event.alert.action = "blocked"
    -- | sort @timestamp desc
    -- | limit 100
  EOT
}
