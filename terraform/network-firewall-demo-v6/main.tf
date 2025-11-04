#####################################
# Terraform Backend (S3)
#####################################

terraform {
  backend "s3" {
    bucket = "apricot1224v1-terraform"
    key    = "network-firewall-demo-v6/terraform.tfstate"
    region = "ap-northeast-1"
  }

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = "~> 5.0"
      version = "6.19.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

#####################################
# Data Sources
#####################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_iam_account_alias" "current" {}

#####################################
# Locals
#####################################

locals {
  account_id    = data.aws_caller_identity.current.account_id
  account_alias = data.aws_iam_account_alias.current.account_alias
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
  default     = "10.2.0.0/22"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.2.0.0/24"
}

variable "firewall_subnet_cidr" {
  description = "CIDR block for firewall subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.2.2.0/24"
}


variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "network-firewall-demo-v6"
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


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "nfw-demo-igw-v6" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nfw-demo-nat-eip-v6" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  # NAT GatewayはPublic Subnetに配置し、IGWへのルートが必要
  depends_on = [aws_internet_gateway.main]

  tags = { Name = "nfw-demo-nat-v6" }
}


#####################################
# Route Tables
#####################################

# 1. Public Subnet Route Table (Egress: Internet-bound traffic)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-public-rtb" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Egress: Public Subnet -> Internet (0.0.0.0/0経由でインターネットアクセス)
resource "aws_route" "public_to_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Egress: Public Subnet -> Private Subnet (Firewall経由でプライベートサブネットへ)
resource "aws_route" "public_to_private" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.private_subnet_cidr
  vpc_endpoint_id        = local.firewall_endpoint_id

  # Network Firewall作成後にルート設定を実施
  depends_on = [aws_networkfirewall_firewall.netfw]
}

# 2. Firewall Subnet Route Table (Egress: Inspected traffic to NAT)
resource "aws_route_table" "firewall" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-firewall-rtb" }
}

resource "aws_route_table_association" "firewall" {
  subnet_id      = aws_subnet.firewall.id
  route_table_id = aws_route_table.firewall.id
}

# Egress: Firewall Subnet -> NAT Gateway (検査後のトラフィックをNAT経由でインターネットへ)
resource "aws_route" "firewall_to_nat" {
  route_table_id         = aws_route_table.firewall.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# 3. Private Subnet Route Table (Egress: All traffic to Firewall)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rtb" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Egress: Private Subnet -> Firewall (すべてのトラフィックをFirewall経由で検査)
resource "aws_route" "private_to_firewall" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_id
  # Network Firewall作成後にルート設定を実施
  depends_on = [aws_networkfirewall_firewall.netfw]
}

#####################################
# 4. Internet Gateway Route Table
#####################################
#
# ⚠️ 現在の構成では以下のリソースは不要のためコメントアウトしています
#
# 【現在の構成で双方向検査が不要な理由】
# 1. プライベートサブネットのみ使用
#    - EC2インスタンスはパブリックIPを持たない
#    - インバウンド接続は受けない（SSM経由でのみアクセス）
#    - すべてアウトバウンド開始の通信のみ
#
# 2. 厳格なアウトバウンド制御
#    - Network Firewallでドメインホワイトリスト(.amazon.com, .amazonaws.com)を実施
#    - 信頼できるドメインへのアクセスのみ許可
#
# 3. ステートフルNATによる保護
#    - NAT Gatewayは自動的に関連する戻りトラフィックのみ許可
#    - 新規インバウンド接続は自動的にブロック
#
# 4. コスト最適化
#    - 復路でFirewallを経由しないことでデータ処理量を半分に削減
#    - Network Firewall料金はデータ処理量(GB)に応じて課金
#
# 【双方向検査のメリット（将来的に必要な場合）】
# 1. レスポンスペイロード検査
#    - 正規のドメインが侵害された場合の対策
#    - DNS乗っ取り攻撃やMITM攻撃の検出
#    - 悪意あるレスポンスコンテンツのブロック
#
# 2. ステートフルな接続の完全性
#    - Network Firewallが両方向を追跡
#    - 異常な戻りトラフィックパターンの検出
#    - セッションハイジャック防止
#    - データ流出(exfiltration)の検出
#
# 3. コンプライアンス要件
#    - PCI-DSS, HIPAA等の規制で双方向検査が推奨/必須の場合
#
# 【双方向検査のデメリット】
# 1. コスト増加: データ処理量が2倍（往路+復路）
# 2. レイテンシ増加: 復路もFirewall経由で若干の遅延
# 3. 複雑性: ルーティング設定が複雑になる
#
# 【このリソースが必要になるケース】
# 将来的に以下を実装する場合のみ、下記のコメントを解除してください:
# 1. パブリックサブネットにリソース配置（ALB/NLB、パブリックIPを持つEC2）
# 2. インバウンドトラフィックの受信（Webサーバー、API）
# 3. 厳格なコンプライアンス要件で双方向検査が必須の場合
#
# 【トラフィックフロー】
# 往路: EC2(Private) → Firewall → NAT(Public) → IGW → Internet
# 復路（IGWルートなし）: Internet → IGW → NAT(Public) → EC2(Private)  ← 現在
# 復路（IGWルート有）: Internet → IGW → Firewall → NAT(Public) → EC2(Private)
#

