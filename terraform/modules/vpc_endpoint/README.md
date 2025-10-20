# VPC Endpoint Module

このモジュールは、AWS VPCエンドポイント（ゲートウェイ型とインターフェース型の両方）を柔軟に作成するためのTerraformモジュールです。

## 特徴

- **ゲートウェイ型とインターフェース型の両方に対応**: 単一のモジュールで両タイプのVPCエンドポイントを作成可能
- **リスト形式の設定**: エンドポイント定義をマップで渡すだけで、タイプに応じて自動的に分類して作成
- **柔軟なタグ付け**: 共通タグと個別タグの両方をサポート
- **豊富な出力**: エンドポイントのID、ARN、DNS情報などを出力

## 使用方法

### 基本的な使い方

```hcl
module "vpc_endpoints" {
  source = "./modules/vpc_endpoint"

  vpc_id = aws_vpc.primary.id

  # VPCエンドポイントの定義（リスト形式）
  endpoints = {
    # ゲートウェイ型エンドポイント
    s3 = {
      name         = "primary-gateway-s3"
      service_name = "com.amazonaws.ap-northeast-1.s3"
      type         = "Gateway"
    }

    # インターフェース型エンドポイント
    ssm = {
      name                = "primary-interface-ssm"
      service_name        = "com.amazonaws.ap-northeast-1.ssm"
      type                = "Interface"
      private_dns_enabled = true
    }

    ssmmessages = {
      name         = "primary-interface-ssmmessages"
      service_name = "com.amazonaws.ap-northeast-1.ssmmessages"
      type         = "Interface"
    }

    ec2 = {
      name         = "primary-interface-ec2"
      service_name = "com.amazonaws.ap-northeast-1.ec2"
      type         = "Interface"
      additional_tags = {
        Environment = "production"
      }
    }
  }

  # ゲートウェイ型エンドポイント用のルートテーブル
  route_table_ids = [
    aws_route_table.rtb_subnet_primary_1a.id,
    aws_route_table.rtb_subnet_primary_1c.id
  ]

  # インターフェース型エンドポイント用のサブネット
  subnet_ids = [
    aws_subnet.primary_1a.id,
    aws_subnet.primary_1c.id
  ]

  # インターフェース型エンドポイント用のセキュリティグループ
  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]

  # 共通タグ
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### ゲートウェイ型のみを作成

```hcl
module "gateway_endpoints" {
  source = "./modules/vpc_endpoint"

  vpc_id = aws_vpc.primary.id

  endpoints = {
    s3 = {
      name         = "s3-gateway"
      service_name = "com.amazonaws.ap-northeast-1.s3"
      type         = "Gateway"
    }
    dynamodb = {
      name         = "dynamodb-gateway"
      service_name = "com.amazonaws.ap-northeast-1.dynamodb"
      type         = "Gateway"
    }
  }

  route_table_ids = [
    aws_route_table.main.id
  ]
}
```

### インターフェース型のみを作成

```hcl
module "interface_endpoints" {
  source = "./modules/vpc_endpoint"

  vpc_id = aws_vpc.primary.id

  endpoints = {
    ssm = {
      name         = "ssm-interface"
      service_name = "com.amazonaws.ap-northeast-1.ssm"
      type         = "Interface"
    }
    ec2messages = {
      name                = "ec2messages-interface"
      service_name        = "com.amazonaws.ap-northeast-1.ec2messages"
      type                = "Interface"
      private_dns_enabled = false
    }
  }

