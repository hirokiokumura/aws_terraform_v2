# Network ACL Module

このモジュールは、VPCのデフォルトNetwork ACLを管理し、インターネット向け通信(0.0.0.0/0)のルールのみを設定します。

## 特徴

- **デフォルトNACLを使用**: カスタムNACLではなく、デフォルトNACLを使用することでサブネット関連付けを簡素化
- **0.0.0.0/0のルールのみ**: インターネット向け通信のみを許可するシンプルな設計
- **VPC内部通信はSGで制御**: Network ACLではなく、セキュリティグループでVPC内部通信を制御する設計

## 設定されるルール

### Ingressルール（インバウンド: 0.0.0.0/0のみ）

| ルール番号 | プロトコル | ポート範囲 | 用途 |
|-----------|-----------|-----------|------|
| 90 | ICMP (Type 0) | - | Echo Reply (Pingレスポンス) |
| 91 | ICMP (Type 3) | - | Destination Unreachable (Path MTU Discovery) |
| 92 | ICMP (Type 11) | - | Time Exceeded (traceroute) |
| 100 | TCP | 443 | HTTPS |
| 200 | TCP | 32768-65535 | エフェメラルポート（HTTPSレスポンス用） |
| 210 | TCP | 53 | DNS TCP レスポンス |
| 220 | UDP | 53 | DNS UDP レスポンス |

### Egressルール（アウトバウンド: 0.0.0.0/0のみ）

| ルール番号 | プロトコル | ポート範囲 | 用途 |
|-----------|-----------|-----------|------|
| 90 | ICMP (Type 8) | - | Echo Request (Ping送信) |
| 100 | TCP | 443 | HTTPS |
| 110 | TCP | 53 | DNS TCP |
| 120 | UDP | 53 | DNS UDP |

## 使用方法

### 基本的な使い方

```hcl
module "network_acl" {
  source = "./modules/network_acl"

  default_network_acl_id = aws_vpc.primary.default_network_acl_id
  name                   = "default-nacl"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## 入力変数

| 変数名 | 型 | 必須 | デフォルト値 | 説明 |
|--------|------|------|--------------|------|
| `default_network_acl_id` | string | はい | - | VPCのデフォルトNetwork ACL ID |
| `name` | string | いいえ | "default-nacl" | デフォルトNetwork ACLの名前タグ |
| `tags` | map(string) | いいえ | {} | デフォルトNetwork ACLに適用する共通タグ |

## 出力

| 出力名 | 型 | 説明 |
|--------|------|------|
| `network_acl_id` | string | デフォルトNetwork ACLのID |
| `network_acl_arn` | string | デフォルトNetwork ACLのARN |

## 設計思想

### なぜデフォルトNACLを使用するのか？

1. **サブネット関連付けの簡素化**: デフォルトNACLは自動的にすべてのサブネットに関連付けられるため、明示的な関連付けが不要
2. **運用の簡素化**: カスタムNACLとの関連付け漏れによる意図しない設定を防止
3. **VPC内部通信はSGで制御**: Network ACLはステートレスなので、VPC内部通信の詳細な制御はセキュリティグループに任せる

### なぜ0.0.0.0/0のルールのみか？

1. **シンプルな設計**: インターネット向け通信のみをNetwork ACLで制御
2. **セキュリティグループとの分離**: VPC内部通信はセキュリティグループで制御し、責務を明確化
3. **保守性の向上**: ルールが少ないため、設定ミスのリスクが低い

## 注意事項

- このモジュールは`aws_default_network_acl`リソースを使用するため、VPCごとに1つのみ作成可能です
- デフォルトNACLに設定されるため、すべてのサブネットに自動的に適用されます
- VPC内部通信（Primary CIDR、Secondary CIDR間）の制御はセキュリティグループで行ってください
- エフェメラルポート範囲は32768-65535（AWS推奨範囲）を使用しています

## ライセンス

このモジュールはMITライセンスの下で公開されています。
