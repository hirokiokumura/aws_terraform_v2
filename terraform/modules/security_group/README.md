# Security Group Module

このモジュールは、terraform-aws-modules/security-group/awsを使用したセキュリティグループのラッパーモジュールです。

## 特徴

- terraform-aws-modules/security-group/awsのベストプラクティスを活用
- CIDR ブロックベースのルール定義
- Prefix List IDを使用したEgressルール（S3 VPCエンドポイント等）
- 柔軟なルール追加機能

## 使用方法

```hcl
module "security_group" {
  source = "./modules/security_group"

  name        = "internal-https-sg"
  description = "Security group for internal HTTPS access"
  vpc_id      = aws_vpc.primary.id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "10.0.0.0/16"
      description = "Allow HTTPS from VPC"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow DNS TCP"
    }
  ]

  egress_with_prefix_list_ids = [
    {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = data.aws_prefix_list.s3.id
      description     = "Allow HTTPS to S3"
    }
  ]

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
```

## 設計方針

### terraform-aws-modules/security-group/awsを使用する理由

1. **ベストプラクティス**: AWSコミュニティで広く使用されている実績のあるモジュール
2. **メンテナンス性**: 個別のルールリソースではなく、モジュールでまとめて管理
3. **一貫性**: ルール定義の形式が統一され、可読性が向上
4. **拡張性**: 新しいルールタイプの追加が容易

### ルール構成

- **Ingressルール**: CIDR ブロックベースで定義
- **Egressルール**: CIDR ブロックとPrefix List IDの両方をサポート
- **追加ルール**: `additional_ingress_rules`で動的にルールを追加可能

## 参考

- [terraform-aws-modules/security-group/aws](https://registry.terraform.io/modules/terraform-aws-modules/security-group/aws/latest)
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_security_group"></a> [security\_group](#module\_security\_group) | terraform-aws-modules/security-group/aws | ~> 5.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_ingress_rules"></a> [additional\_ingress\_rules](#input\_additional\_ingress\_rules) | 追加のIngressルール | <pre>list(object({<br/>    from_port   = number<br/>    to_port     = number<br/>    protocol    = string<br/>    cidr_blocks = string<br/>    description = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_description"></a> [description](#input\_description) | セキュリティグループの説明 | `string` | `"Managed by Terraform"` | no |
| <a name="input_egress_with_cidr_blocks"></a> [egress\_with\_cidr\_blocks](#input\_egress\_with\_cidr\_blocks) | CIDR ブロックを使用したEgressルールのリスト | <pre>list(object({<br/>    from_port   = number<br/>    to_port     = number<br/>    protocol    = string<br/>    cidr_blocks = string<br/>    description = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_egress_with_prefix_list_ids"></a> [egress\_with\_prefix\_list\_ids](#input\_egress\_with\_prefix\_list\_ids) | Prefix List IDを使用したEgressルールのリスト | <pre>list(object({<br/>    from_port       = number<br/>    to_port         = number<br/>    protocol        = string<br/>    prefix_list_ids = string<br/>    description     = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_ingress_with_cidr_blocks"></a> [ingress\_with\_cidr\_blocks](#input\_ingress\_with\_cidr\_blocks) | CIDR ブロックを使用したIngressルールのリスト | <pre>list(object({<br/>    from_port   = number<br/>    to_port     = number<br/>    protocol    = string<br/>    cidr_blocks = string<br/>    description = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | セキュリティグループの名前 | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | リソースに付与するタグ | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | セキュリティグループを作成するVPC ID | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_security_group_arn"></a> [security\_group\_arn](#output\_security\_group\_arn) | セキュリティグループのARN |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | セキュリティグループのID |
| <a name="output_security_group_name"></a> [security\_group\_name](#output\_security\_group\_name) | セキュリティグループの名前 |
| <a name="output_security_group_vpc_id"></a> [security\_group\_vpc\_id](#output\_security\_group\_vpc\_id) | セキュリティグループが属するVPC ID |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
