# AWS Terraform Infrastructure

VPCネットワーキング、CloudTrailログ、Athena分析、AWS Configコンプライアンス監視を含むマルチサービス環境をプロビジョニングするTerraformプロジェクトです。

## 📋 目次

- [アーキテクチャ](#アーキテクチャ)
- [前提条件](#前提条件)
- [セットアップ](#セットアップ)
- [使用方法](#使用方法)
- [セキュリティとコンプライアンス](#セキュリティとコンプライアンス)
- [開発ワークフロー](#開発ワークフロー)

## 🏗️ アーキテクチャ

### ネットワーク構成

- **Primary CIDR (10.0.0.0/22)**
  - VPCエンドポイント（Athena、Bedrock、S3）
  - Private NAT Gateway
  - Aurora PostgreSQL

- **Secondary CIDR (10.1.4.0/24)**
  - EC2インスタンス
  - ECSタスク

### セキュリティ機能

- 最小権限の原則に基づくNetwork ACL設定
- CloudTrail API監査ログ
- AWS Config設定変更追跡
- Athena分析環境

## 🔧 前提条件

### 必須ツール

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [Git](https://git-scm.com/)
- [pre-commit](https://pre-commit.com/) (開発用)

### オプションツール（推奨）

- [tflint](https://github.com/terraform-linters/tflint) - Terraform Linter
- [trivy](https://trivy.dev/) - マルチスキャナー（IaC、脆弱性、機密情報）
- [checkov](https://www.checkov.io/) - セキュリティスキャナー
- [terraform-docs](https://terraform-docs.io/) - ドキュメント生成

## 🚀 セットアップ

### 1. リポジトリのクローン

```bash
git clone https://github.com/hirokiokumura/aws_terraform_v2.git
cd aws_terraform_v2
```

### 2. Pre-commitフックのインストール

```bash
# pre-commitのインストール（Homebrewの場合）
brew install pre-commit

# または pipの場合
pip install pre-commit

# pre-commitフックの有効化
pre-commit install
pre-commit install --hook-type commit-msg
```

### 3. 追加ツールのインストール（推奨）

```bash
# Homebrew（macOS/Linux）
brew install tflint trivy terraform-docs checkov

# または各ツール個別にインストール

# TFLint
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# Trivy
brew install trivy
# またはLinuxの場合
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Checkov
pip install checkov

# terraform-docs
brew install terraform-docs
```

### 4. TFLintプラグインの初期化

```bash
tflint --init
```

### 5. AWS認証情報の設定

```bash
aws configure
# または環境変数で設定
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-northeast-1"
```

## 📦 使用方法

### 基本的なTerraform操作

```bash
# Terraformディレクトリに移動
cd terraform

# 初期化（初回のみ）
terraform init

# 変更計画の確認
terraform plan -var="ip_address=YOUR_IP_HERE"

# インフラストラクチャの適用
terraform apply -var="ip_address=YOUR_IP_HERE"

# リソースの削除
terraform destroy
```

### 変数の設定

`ip_address`変数はセキュリティグループ設定に必要です：

**方法1: コマンドライン引数**

```bash
terraform plan -var="ip_address=1.2.3.4"
```

**方法2: 環境変数**

```bash
export TF_VAR_ip_address=1.2.3.4
terraform plan
```

**方法3: terraform.tfvarsファイル**

```bash
# terraform/terraform.tfvars を作成
echo 'ip_address = "1.2.3.4"' > terraform/terraform.tfvars
terraform plan
```

## 🔒 セキュリティとコンプライアンス

### Pre-commitフックによる自動チェック

コミット前に以下のチェックが自動実行されます：

1. **フォーマット検証**
   - 末尾の空白削除
   - ファイル末尾の改行追加
   - Terraformコードの自動フォーマット

2. **構文検証**
   - `terraform validate` による構文チェック
   - YAML/JSONファイルの検証

3. **セキュリティスキャン**
   - Checkovによるセキュリティベストプラクティスチェック
   - TFLintによる静的解析

4. **品質チェック**
   - 命名規則の検証
   - 未使用変数の検出
   - ドキュメントの自動生成

### 手動でのセキュリティスキャン

```bash
# Trivyによるスキャン（IaC、脆弱性、機密情報）
trivy config terraform/

# Checkovによるスキャン
checkov -d terraform/

# TFLintによる静的解析
cd terraform && tflint

# すべてのpre-commitフックを手動実行
pre-commit run --all-files
```

### Network ACLセキュリティ設計

- **最小権限の原則**: 必要なポートのみを明示的に許可
- **セグメンテーション**: Primary/Secondary CIDRで役割を分離
- **監査**: すべてのルールにコメントで用途を明記

## 🔄 開発ワークフロー

### 1. ブランチの作成

```bash
git checkout -b feature/your-feature-name
```

### 2. コードの変更

```bash
# Terraformファイルを編集
vim terraform/your_file.tf

# フォーマット確認
terraform fmt -recursive terraform/
```

### 3. コミット

```bash
# ステージング
git add terraform/your_file.tf

# コミット（pre-commitフックが自動実行されます）
git commit -m "feat: add new feature"

# もしpre-commitでエラーが出た場合
# 自動修正された変更を再度ステージング
git add .
git commit -m "feat: add new feature"
```

### 4. プッシュとPR作成

```bash
# リモートにプッシュ
git push -u origin feature/your-feature-name

# GitHub CLIでPR作成
gh pr create --title "feat: add new feature" --body "詳細な説明"
```

## 📚 主要な設定ファイル

| ファイル | 説明 |
|---------|------|
| `.pre-commit-config.yaml` | Pre-commitフックの設定 |
| `.tflint.hcl` | TFLintの設定 |
| `terraform/provider.tf` | Terraformプロバイダー設定 |
| `terraform/vpc.tf` | VPCネットワーク設定 |
| `terraform/network_acl.tf` | Network ACLセキュリティ設定 |
| `terraform/security_group.tf` | セキュリティグループ設定 |

## 🐛 トラブルシューティング

### Pre-commitフックが失敗する

```bash
# キャッシュをクリア
pre-commit clean

# フックを再インストール
pre-commit uninstall
pre-commit install

# 特定のフックをスキップ（緊急時のみ）
SKIP=terraform_checkov git commit -m "message"
```

### Terraform initが失敗する

```bash
# プラグインキャッシュをクリア
rm -rf terraform/.terraform
terraform init -upgrade
```

### TFLintプラグインエラー

```bash
# プラグインを再初期化
rm -rf ~/.tflint.d
tflint --init
```

## 📝 重要な注意点

- 状態はS3にリモート保存されています
- CloudTrailモジュールは適切なバケットポリシーが必要です
- VPCエンドポイントはAWSサービスへのプライベートアクセスを提供します
- セキュリティグループは制限的です - `ip_address`変数が実際のIPと一致することを確認してください

## 🤝 コントリビューション

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'feat: add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Requestを作成

## 📄 ライセンス

このプロジェクトは[MITライセンス](LICENSE)の下で公開されています。

## 👤 Author

[@hirokiokumura](https://github.com/hirokiokumura)
