#####################################
# Terraform Backend (S3)
#####################################

terraform {
  backend "s3" {
    bucket = "apricot1224v1-terraform"
    key    = "network-firewall-demo-v4/terraform.tfstate"
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
  default     = "network-firewall-demo-v4"
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
  tags   = { Name = "nfw-demo-igw-v4" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "nfw-demo-nat-eip-v4" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  # NAT GatewayはPublic Subnetに配置し、IGWへのルートが必要
  depends_on = [aws_internet_gateway.main]

  tags = { Name = "nfw-demo-nat-v4" }
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

# Egress: Public Subnet -> Network Firewall Endpoint
resource "aws_route" "public_egress_to_firewall" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
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

# Egress: Firewall Subnet -> Internet Gateway (after inspection)
resource "aws_route" "firewall_egress_to_igw" {
  route_table_id         = aws_route_table.firewall.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
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

# Egress: Private Subnet -> Public Subnet (for inspection)
resource "aws_route" "private_egress_to_public" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
  # Network Firewall作成後にルート設定を実施
  # depends_on = [aws_networkfirewall_firewall.main]
}

# Egress: Private Subnet -> Firewall Endpoint (for inspection)
# resource "aws_route" "private_egress_to_firewall" {
#   route_table_id         = aws_route_table.private.id
#   destination_cidr_block = "0.0.0.0/0"
#   vpc_endpoint_id        = local.firewall_endpoint_id

#   # Network Firewall作成後にルート設定を実施
#   depends_on = [aws_networkfirewall_firewall.main]
# }

# 4. IGW Route Table (Ingress: Return traffic from Internet)
# IGWからPrivate Subnetへの戻りトラフィックをFirewall Endpointに転送
resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw-rtb" }
}

# Ingress: IGW -> Firewall Endpoint (return traffic to Public Subnet)
resource "aws_route" "igw_ingress_to_firewall" {
  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.public_subnet_cidr
  vpc_endpoint_id        = local.firewall_endpoint_id

  # Network Firewall作成後にルート設定を実施
  depends_on = [aws_networkfirewall_firewall.netfw]
}

resource "aws_route_table_association" "igw" {
  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw.id

  # IGWルート作成後にアタッチ
  depends_on = [aws_route.igw_ingress_to_firewall]
}


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
  name = "nfw-demo-ec2-ssm-role-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "nfw-demo-ec2-ssm-role-v4"
  }
}

resource "aws_iam_instance_profile" "ssm_profile" {
  # インスタンスプロファイル名も動的生成
  name = "nfw-demo-ec2-ssm-profile-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.id}"
  role = aws_iam_role.ssm_role.name

  tags = {
    Name = "nfw-demo-ec2-ssm-profile-v4"
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
    http_tokens                 = "required" # IMDSv4を強制
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name        = "firewall-test-ec2-v4"
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
  delete_protection        = true
  subnet_change_protection = true

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
# 既存のS3バケットを参照（手動で作成済み）
data "aws_s3_bucket" "firewall_logs" {
  bucket = "apricot1224v1-nwf-logs-v4"
}

# S3バケットポリシー: Network Firewallがログを書き込めるように許可
resource "aws_s3_bucket_policy" "firewall_logs_policy" {
  bucket = data.aws_s3_bucket.firewall_logs.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Id": "AWSLogDeliveryWrite20150319",
    "Statement": [
        {
            "Sid": "AWSLogDeliveryWrite1",
            "Effect": "Allow",
            "Principal": {
                "Service": "delivery.logs.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::apricot1224v1-nwf-logs-v4/alert/AWSLogs/346381328608/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "aws:SourceAccount": "346381328608"
                },
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:logs:ap-northeast-1:346381328608:*"
                }
            }
        },
        {
            "Sid": "AWSLogDeliveryAclCheck1",
            "Effect": "Allow",
            "Principal": {
                "Service": "delivery.logs.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::apricot1224v1-nwf-logs-v4",
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "346381328608"
                },
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:logs:ap-northeast-1:346381328608:*"
                }
            }
        },
        {
            "Sid": "AWSLogDeliveryWrite2",
            "Effect": "Allow",
            "Principal": {
                "Service": "delivery.logs.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::apricot1224v1-nwf-logs-v4/flow/AWSLogs/346381328608/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "aws:SourceAccount": "346381328608"
                },
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:logs:ap-northeast-1:346381328608:*"
                }
            }
        }
    ]
})
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
        bucketName = data.aws_s3_bucket.firewall_logs.id
        prefix     = "alert"
      }
      log_destination_type = "S3"
      log_type             = "ALERT"
    }

    # FLOWログ: すべてのネットワークフローのメタデータ
    log_destination_config {
      log_destination = {
        bucketName = data.aws_s3_bucket.firewall_logs.id
        prefix     = "flow"
      }
      log_destination_type = "S3"
      log_type             = "FLOW"
    }
  }
}
