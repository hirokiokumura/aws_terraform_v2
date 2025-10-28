# AWS Network Firewall Demo with Athena Log Analysis

AWS Network Firewallのドメインルール検証とS3ログのAthena分析を体験できるハンズオン環境です。

## 📚 学習内容

- Network Firewallのドメインフィルタリング (ALLOWLIST/DENYLIST)
- S3へのログ出力設定 (ALERT/FLOW)
- Athenaを使ったログ分析とクエリ
- VPCルーティングとFirewall統合

## 🏗️ アーキテクチャ

```
EC2 (Private Subnet: 10.0.2.0/24)
  ↓ Route: 0.0.0.0/0 → Firewall Endpoint
Network Firewall (Firewall Subnet: 10.0.1.0/24)
  ↓ ドメインルールでフィルタリング (ALLOWLIST/DENYLIST)
  ↓ Route: 0.0.0.0/0 → NAT Gateway
  ↓ Logs → CloudWatch Logs (ALERT) / S3 (FLOW)
NAT Gateway (Public Subnet: 10.0.0.0/24)
  ↓ 送信元NAT変換 (Private IP → Public IP)
  ↓ Route: 0.0.0.0/0 → IGW
Internet Gateway
  ↓
インターネット

復路 (インターネット → EC2):
インターネット
  ↓
Internet Gateway
  ↓ Route: 10.0.2.0/24 → Firewall Endpoint
Network Firewall
  ↓ ステートフル検査 (確立済み接続の戻りパケット)
  ↓
EC2 (Private Subnet)
```

## 🚀 デプロイ手順

### 方法1: GitHub Actions（自動デプロイ）

このリポジトリには専用のGitHub Actionsワークフローが設定されています。

**トリガー条件:**

- `main`ブランチへのpush時に`terraform/network-firewall-demo/`配下の変更があった場合
- Pull Request作成時（Planのみ実行、コメントに結果を表示）
- 手動実行（workflow_dispatch）

**ワークフローファイル:** `.github/workflows/terraform-network-firewall.yml`

**mainブランチへのマージ時の動作:**

1. Terraform Format Check
2. Terraform Init
3. Terraform Validate
4. Terraform Apply（自動承認）
5. Outputs表示

### 方法2: ローカルでのデプロイ

```bash
cd terraform/network-firewall-demo
terraform init
terraform apply
```

**必要な権限:**

- VPC、Subnet、IGW、NAT Gateway、Route Table作成権限
- Network Firewall作成権限
- S3バケット作成権限
- CloudWatch Logs作成権限
- Elastic IP割り当て権限
- IAMロール作成権限
- Athena、Glue作成権限
- EC2インスタンス作成権限

## 🧪 検証手順

### 1. ドメインルールのテスト

**重要**: SSM接続はNAT Gateway経由でインターネット経由のSSMエンドポイントに接続します。VPCエンドポイントは使用していません（コスト削減のため）。

```bash
# 1. terraform outputから取得したインスタンスIDでSSM接続
# 注意: NAT GatewayとNetwork Firewallのデプロイ完了後に接続可能になります
aws ssm start-session --target <EC2_INSTANCE_ID> --region ap-northeast-1

# 2. 許可されるドメインをテスト (成功するはず)
curl -I https://example.com
curl -I https://aws.amazon.com

# 3. 拒否されるドメインをテスト (タイムアウトするはず)
curl -I https://google.com
```

**SSM接続の通信経路:**
```
EC2 (Private Subnet)
  ↓ 0.0.0.0/0 → Firewall Endpoint
Network Firewall
  ↓ ドメインフィルタリング (amazonaws.comは許可)
  ↓ 0.0.0.0/0 → NAT Gateway
NAT Gateway
  ↓ 送信元NAT変換
  ↓ 0.0.0.0/0 → IGW
Internet
  ↓
SSM Public Endpoint (ssm.ap-northeast-1.amazonaws.com)
```

### 2. CloudWatch Logsでアラート確認

```bash
# ALERTログはCloudWatch Logsに保存 (リアルタイムメトリクス用)
# terraform outputから確認
terraform output test_commands

# CloudWatch Logs Insightsでクエリ実行例:
# ロググループ: /aws/networkfirewall/<firewall-name>
# クエリ:
# fields @timestamp, event.src_ip, event.dest_ip, event.alert.signature, event.alert.action
# | filter event.alert.action = "blocked"
# | sort @timestamp desc
# | limit 100
```

### 3. S3ログの確認

