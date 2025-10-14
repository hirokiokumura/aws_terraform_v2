# Network ACL Module

VPCのカスタムNetwork ACL（NACL）を作成し、指定されたサブネットに関連付けるTerraformモジュールです。

## 設計方針

- **0.0.0.0/0によるポート制御**: VPC内部CIDR特定のルールを排除し、ポート番号のみで制御
- **ステートレス対応**: NACLはステートレスなため、リクエストとレスポンスの両方向を明示的に許可
- **最小権限の原則**: 必要なポートのみを明示的に許可し、デフォルトはすべて拒否

## 機能

### サポートされる通信パターン

1. **HTTPS通信** (443)
   - VPC → インターネット (NAT Gateway経由)
   - EC2/ECS → VPCエンドポイント (VPC内部通信)
   - エフェメラルポート (32768-65535) によるレスポンス受信

2. **DNS通信** (53)
   - TCP/UDP両方をサポート
   - インターネットDNSおよびVPC内部DNSに対応

3. **PostgreSQL通信** (5432)
   - EC2/ECS → Aurora PostgreSQL (VPC内部通信)
   - オプション機能（デフォルト無効）

4. **ICMP通信**
   - Ping (Echo Request/Reply)
   - Path MTU Discovery (Destination Unreachable)
   - traceroute (Time Exceeded)

### 拡張性

- **追加ルール**: `additional_ingress_rules`および`additional_egress_rules`変数で任意のルールを追加可能
- **フィーチャーフラグ**: 各プロトコル（HTTPS, DNS, PostgreSQL, ICMP）を個別に有効/無効化可能

## 使用方法

### 基本的な使用例

```hcl
module "network_acl" {
  source = "../modules/network_acl"

  vpc_id     = aws_vpc.primary.id
  nacl_name  = "custom-nacl"
  subnet_ids = [
    aws_subnet.primary_1a.id,
    aws_subnet.primary_1c.id,
    aws_subnet.secondary_1a.id,
    aws_subnet.secondary_1c.id,
  ]

  # PostgreSQLを有効化
  enable_postgresql = true

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
```

### PostgreSQL無効化の例

```hcl
module "network_acl" {
  source = "../modules/network_acl"

  vpc_id             = aws_vpc.primary.id
  subnet_ids         = [aws_subnet.example.id]
  enable_postgresql  = false  # PostgreSQLを無効化
}
```

### 追加ルールの例

```hcl
module "network_acl" {
  source = "../modules/network_acl"

  vpc_id     = aws_vpc.primary.id
  subnet_ids = [aws_subnet.example.id]

  # MySQLポートを追加
  additional_ingress_rules = [
    {
      rule_number = 400
      protocol    = "tcp"
      rule_action = "allow"
      cidr_block  = "0.0.0.0/0"
      from_port   = 3306
      to_port     = 3306
    }
  ]

  additional_egress_rules = [
    {
      rule_number = 400
      protocol    = "tcp"
      rule_action = "allow"
      cidr_block  = "0.0.0.0/0"
      from_port   = 3306
      to_port     = 3306
    }
  ]
}
```

## 入力変数

| 変数名 | 説明 | 型 | デフォルト値 | 必須 |
|--------|------|-----|-------------|------|
| `vpc_id` | VPCのID | `string` | - | ✅ |
| `subnet_ids` | NACLを関連付けるサブネットIDのリスト | `list(string)` | - | ✅ |
| `nacl_name` | Network ACLの名前 | `string` | `"custom-nacl"` | ❌ |
| `enable_https` | HTTPS (443) を許可するか | `bool` | `true` | ❌ |
| `enable_dns` | DNS (53) を許可するか | `bool` | `true` | ❌ |
| `enable_postgresql` | PostgreSQL (5432) を許可するか | `bool` | `false` | ❌ |
| `enable_icmp` | ICMP (Ping, Path MTU Discovery, traceroute) を許可するか | `bool` | `true` | ❌ |
| `additional_ingress_rules` | 追加のIngressルール | `list(object)` | `[]` | ❌ |
| `additional_egress_rules` | 追加のEgressルール | `list(object)` | `[]` | ❌ |
| `tags` | リソースに付与するタグ | `map(string)` | `{}` | ❌ |

### 追加ルールのオブジェクト構造

```hcl
{
  rule_number = number          # 必須: ルール番号 (400-499推奨)
  protocol    = string          # 必須: "tcp", "udp", "icmp", "-1"
  rule_action = string          # 必須: "allow" or "deny"
  cidr_block  = string          # 必須: "0.0.0.0/0"等
  from_port   = optional(number)  # TCPまたはUDPの場合必須
  to_port     = optional(number)  # TCPまたはUDPの場合必須
  icmp_type   = optional(number)  # ICMPの場合必須
  icmp_code   = optional(number)  # ICMPの場合必須
}
```

## 出力値

| 出力名 | 説明 | 型 |
|--------|------|----|
| `network_acl_id` | 作成されたNetwork ACLのID | `string` |
| `network_acl_arn` | 作成されたNetwork ACLのARN | `string` |
| `subnet_associations` | サブネットとNACLの関連付けリスト | `map(object)` |

## ルール番号体系

### Ingress（受信）

