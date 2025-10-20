# VPC Endpoint Module

このモジュールは、AWS VPCエンドポイント（ゲートウェイ型とインターフェース型）を柔軟に作成するためのTerraformモジュールです。

## 特徴

- **ゲートウェイ型とインターフェース型を明確に分離**: それぞれ専用の変数で定義するため、混乱がなく直感的
- **キーの重複を回避**: 同じサービス（例：S3）でゲートウェイ型とインターフェース型の両方を作成可能
- **柔軟なタグ付け**: 共通タグと個別タグの両方をサポート
- **豊富な出力**: エンドポイントのID、ARN、DNS情報などを出力

## 使用方法

### 基本的な使い方

```hcl
module "vpc_endpoints" {
  source = "./modules/vpc_endpoint"

  vpc_id = aws_vpc.primary.id

  # ゲートウェイ型エンドポイント
  gateway_endpoints = {
    s3 = {
      name         = "primary-gateway-s3"
      service_name = "com.amazonaws.ap-northeast-1.s3"
    }
    dynamodb = {
      name         = "primary-gateway-dynamodb"
      service_name = "com.amazonaws.ap-northeast-1.dynamodb"
    }
  }

  # インターフェース型エンドポイント
  interface_endpoints = {
    ssm = {
      name                = "primary-interface-ssm"
      service_name        = "com.amazonaws.ap-northeast-1.ssm"
      private_dns_enabled = true
    }
    ssmmessages = {
      name                = "primary-interface-ssmmessages"
      service_name        = "com.amazonaws.ap-northeast-1.ssmmessages"
      private_dns_enabled = true
    }
    ec2 = {
      name         = "primary-interface-ec2"
      service_name = "com.amazonaws.ap-northeast-1.ec2"
      additional_tags = {
        Environment = "production"
      }
    }
  }

  # ゲートウェイ型エンドポイント用のルートテーブル
  gateway_route_table_ids = [
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

  gateway_endpoints = {
    s3 = {
      name         = "s3-gateway"
      service_name = "com.amazonaws.ap-northeast-1.s3"
    }
    dynamodb = {
      name         = "dynamodb-gateway"
      service_name = "com.amazonaws.ap-northeast-1.dynamodb"
    }
  }

  gateway_route_table_ids = [
    aws_route_table.main.id
  ]
}
```

### インターフェース型のみを作成

```hcl
module "interface_endpoints" {
  source = "./modules/vpc_endpoint"

  vpc_id = aws_vpc.primary.id

  interface_endpoints = {
    ssm = {
      name         = "ssm-interface"
      service_name = "com.amazonaws.ap-northeast-1.ssm"
    }
    ec2messages = {
      name                = "ec2messages-interface"
      service_name        = "com.amazonaws.ap-northeast-1.ec2messages"
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
| `gateway_endpoints` | map(object) | いいえ | {} | 作成するゲートウェイ型VPCエンドポイントの定義マップ |
| `interface_endpoints` | map(object) | いいえ | {} | 作成するインターフェース型VPCエンドポイントの定義マップ |
| `gateway_route_table_ids` | list(string) | いいえ | [] | ゲートウェイ型エンドポイントに関連付けるルートテーブルIDのリスト |
| `subnet_ids` | list(string) | いいえ | [] | インターフェース型エンドポイントに関連付けるサブネットIDのリスト |
| `security_group_ids` | list(string) | いいえ | [] | インターフェース型エンドポイントに関連付けるセキュリティグループIDのリスト |
| `tags` | map(string) | いいえ | {} | すべてのVPCエンドポイントに適用する共通タグ |

### gateway_endpoints オブジェクトの構造

```hcl
{
  name            = string       # エンドポイント名（タグに使用）
  service_name    = string       # AWSサービス名（例: com.amazonaws.ap-northeast-1.s3）
  additional_tags = map(string)  # オプション。個別のエンドポイントに追加するタグ
}
```

### interface_endpoints オブジェクトの構造

```hcl
{
  name                = string       # エンドポイント名（タグに使用）
  service_name        = string       # AWSサービス名（例: com.amazonaws.ap-northeast-1.ssm）
  private_dns_enabled = bool         # オプション。デフォルト: true
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

- ゲートウェイ型エンドポイントを作成する場合は、`gateway_route_table_ids`を必ず指定してください
- インターフェース型エンドポイントを作成する場合は、`subnet_ids`と`security_group_ids`を必ず指定してください
- インターフェース型エンドポイントは、複数のサブネットに配置することで高可用性を実現できます
- プライベートDNSを有効にする場合（デフォルト）、VPCで`enableDnsHostnames`と`enableDnsSupport`が有効になっている必要があります

## 設計上の利点

### なぜゲートウェイ型とインターフェース型を分離するのか？

1. **キーの重複を回避**: 同じサービス（例：S3）でゲートウェイ型とインターフェース型の両方を作成する場合、単一のマップではキーが重複してしまいます
2. **明確な意図**: `gateway_endpoints`と`interface_endpoints`を分けることで、どのタイプのエンドポイントを作成しているか一目瞭然
3. **必須パラメータの違い**: ゲートウェイ型は`gateway_route_table_ids`、インターフェース型は`subnet_ids`と`security_group_ids`が必要という違いを明確化
4. **設定項目の違い**: インターフェース型のみに存在する`private_dns_enabled`などの設定を適切に扱える

## ライセンス

このモジュールはMITライセンスの下で公開されています。
