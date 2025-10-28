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
  ↓ ドメインルールでフィルタリング
  ↓ Route: 0.0.0.0/0 → IGW
  ↓ Logs → S3 (ALERT/FLOW)
Internet Gateway
  ↓
インターネット
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

- VPC、Subnet、IGW、Route Table作成権限
- Network Firewall作成権限
- S3バケット作成権限
- IAMロール作成権限
- CloudWatch Logs作成権限
- Athena、Glue作成権限

## 🧪 検証手順

### 1. ドメインルールのテスト

```bash
# 1. terraform outputから取得したインスタンスIDでSSM接続
aws ssm start-session --target <EC2_INSTANCE_ID> --region ap-northeast-1

# 2. 許可されるドメインをテスト (成功するはず)
curl -I https://example.com
curl -I https://aws.amazon.com

# 3. 拒否されるドメインをテスト (タイムアウトするはず)
curl -I https://google.com
```

### 2. S3ログの確認

```bash
# terraform outputからバケット名を取得
terraform output s3_log_bucket

# ALERTログ (拒否されたドメインなど)
aws s3 ls s3://<BUCKET_NAME>/alert/ --recursive

# FLOWログ (全トラフィックフロー)
aws s3 ls s3://<BUCKET_NAME>/flow/ --recursive
```

### 3. Athenaでログ分析

#### 3.1 テーブル作成（パーティション対応）

```bash
# DDLを出力
terraform output athena_ddl_alert
terraform output athena_ddl_flow
```

Athenaコンソールで上記DDLを実行してテーブルを作成します。

**重要:** テーブルはパーティションプロジェクション対応で、以下の利点があります：

- 自動的に `yyyy/mm/dd/HH` 形式のパーティションを認識
- `MSCK REPAIR TABLE` コマンド不要
- クエリ時のスキャンデータ量を大幅削減（コスト最適化）

#### 3.2 サンプルクエリ（パーティションフィルタ付き）

```bash
# クエリ例を出力（パーティション利用のベストプラクティス付き）
terraform output athena_sample_queries
```

**拒否されたドメインの確認（特定日のみスキャン）:**

```sql
SELECT
  from_unixtime(event_timestamp) as timestamp,
  event.src_ip,
  event.dest_ip,
  event.alert.signature,
  event.alert.action
FROM network_firewall_logs.alert_logs
WHERE event.alert.action = 'blocked'
  AND year = '2024'
  AND month = '01'
  AND day = '15'
ORDER BY event_timestamp DESC
LIMIT 100;
```

**トラフィック統計（パーティションフィルタで高速化）:**

```sql
SELECT
  event.dest_ip,
  event.dest_port,
  COUNT(*) as connection_count,
  SUM(event.netflow.bytes) as total_bytes
FROM network_firewall_logs.flow_logs
WHERE year = '2024'
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
- S3パス: `s3://<bucket>/AWSLogs/NetworkFirewall/alert/<account-id>/firewall/<region>/<firewall-name>/yyyy/mm/dd/HH/`

### FLOW ログ

- すべてのトラフィックフロー情報
- パケット数、バイト数など
- S3パス: `s3://<bucket>/AWSLogs/NetworkFirewall/flow/<account-id>/firewall/<region>/<firewall-name>/yyyy/mm/dd/HH/`

### CloudWatch Metrics

- ブロックされたドメインアクセス回数: `NetworkFirewall/BlockedDomainCount`
- 許可されたドメインアクセス回数: `NetworkFirewall/AllowedDomainCount`
- CloudWatchコンソールでリアルタイム監視可能

## 🧹 クリーンアップ

```bash
terraform destroy
```

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
| [aws_subnet.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zone"></a> [availability\_zone](#input\_availability\_zone) | Availability Zone for all resources | `string` | `"ap-northeast-1a"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_athena_database"></a> [athena\_database](#output\_athena\_database) | Athena database name for log analysis |
| <a name="output_athena_ddl_alert"></a> [athena\_ddl\_alert](#output\_athena\_ddl\_alert) | Athena DDL to create ALERT logs table with partitions |
| <a name="output_athena_ddl_flow"></a> [athena\_ddl\_flow](#output\_athena\_ddl\_flow) | Athena DDL to create FLOW logs table with partitions |
| <a name="output_athena_sample_queries"></a> [athena\_sample\_queries](#output\_athena\_sample\_queries) | Sample Athena queries for log analysis with partition filters |
| <a name="output_athena_workgroup"></a> [athena\_workgroup](#output\_athena\_workgroup) | Athena workgroup name |
| <a name="output_ec2_instance_id"></a> [ec2\_instance\_id](#output\_ec2\_instance\_id) | EC2 Instance ID for SSM connection |
| <a name="output_firewall_endpoint_id"></a> [firewall\_endpoint\_id](#output\_firewall\_endpoint\_id) | Network Firewall Endpoint ID |
| <a name="output_s3_log_bucket"></a> [s3\_log\_bucket](#output\_s3\_log\_bucket) | S3 bucket for Network Firewall logs |
| <a name="output_test_commands"></a> [test\_commands](#output\_test\_commands) | Commands to test Network Firewall domain rules and analyze logs |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