| ルール番号 | プロトコル | ポート/タイプ | 説明 |
|-----------|----------|--------------|------|
| 100 | TCP | 443 | HTTPS |
| 110 | TCP | 32768-65535 | Ephemeral (HTTPSレスポンス) |
| 120 | TCP | 53 | DNS TCP |
| 130 | UDP | 53 | DNS UDP |
| 140 | TCP | 5432 | PostgreSQL (オプション) |
| 150 | ICMP | Type 0 | Echo Reply (Ping) |
| 151 | ICMP | Type 3 | Destination Unreachable |
| 152 | ICMP | Type 11 | Time Exceeded (traceroute) |
| 400-499 | - | - | 追加ルール用（予約） |

### Egress（送信）

| ルール番号 | プロトコル | ポート/タイプ | 説明 |
|-----------|----------|--------------|------|
| 100 | TCP | 443 | HTTPS |
| 110 | TCP | 53 | DNS TCP |
| 120 | UDP | 53 | DNS UDP |
| 130 | TCP | 5432 | PostgreSQL (オプション) |
| 140 | ICMP | Type 8 | Echo Request (Ping) |
| 400-499 | - | - | 追加ルール用（予約） |

**注意**: Egress Ephemeralポート (32768-65535) は不要です。VPCから外部への通信では、Ingress Ephemeralのみで十分です。

## 重要な注意事項

### NACLのステートレス性

NACLはステートレスであるため、双方向の通信には明示的なルールが必要です：

- **VPC → インターネット (HTTPS)**
  - Egress 443: リクエスト送信
  - Ingress 32768-65535: レスポンス受信

- **EC2/ECS → Aurora PostgreSQL**
  - Egress 5432: 接続開始
  - Ingress 5432: 接続受け入れ

### セキュリティグループとの併用

NACLとセキュリティグループは併用されます：

- **NACL**: サブネットレベルのステートレスファイアウォール
- **セキュリティグループ**: インスタンスレベルのステートフルファイアウォール

両方の設定が必要です。NACLで許可されても、セキュリティグループで拒否されれば通信できません。

### デフォルトNACL

このモジュールはカスタムNACLを作成します。デフォルトNACLは別途管理する必要があります：

```hcl
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.primary.default_network_acl_id

  # すべて拒否（ルールを定義しない）

  tags = {
    Name = "default-nacl-deny-all"
  }
}
```

## 制限事項

- ルール番号100-399は予約済み（モジュール内部使用）
- 追加ルールはルール番号400-499を使用してください
- 1つのNACLあたり最大20個のIngressルールと20個のEgressルールまで（AWS制限）

## terraform-docsによる自動生成ドキュメント

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.16.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_network_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_association) | resource |
| [aws_network_acl_rule.additional_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.additional_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.egress_dns_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.egress_dns_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.egress_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.egress_icmp_echo_request](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.egress_postgresql](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_dns_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_dns_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_ephemeral](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_icmp_dest_unreachable](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_icmp_echo_reply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_icmp_time_exceeded](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.ingress_postgresql](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_egress_rules"></a> [additional\_egress\_rules](#input\_additional\_egress\_rules) | 追加のEgressルール | <pre>list(object({<br/>    rule_number = number<br/>    protocol    = string<br/>    rule_action = string<br/>    cidr_block  = string<br/>    from_port   = optional(number)<br/>    to_port     = optional(number)<br/>    icmp_type   = optional(number)<br/>    icmp_code   = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_additional_ingress_rules"></a> [additional\_ingress\_rules](#input\_additional\_ingress\_rules) | 追加のIngressルール | <pre>list(object({<br/>    rule_number = number<br/>    protocol    = string<br/>    rule_action = string<br/>    cidr_block  = string<br/>    from_port   = optional(number)<br/>    to_port     = optional(number)<br/>    icmp_type   = optional(number)<br/>    icmp_code   = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_enable_dns"></a> [enable\_dns](#input\_enable\_dns) | DNS (53) を許可するか | `bool` | `true` | no |
| <a name="input_enable_https"></a> [enable\_https](#input\_enable\_https) | HTTPS (443) を許可するか | `bool` | `true` | no |
| <a name="input_enable_icmp"></a> [enable\_icmp](#input\_enable\_icmp) | ICMP (Ping, Path MTU Discovery, traceroute) を許可するか | `bool` | `true` | no |
| <a name="input_enable_postgresql"></a> [enable\_postgresql](#input\_enable\_postgresql) | PostgreSQL (5432) を許可するか | `bool` | `false` | no |
| <a name="input_nacl_name"></a> [nacl\_name](#input\_nacl\_name) | Network ACLの名前 | `string` | `"custom-nacl"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | NACLを関連付けるサブネットIDのリスト | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | リソースに付与するタグ | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPCのID | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_network_acl_arn"></a> [network\_acl\_arn](#output\_network\_acl\_arn) | 作成されたNetwork ACLのARN |
| <a name="output_network_acl_id"></a> [network\_acl\_id](#output\_network\_acl\_id) | 作成されたNetwork ACLのID |
| <a name="output_subnet_associations"></a> [subnet\_associations](#output\_subnet\_associations) | サブネットとNACLの関連付けリスト |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