# # Ingress: Internet Gateway Route Table (インターネットからの戻りトラフィック)
# resource "aws_route_table" "igw" {
#   vpc_id = aws_vpc.main.id
#   tags   = { Name = "${var.project_name}-igw-rtb" }
# }

# resource "aws_route_table_association" "igw" {
#   gateway_id     = aws_internet_gateway.main.id
#   route_table_id = aws_route_table.igw.id
# }

# # Ingress: Internet Gateway -> Public Subnet (Firewall経由でパブリックサブネットへ)
# resource "aws_route" "igw_to_public" {
#   route_table_id         = aws_route_table.igw.id
#   destination_cidr_block = var.public_subnet_cidr
#   vpc_endpoint_id        = local.firewall_endpoint_id
#
#   # Network Firewall作成後にルート設定を実施
#   depends_on = [aws_networkfirewall_firewall.netfw]
# }

#####################################
# Security Groups
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
# IAM Roles & Policies
#####################################

resource "aws_iam_role" "ssm_role" {
  # 名前を動的生成してアカウント間での衝突を防止
  # アカウントIDとリージョンを含めることで一意性を確保
  name = "nfw-demo-ec2-ssm-role-${local.account_id}-${data.aws_region.current.id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "nfw-demo-ec2-ssm-role-v6"
  }
}

resource "aws_iam_instance_profile" "ssm_profile" {
  # インスタンスプロファイル名も動的生成
  name = "nfw-demo-ec2-ssm-profile-${local.account_id}-${data.aws_region.current.id}"
  role = aws_iam_role.ssm_role.name

  tags = {
    Name = "nfw-demo-ec2-ssm-profile-v6"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#####################################
# EC2 Instances
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
    http_tokens                 = "required" # IMDSv6を強制
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name        = "firewall-test-ec2-v6"
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
      service_name = "com.amazonaws.${data.aws_region.current.id}.ssm"
      description  = "SSM endpoint for Session Manager"
    }
    ssmmessages = {
      service_name = "com.amazonaws.${data.aws_region.current.id}.ssmmessages"
      description  = "SSM Messages endpoint for Session Manager"
    }
    ec2messages = {
      service_name = "com.amazonaws.${data.aws_region.current.id}.ec2messages"
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
# Network Firewall Configuration
#####################################

# 1. Rule Groups
# ドメインリストフィルタリング: .amazon.com と .amazonaws.com を許可

resource "aws_networkfirewall_rule_group" "allow_rule_group" {
  capacity = 100
  name     = "allow-rule-group"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = [".amazon.com", ".amazonaws.com"]
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "allow-rule-group" }
}

# 2. Firewall Policy

resource "aws_networkfirewall_firewall_policy" "test_firewall_policy" {
  name = "test-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    # STRICT_ORDER: ルールを順序通りに評価
    stateful_engine_options {
      rule_order              = "STRICT_ORDER"
      stream_exception_policy = "REJECT"
    }

    # デフォルトアクション: どのルールにもマッチしない場合の動作
    stateful_default_actions = ["aws:drop_established"]

    # ドメインフィルタリングルールグループ
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.allow_rule_group.arn
      priority     = 1
    }
  }

  tags = { Name = "test-firewall-policy" }
}