```bash
# terraform outputからバケット名を取得
terraform output s3_log_bucket

# FLOWログ (全トラフィックフロー) - S3に保存
aws s3 ls s3://<BUCKET_NAME>/AWSLogs/NetworkFirewall/flow/ --recursive
```

### 4. Athenaでログ分析

#### 4.1 テーブル作成（パーティション対応）

```bash
# FLOWログのDDLを出力
terraform output athena_ddl_flow
```

Athenaコンソールで上記DDLを実行してテーブルを作成します。

**重要:** テーブルはパーティションプロジェクション対応で、以下の利点があります：

- 自動的に `yyyy/mm/dd/HH` 形式のパーティションを認識
- `MSCK REPAIR TABLE` コマンド不要
- クエリ時のスキャンデータ量を大幅削減（コスト最適化）

#### 4.2 サンプルクエリ（パーティションフィルタ付き）

```bash
# クエリ例を出力（パーティション利用のベストプラクティス付き）
terraform output athena_sample_queries
```

**トラフィック統計（パーティションフィルタで高速化）:**

```sql
SELECT
  event.dest_ip,
  event.dest_port,
  COUNT(*) as connection_count,
  SUM(event.netflow.bytes) as total_bytes
FROM network_firewall_logs.flow_logs
WHERE year = '2025'
  AND month = '01'
  AND day = '15'
GROUP BY event.dest_ip, event.dest_port
ORDER BY total_bytes DESC;
```

💡 **パーティションフィルタのポイント:**

- `WHERE year = '...' AND month = '...' AND day = '...'` を必ず含める
- スキャンデータ量が削減され、クエリが高速化＆低コストに
- クエリ実行前に「Data scanned」を確認する習慣をつける

## 📊 ログの種類

### ALERT ログ

- ルールにマッチしたトラフィックの詳細
- 拒否されたドメインアクセスなど
- **保存先**: CloudWatch Logs (リアルタイムメトリクス・アラート用)
- **ロググループ**: `/aws/networkfirewall/<firewall-name>`
- **用途**: CloudWatch Metrics、CloudWatch Logs Insightsでの分析

### FLOW ログ

- すべてのトラフィックフロー情報
- パケット数、バイト数など
- **保存先**: S3 (長期保存・Athena分析用)
- **S3パス**: `s3://<bucket>/AWSLogs/NetworkFirewall/flow/<account-id>/firewall/<region>/<firewall-name>/yyyy/mm/dd/HH/`
- **用途**: Athenaでのトラフィック統計分析

### CloudWatch Metrics

- ブロックされたドメインアクセス回数: `NetworkFirewall/BlockedDomainCount`
- 許可されたドメインアクセス回数: `NetworkFirewall/AllowedDomainCount`
- CloudWatchコンソールでリアルタイム監視可能

## 🧹 クリーンアップ

```bash
terraform destroy
```

## 🔧 トラブルシューティング

### SSM接続できない場合

**症状**: "SSM エージェントはオンラインではありません" エラー

**確認手順**:

1. **EC2インスタンスのステータス確認**
   ```bash
   # Systems Manager → Fleet Manager → Managed instances でインスタンスが表示されるか確認
   ```

2. **CloudWatch Logsでブロックログ確認**
   ```bash
   # ロググループ: /aws/networkfirewall/alert
   # クエリ例:
   fields @timestamp, event.alert.signature, event.dest_ip
   | filter event.alert.action = "blocked"
   | filter event.app_proto = "tls"
   | sort @timestamp desc
   | limit 20
   ```

3. **Network Firewallのルール確認**
   - ALLOWLIST: `.amazonaws.com` が含まれているか確認
   - DENYLIST: SSM関連ドメインが含まれていないか確認

4. **ルーティング確認**
   ```bash
   # Private SubnetのルートテーブルでFirewall Endpointへのルート確認
   # Firewall SubnetのルートテーブルでNAT Gatewayへのルート確認
   # Public SubnetのルートテーブルでIGWへのルート確認
   ```

5. **SSMエージェントログ確認（VPCエンドポイント経由でアクセスできる場合）**
   ```bash
   # EC2にログインできる場合
   sudo tail -f /var/log/amazon/ssm/amazon-ssm-agent.log
   sudo tail -f /var/log/amazon/ssm/errors.log
   ```

**解決策**:
- SSMエージェントは起動後数分かかる場合があります（最大5分程度待つ）
- Network Firewallのルールが反映されるまで数分かかる場合があります
- NAT Gatewayが正常に作成されているか確認（コンソールまたは `terraform state list`）

## 💡 学習ポイント

1. **Network Firewallの動作理解**
   - ドメインベースのフィルタリング
   - ALLOWLISTとDENYLISTの違い

