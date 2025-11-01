# AWS Network Firewall Demo v4

AWS Network Firewallを使用したセキュアなネットワークアーキテクチャのデモ環境です。

## 目次

- [アーキテクチャ概要](#アーキテクチャ概要)
- [ネットワーク構成](#ネットワーク構成)
- [ルートテーブル詳細](#ルートテーブル詳細)
- [トラフィックフロー](#トラフィックフロー)
- [Network Firewall設定](#network-firewall設定)
- [デプロイ手順](#デプロイ手順)

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────────────┐
│                          VPC: 10.2.0.0/22                           │
│                     (network-firewall-demo-v4-vpc)                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │                    Internet Gateway                        │    │
│  │                  (nfw-demo-igw-v4)                        │    │
│  └─────────────────────┬─────────────────────────────────────┘    │
│                        │                                            │
│         ┌──────────────┴──────────────┐                           │
│         │                             │                           │
│         ▼ (IGW Route Table)           ▼                           │
│   ┌──────────────┐            ┌──────────────┐                   │
│   │ 10.2.0.0/24  │            │              │                   │
│   │ → NFW EP     │            │              │                   │
│   └──────────────┘            └──────────────┘                   │
│         │                             │                           │
│         ▼                             ▼                           │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │  Public Subnet      │    │ Firewall Subnet     │             │
│  │  10.2.0.0/24        │    │ 10.2.1.0/24         │             │
│  │                     │    │                     │             │
│  │  ┌──────────────┐   │    │  ┌──────────────┐  │             │
│  │  │ NAT Gateway  │   │    │  │   Network    │  │             │
│  │  │ (Public IP)  │   │    │  │   Firewall   │  │             │
│  │  └──────────────┘   │    │  │  Endpoint    │  │             │
│  │                     │    │  └──────────────┘  │             │
│  │  Route Table:       │    │  Route Table:      │             │
│  │  0.0.0.0/0 → NFW EP │    │  0.0.0.0/0 → IGW   │             │
│  └─────────────────────┘    └─────────────────────┘             │
│                                                                   │
│  ┌─────────────────────┐                                         │
│  │  Private Subnet     │                                         │
│  │  10.2.2.0/24        │                                         │
│  │                     │                                         │
│  │  ┌──────────────┐   │                                         │
│  │  │ EC2 Instance │   │                                         │
│  │  │ (Private IP) │   │                                         │
│  │  └──────────────┘   │                                         │
│  │                     │                                         │
│  │  ┌──────────────────────────────────┐                        │
│  │  │ VPC Endpoints (SSM)              │                        │
│  │  │ - ssm                            │                        │
│  │  │ - ssmmessages                    │                        │
│  │  │ - ec2messages                    │                        │
│  │  └──────────────────────────────────┘                        │
│  │                     │                                         │
│  │  Route Table:       │                                         │
│  │  0.0.0.0/0 → NAT GW │                                         │
│  └─────────────────────┘                                         │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## ネットワーク構成

### VPC

- **CIDR**: 10.2.0.0/22
- **リージョン**: ap-northeast-1
- **アベイラビリティゾーン**: ap-northeast-1a

### サブネット構成

| サブネット名 | CIDR | 用途 | 主要リソース |
|------------|------|------|-------------|
| Public Subnet | 10.2.0.0/24 | インターネット接続用 | NAT Gateway |
| Firewall Subnet | 10.2.1.0/24 | Network Firewall配置用 | Network Firewall Endpoint |
| Private Subnet | 10.2.2.0/24 | アプリケーション配置用 | EC2インスタンス、VPC Endpoints |

## ルートテーブル詳細

### 1. Public Subnet Route Table (`network-firewall-demo-v4-public-rtb`)

| 宛先 | ターゲット | 説明 |
|-----|----------|------|
| 10.2.0.0/22 | local | VPC内通信 |
| 0.0.0.0/0 | Network Firewall Endpoint | インターネット向けトラフィックをFirewallで検査 |

**役割**: Public SubnetからのEgressトラフィックをNetwork Firewallに送信

### 2. Firewall Subnet Route Table (`network-firewall-demo-v4-firewall-rtb`)

| 宛先 | ターゲット | 説明 |
|-----|----------|------|
| 10.2.0.0/22 | local | VPC内通信 |
| 0.0.0.0/0 | Internet Gateway | 検査済みトラフィックをインターネットへ |

**役割**: Firewall検査後のトラフィックをIGWに転送

### 3. Private Subnet Route Table (`network-firewall-demo-v4-private-rtb`)

| 宛先 | ターゲット | 説明 |
|-----|----------|------|
| 10.2.0.0/22 | local | VPC内通信 |
| 0.0.0.0/0 | NAT Gateway | インターネット向けトラフィックをNAT GWへ |

**役割**: Private SubnetからのEgressトラフィックをNAT Gatewayに送信

### 4. IGW Route Table (`network-firewall-demo-v4-igw-rtb`)

| 宛先 | ターゲット | 説明 |
|-----|----------|------|
| 10.2.0.0/24 | Network Firewall Endpoint | Public Subnet宛の戻りトラフィックをFirewallで検査 |

**役割**: インターネットからの戻りトラフィックをNetwork Firewallで検査

## トラフィックフロー

### Egress (Private Subnet → Internet)

EC2インスタンスからインターネットへのアクセス経路:

```
┌─────────────┐
│ EC2 Instance│  Private Subnet (10.2.2.0/24)
│ (10.2.2.x)  │
└──────┬──────┘
       │
       │ ① Private RTB: 0.0.0.0/0 → NAT Gateway
       │
       ▼
┌──────────────┐
│ NAT Gateway  │  Public Subnet (10.2.0.0/24)
│ (10.2.0.x)   │  送信元IPをNAT GWのElastic IPに変換
└──────┬───────┘
       │
       │ ② Public RTB: 0.0.0.0/0 → Network Firewall Endpoint
       │
       ▼
┌─────────────────┐
│ Network Firewall│  Firewall Subnet (10.2.1.0/24)
│ Endpoint        │  ドメインフィルタリングを実施
│ (10.2.1.x)      │  許可: .amazon.com, .amazonaws.com
└──────┬──────────┘
       │
       │ ③ Firewall RTB: 0.0.0.0/0 → Internet Gateway
       │
       ▼
┌──────────────┐
│ Internet     │
│ Gateway      │
└──────────────┘
       │
       ▼
    Internet
```

**ステップ詳細**:

1. **Private Subnet → NAT Gateway**
   - EC2インスタンス (10.2.2.x) がインターネット宛のパケットを送信
   - Private Route TableのデフォルトルートによりNAT Gatewayへ転送

2. **NAT Gateway → Network Firewall**
   - NAT GatewayがソースIPをElastic IPに変換
   - Public Route TableのデフォルトルートによりNetwork Firewall Endpointへ転送

3. **Network Firewall → Internet Gateway**
   - Network Firewallがドメインベースのフィルタリングを実施
   - 許可されたトラフィックのみFirewall Route TableのルートによりIGWへ転送

4. **Internet Gateway → Internet**
   - IGWがパケットをインターネットへルーティング

### Ingress (Internet → Public Subnet - 戻りトラフィック)

インターネットからの戻りトラフィック経路:

```
    Internet
       │
       ▼
┌──────────────┐
│ Internet     │
│ Gateway      │
└──────┬───────┘
       │
       │ ① IGW RTB: 10.2.0.0/24 → Network Firewall Endpoint
       │
       ▼
┌─────────────────┐
│ Network Firewall│  Firewall Subnet (10.2.1.0/24)
│ Endpoint        │  戻りトラフィックを検査
│ (10.2.1.x)      │
└──────┬──────────┘
       │
       │ ② パケットをPublic Subnetへ転送
       │
       ▼
┌──────────────┐
│ NAT Gateway  │  Public Subnet (10.2.0.0/24)
│ (10.2.0.x)   │  送信先IPを元のPrivate IPに変換
└──────┬───────┘
       │
       │ ③ Private Subnetへルーティング
       │
       ▼
┌─────────────┐
│ EC2 Instance│  Private Subnet (10.2.2.0/24)
│ (10.2.2.x)  │
└─────────────┘
```

**ステップ詳細**:

1. **Internet → Internet Gateway**
   - インターネットからNAT GatewayのElastic IP宛にパケットが到着

2. **Internet Gateway → Network Firewall**
   - IGW Route TableによりPublic Subnet (10.2.0.0/24) 宛のトラフィックをNetwork Firewall Endpointへ転送

3. **Network Firewall → NAT Gateway**
   - Network Firewallが戻りトラフィックを検査
   - 検査済みパケットをPublic SubnetのNAT Gatewayへ転送

4. **NAT Gateway → EC2 Instance**
   - NAT Gatewayが宛先IPを元のPrivate IP (10.2.2.x) に変換
   - VPC内ルーティングによりPrivate SubnetのEC2インスタンスへ配送

## Network Firewall設定

### ファイアウォールポリシー (`test-firewall-policy`)

- **ルール評価順序**: STRICT_ORDER（厳密な順序で評価）
- **デフォルトアクション**: `aws:drop_established`（確立された接続以外はドロップ）
- **Stateless処理**: すべてStateful Engineに転送 (`aws:forward_to_sfe`)

### ルールグループ (`allow-rule-group`)

**タイプ**: Stateful（ステートフル）
**容量**: 100
**ルールタイプ**: Domain List（ドメインリスト）

**許可ドメイン**:
- `.amazon.com`
- `.amazonaws.com`

**検査対象**:
- HTTP_HOST: HTTPホストヘッダー
- TLS_SNI: TLS Server Name Indication

**動作**:
- 上記ドメインへのHTTPS/HTTPアクセスを許可（ALLOWLIST）
- その他のドメインへのアクセスはブロック

### ログ設定

ログはS3バケット `apricot1224v1-nwf-logs` に保存されます。

**ログタイプ**:

1. **ALERTログ** (`alert/` prefix)
   - ルールにマッチしたトラフィック（許可/ブロック）の詳細
   - ブロックされたドメインへのアクセス記録
   - 場所: `s3://apricot1224v1-nwf-logs/alert/AWSLogs/{account-id}/`

2. **FLOWログ** (`flow/` prefix)
   - すべてのネットワークフローのメタデータ
   - 送信元/宛先IP、ポート、プロトコル、パケット数、バイト数など
   - 場所: `s3://apricot1224v1-nwf-logs/flow/AWSLogs/{account-id}/`

## デプロイ手順

### 前提条件

- AWS CLI設定済み（プロファイル: `ec2-user`）
- Terraform v1.0以上

### 初期化

```bash
cd terraform/network-firewall-demo-v4
export AWS_PROFILE=ec2-user
terraform init
```

### デプロイ

```bash
terraform plan
terraform apply
```

### リソース確認

```bash
# VPC確認
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=network-firewall-demo-v4-vpc" --profile ec2-user

# Network Firewall確認
aws network-firewall describe-firewall --firewall-name netfw --region ap-northeast-1 --profile ec2-user

# ルートテーブル確認
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" --profile ec2-user
```

### EC2インスタンスへの接続

SSM Session Managerを使用してEC2インスタンスに接続:

```bash
aws ssm start-session --target $(terraform output -raw ec2_instance_id) --profile ec2-user
```

### 通信テスト

EC2インスタンスから以下のコマンドで通信をテスト:

```bash
# 許可されたドメイン（成功するはず）
curl https://www.amazon.com
curl https://aws.amazon.com

# ブロックされるドメイン（失敗するはず）
curl https://www.google.com
curl https://www.example.com
```

ブロックされた通信はALERTログに記録されます。

### ログ確認

```bash
# ALERTログの確認
aws s3 ls s3://apricot1224v1-nwf-logs/alert/AWSLogs/ --recursive --profile ec2-user

# FLOWログの確認
aws s3 ls s3://apricot1224v1-nwf-logs/flow/AWSLogs/ --recursive --profile ec2-user

# ログのダウンロード（例）
aws s3 cp s3://apricot1224v1-nwf-logs/alert/AWSLogs/{account-id}/{region}/{year}/{month}/{day}/{log-file} . --profile ec2-user
```

### クリーンアップ

```bash
terraform destroy
```

## セキュリティ考慮事項

### 実装されているセキュリティ対策

1. **ネットワーク分離**
   - Private SubnetにEC2配置（直接インターネットアクセス不可）
   - Public Subnetは最小限のリソース（NAT Gatewayのみ）

2. **トラフィック検査**
   - すべてのEgress/IngressトラフィックをNetwork Firewallで検査
   - ドメインベースのフィルタリング（ホワイトリスト方式）

3. **ログ記録**
   - すべてのALERT（許可/ブロック）を記録
   - すべてのFLOW（ネットワークフロー）を記録
   - S3バケットに長期保存

4. **最小権限の原則**
   - EC2インスタンスにはSSM接続用の最小限の権限のみ付与
   - VPC Endpointsを使用してプライベート接続

5. **データ保護**
   - EC2ルートボリュームの暗号化
   - S3ログバケットの暗号化（AES256）
   - IMDSv2の強制

## トラブルシューティング

### EC2インスタンスに接続できない

**原因**: VPC Endpointsの設定を確認

```bash
# VPC Endpoints確認
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" --profile ec2-user
```

### インターネット接続できない

**原因1**: Network Firewallルールでブロックされている
- ALERTログを確認してブロック理由を特定

**原因2**: ルートテーブル設定の問題
```bash
# ルートテーブル確認
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" --profile ec2-user
```

### ログが記録されない

**原因**: S3バケットポリシーの権限不足
```bash
# バケットポリシー確認
aws s3api get-bucket-policy --bucket apricot1224v1-nwf-logs --profile ec2-user
```

## コスト見積もり

主要リソースの月額コスト（ap-northeast-1リージョン）:

| リソース | 月額コスト（概算） |
|---------|------------------|
| Network Firewall | ~$400 |
| NAT Gateway | ~$35 |
| VPC Endpoints (SSM×3) | ~$22 |
| EC2 t3.micro | ~$8 |
| S3ストレージ（ログ） | 変動（使用量による） |
| **合計** | **~$465** |

※ 実際のコストはデータ転送量やログ量により変動します

## 参考資料

- [AWS Network Firewall Documentation](https://docs.aws.amazon.com/network-firewall/)
- [AWS Network Firewall Deployment Models](https://docs.aws.amazon.com/network-firewall/latest/developerguide/arch-igw-ngw.html)
- [Terraform AWS Network Firewall Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall)