# 3. Network Firewall

resource "aws_networkfirewall_firewall" "netfw" {
  name                = "netfw"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.test_firewall_policy.arn
  vpc_id              = aws_vpc.main.id

  # 削除保護とサブネット変更保護を有効化
  # delete_protection        = true
  # subnet_change_protection = true

  subnet_mapping {
    subnet_id = aws_subnet.firewall.id
  }

  tags = { Name = "netfw" }
}

#####################################
# Locals for Network Firewall Endpoints
#####################################

locals {
  # Network Firewallエンドポイント作成後に取得
  # ルーティング設定で使用するため、ここで一元管理
  firewall_endpoint_id = try(
    tolist(aws_networkfirewall_firewall.netfw.firewall_status[0].sync_states)[0].attachment[0].endpoint_id,
    null
  )
}

# 4. S3 Bucket for Logs
# terraform-aws-s3-bucketモジュールを使用してS3バケットを作成
module "s3_bucket_firewall_logs" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.8"

  bucket = "${local.account_alias}-nwf-logs-v6"

  # バージョニング: 無効
  versioning = {
    enabled = false
  }

  # サーバーサイド暗号化: 有効 (デフォルトでAES256)
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # パブリックアクセスブロック: すべて有効(セキュリティベストプラクティス)
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # オブジェクトの所有権: BucketOwnerEnforced
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # ACL: 無効 (object_ownershipがBucketOwnerEnforcedのため)
  acl = null

  tags = {
    Name        = "${local.account_alias}-nwf-logs-v6"
    Environment = "demo"
    Purpose     = "Network Firewall Logs"
  }
}

# S3バケットポリシー: Network Firewallがログを書き込めるように許可
data "aws_iam_policy_document" "firewall_logs_policy" {
  # Network Firewallサービスによる直接書き込み権限
  statement {
    sid    = "AWSNetworkFirewallPutObject"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["network-firewall.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "arn:aws:s3:::${local.account_alias}-nwf-logs-v6/alert/AWSLogs/${local.account_id}/*",
      "arn:aws:s3:::${local.account_alias}-nwf-logs-v6/flow/AWSLogs/${local.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AWSNetworkFirewallGetBucketAcl"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["network-firewall.amazonaws.com"]
    }

    actions = ["s3:GetBucketAcl"]

    resources = ["arn:aws:s3:::${local.account_alias}-nwf-logs-v6"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # CloudWatch Logs経由での書き込み権限（オプション）
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "arn:aws:s3:::${local.account_alias}-nwf-logs-v6/alert/AWSLogs/${local.account_id}/*",
      "arn:aws:s3:::${local.account_alias}-nwf-logs-v6/flow/AWSLogs/${local.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.id}:${local.account_id}:*"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = ["s3:GetBucketAcl"]

    resources = ["arn:aws:s3:::${local.account_alias}-nwf-logs-v6"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.id}:${local.account_id}:*"]
    }
  }
}

resource "aws_s3_bucket_policy" "firewall_logs_policy" {
  bucket = module.s3_bucket_firewall_logs.s3_bucket_id
  policy = data.aws_iam_policy_document.firewall_logs_policy.json
}

# 5. Logging Configuration
# ALERTログ: ルールにマッチしたトラフィック（許可/ブロック）を記録
# FLOWログ: すべてのネットワークフローを記録
resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.netfw.arn

  logging_configuration {
    # ALERTログ: ブロックされたトラフィックや許可されたトラフィックの詳細
    log_destination_config {
      log_destination = {
        bucketName = module.s3_bucket_firewall_logs.s3_bucket_id
        prefix     = "alert"
      }
      log_destination_type = "S3"
      log_type             = "ALERT"
    }

    # FLOWログ: すべてのネットワークフローのメタデータ
    log_destination_config {
      log_destination = {
        bucketName = module.s3_bucket_firewall_logs.s3_bucket_id
        prefix     = "flow"
      }
      log_destination_type = "S3"
      log_type             = "FLOW"
    }
  }
}