2. **ログ分析スキル**
   - S3へのログ保存
   - Athenaでの構造化データ分析
   - セキュリティ監査のためのクエリ作成

3. **AWS統合**
   - VPCルーティングとFirewall統合
   - SSM Session Managerでの安全なアクセス

---

# network-firewall-demo

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ec2_security_group"></a> [ec2\_security\_group](#module\_ec2\_security\_group) | terraform-aws-modules/security-group/aws | ~> 5.0 |
| <a name="module_s3_athena_results"></a> [s3\_athena\_results](#module\_s3\_athena\_results) | terraform-aws-modules/s3-bucket/aws | ~> 4.0 |
| <a name="module_s3_firewall_logs"></a> [s3\_firewall\_logs](#module\_s3\_firewall\_logs) | terraform-aws-modules/s3-bucket/aws | ~> 4.0 |
| <a name="module_vpc_endpoint_security_group"></a> [vpc\_endpoint\_security\_group](#module\_vpc\_endpoint\_security\_group) | terraform-aws-modules/security-group/aws | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_athena_workgroup.firewall_analysis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_workgroup) | resource |
| [aws_cloudwatch_log_group.network_firewall_alert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_metric_filter.allowed_domains](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_log_metric_filter.blocked_domains](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_glue_catalog_database.firewall_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database) | resource |
| [aws_iam_instance_profile.ssm_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ssm_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ssm_core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.test](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_networkfirewall_firewall.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall) | resource |
| [aws_networkfirewall_firewall_policy.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall_policy) | resource |
| [aws_networkfirewall_logging_configuration.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_logging_configuration) | resource |
| [aws_networkfirewall_rule_group.allowlist](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_rule_group) | resource |
| [aws_networkfirewall_rule_group.denylist](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_rule_group) | resource |
| [aws_route.firewall_to_igw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.igw_to_firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_to_firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_s3_bucket_policy.firewall_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_subnet.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.firewall_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zone"></a> [availability\_zone](#input\_availability\_zone) | Availability Zone for all resources | `string` | `"ap-northeast-1a"` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | CloudWatch Logs retention period in days | `number` | `7` | no |
| <a name="input_ec2_ami_id"></a> [ec2\_ami\_id](#input\_ec2\_ami\_id) | AMI ID for EC2 instance (Amazon Linux 2023 recommended) | `string` | `"ami-0091f05e4b8ee6709"` | no |
| <a name="input_firewall_subnet_cidr"></a> [firewall\_subnet\_cidr](#input\_firewall\_subnet\_cidr) | CIDR block for firewall subnet | `string` | `"10.0.1.0/24"` | no |
| <a name="input_private_subnet_cidr"></a> [private\_subnet\_cidr](#input\_private\_subnet\_cidr) | CIDR block for private subnet | `string` | `"10.0.2.0/24"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name for resource naming and tagging | `string` | `"network-firewall-demo"` | no |
| <a name="input_public_subnet_cidr"></a> [public\_subnet\_cidr](#input\_public\_subnet\_cidr) | CIDR block for public subnet | `string` | `"10.0.0.0/24"` | no |
| <a name="input_s3_log_expiration_days"></a> [s3\_log\_expiration\_days](#input\_s3\_log\_expiration\_days) | S3 log expiration period in days | `number` | `90` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for VPC | `string` | `"10.0.0.0/22"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_athena_database"></a> [athena\_database](#output\_athena\_database) | Athena database name for log analysis |
| <a name="output_athena_ddl_flow"></a> [athena\_ddl\_flow](#output\_athena\_ddl\_flow) | Athena DDL to create FLOW logs table with partitions |
| <a name="output_athena_sample_queries"></a> [athena\_sample\_queries](#output\_athena\_sample\_queries) | Sample Athena queries for FLOW log analysis with partition filters |
| <a name="output_athena_workgroup"></a> [athena\_workgroup](#output\_athena\_workgroup) | Athena workgroup name |
| <a name="output_ec2_instance_id"></a> [ec2\_instance\_id](#output\_ec2\_instance\_id) | EC2 Instance ID for SSM connection |
| <a name="output_firewall_endpoint_id"></a> [firewall\_endpoint\_id](#output\_firewall\_endpoint\_id) | Network Firewall Endpoint ID |
| <a name="output_s3_log_bucket"></a> [s3\_log\_bucket](#output\_s3\_log\_bucket) | S3 bucket for Network Firewall logs |
| <a name="output_test_commands"></a> [test\_commands](#output\_test\_commands) | Commands to test Network Firewall domain rules and analyze logs |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
