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

```bash
cd terraform/network-firewall-demo
terraform init
terraform apply
```

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

#### 3.1 テーブル作成

```bash
# DDLを出力
terraform output athena_ddl_alert
terraform output athena_ddl_flow
```

Athenaコンソールで上記DDLを実行してテーブルを作成します。

#### 3.2 サンプルクエリ

```bash
# クエリ例を出力
terraform output athena_sample_queries
```

**拒否されたドメインの確認:**
```sql
SELECT
  from_unixtime(event_timestamp) as timestamp,
  event.src_ip,
  event.dest_ip,
  event.alert.signature,
  event.alert.action
FROM network_firewall_logs.alert_logs
WHERE event.alert.action = 'blocked'
ORDER BY event_timestamp DESC
LIMIT 100;
```

**トラフィック統計:**
```sql
SELECT
  event.dest_ip,
  event.dest_port,
  COUNT(*) as connection_count,
  SUM(event.netflow.bytes) as total_bytes
FROM network_firewall_logs.flow_logs
GROUP BY event.dest_ip, event.dest_port
ORDER BY total_bytes DESC;
```

## 📊 ログの種類

### ALERT ログ
- ルールにマッチしたトラフィックの詳細
- 拒否されたドメインアクセスなど
- S3パス: `s3://<bucket>/alert/`

### FLOW ログ
- すべてのトラフィックフロー情報
- パケット数、バイト数など
- S3パス: `s3://<bucket>/flow/`

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

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_instance_profile.ssm_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ssm_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ssm_core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.test](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_networkfirewall_firewall.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall) | resource |
| [aws_networkfirewall_firewall_policy.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/networkfirewall_firewall_policy) | resource |
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
| [aws_security_group.ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |

## Inputs

No inputs.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ec2_instance_id"></a> [ec2\_instance\_id](#output\_ec2\_instance\_id) | EC2 Instance ID for SSM connection |
| <a name="output_firewall_endpoint_id"></a> [firewall\_endpoint\_id](#output\_firewall\_endpoint\_id) | Network Firewall Endpoint ID |
| <a name="output_test_commands"></a> [test\_commands](#output\_test\_commands) | Commands to test Network Firewall domain rules |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