  subnet_ids = [
    aws_subnet.private_1a.id,
    aws_subnet.private_1c.id
  ]

  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]
}
```

## 入力変数

| 変数名 | 型 | 必須 | デフォルト値 | 説明 |
|--------|------|------|--------------|------|
| `vpc_id` | string | はい | - | VPCエンドポイントを作成するVPCのID |
| `endpoints` | map(object) | はい | - | 作成するVPCエンドポイントの定義マップ |
| `route_table_ids` | list(string) | いいえ | [] | ゲートウェイ型エンドポイントに関連付けるルートテーブルIDのリスト |
| `subnet_ids` | list(string) | いいえ | [] | インターフェース型エンドポイントに関連付けるサブネットIDのリスト |
| `security_group_ids` | list(string) | いいえ | [] | インターフェース型エンドポイントに関連付けるセキュリティグループIDのリスト |
| `tags` | map(string) | いいえ | {} | すべてのVPCエンドポイントに適用する共通タグ |

### endpoints オブジェクトの構造

```hcl
{
  name                = string       # エンドポイント名（タグに使用）
  service_name        = string       # AWSサービス名（例: com.amazonaws.ap-northeast-1.s3）
  type                = string       # "Gateway" または "Interface"
  private_dns_enabled = bool         # オプション。Interface型の場合のみ有効。デフォルト: true
  additional_tags     = map(string)  # オプション。個別のエンドポイントに追加するタグ
}
```

## 出力

| 出力名 | 型 | 説明 |
|--------|------|------|
| `gateway_endpoint_ids` | map(string) | ゲートウェイ型エンドポイントのIDマップ |
| `gateway_endpoint_arns` | map(string) | ゲートウェイ型エンドポイントのARNマップ |
| `interface_endpoint_ids` | map(string) | インターフェース型エンドポイントのIDマップ |
| `interface_endpoint_arns` | map(string) | インターフェース型エンドポイントのARNマップ |
| `interface_endpoint_dns_entries` | map(object) | インターフェース型エンドポイントのDNSエントリマップ |
| `interface_endpoint_network_interface_ids` | map(list(string)) | インターフェース型エンドポイントのネットワークインターフェースIDマップ |
| `all_endpoint_ids` | map(string) | すべてのエンドポイント（ゲートウェイ型とインターフェース型）のIDマップ |

## よくあるAWSサービスのエンドポイント名

### ゲートウェイ型

- S3: `com.amazonaws.<region>.s3`
- DynamoDB: `com.amazonaws.<region>.dynamodb`

### インターフェース型（一部抜粋）

- EC2: `com.amazonaws.<region>.ec2`
- SSM: `com.amazonaws.<region>.ssm`
- SSM Messages: `com.amazonaws.<region>.ssmmessages`
- EC2 Messages: `com.amazonaws.<region>.ec2messages`
- Secrets Manager: `com.amazonaws.<region>.secretsmanager`
- CloudWatch Logs: `com.amazonaws.<region>.logs`
- ECR API: `com.amazonaws.<region>.ecr.api`
- ECR DKR: `com.amazonaws.<region>.ecr.dkr`
- Lambda: `com.amazonaws.<region>.lambda`

## 注意事項

- ゲートウェイ型エンドポイントを作成する場合は、`route_table_ids`を必ず指定してください
- インターフェース型エンドポイントを作成する場合は、`subnet_ids`と`security_group_ids`を必ず指定してください
- インターフェース型エンドポイントは、複数のサブネットに配置することで高可用性を実現できます
- プライベートDNSを有効にする場合（デフォルト）、VPCで`enableDnsHostnames`と`enableDnsSupport`が有効になっている必要があります

## ライセンス

このモジュールはMITライセンスの下で公開されています。
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.17.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_vpc_endpoint.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_endpoints"></a> [endpoints](#input\_endpoints) | 作成するVPCエンドポイントのマップ。<br/>キー: エンドポイントの識別子<br/>値: {<br/>  name         = エンドポイント名（タグに使用）<br/>  service\_name = AWSサービス名（例: com.amazonaws.ap-northeast-1.s3）<br/>  type         = エンドポイントタイプ（"Gateway" または "Interface"）<br/>  private\_dns\_enabled = プライベートDNSを有効化するか（Interface型の場合のみ、オプション、デフォルト: true）<br/>  additional\_tags = 追加のタグ（オプション）<br/>} | <pre>map(object({<br/>    name                = string<br/>    service_name        = string<br/>    type                = string<br/>    private_dns_enabled = optional(bool, true)<br/>    additional_tags     = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_route_table_ids"></a> [route\_table\_ids](#input\_route\_table\_ids) | Gateway型エンドポイントに関連付けるルートテーブルIDのリスト | `list(string)` | `[]` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Interface型エンドポイントに関連付けるセキュリティグループIDのリスト | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Interface型エンドポイントに関連付けるサブネットIDのリスト | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | すべてのVPCエンドポイントに適用する共通タグ | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPCエンドポイントを作成するVPCのID | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_all_endpoint_ids"></a> [all\_endpoint\_ids](#output\_all\_endpoint\_ids) | すべてのVPCエンドポイント（ゲートウェイ型とインターフェース型）のIDマップ |
| <a name="output_gateway_endpoint_arns"></a> [gateway\_endpoint\_arns](#output\_gateway\_endpoint\_arns) | 作成されたゲートウェイ型VPCエンドポイントのARNマップ |
| <a name="output_gateway_endpoint_ids"></a> [gateway\_endpoint\_ids](#output\_gateway\_endpoint\_ids) | 作成されたゲートウェイ型VPCエンドポイントのIDマップ |
| <a name="output_interface_endpoint_arns"></a> [interface\_endpoint\_arns](#output\_interface\_endpoint\_arns) | 作成されたインターフェース型VPCエンドポイントのARNマップ |
| <a name="output_interface_endpoint_dns_entries"></a> [interface\_endpoint\_dns\_entries](#output\_interface\_endpoint\_dns\_entries) | 作成されたインターフェース型VPCエンドポイントのDNSエントリマップ |
| <a name="output_interface_endpoint_ids"></a> [interface\_endpoint\_ids](#output\_interface\_endpoint\_ids) | 作成されたインターフェース型VPCエンドポイントのIDマップ |
| <a name="output_interface_endpoint_network_interface_ids"></a> [interface\_endpoint\_network\_interface\_ids](#output\_interface\_endpoint\_network\_interface\_ids) | 作成されたインターフェース型VPCエンドポイントのネットワークインターフェースIDマップ |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
