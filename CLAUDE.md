# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

これは、VPCネットワーキング、CloudTrailログ、Athena分析、AWS Configコンプライアンス監視を含むマルチサービス環境をプロビジョニングするTerraformを使用した包括的なAWSインフラストラクチャプロジェクトです。セキュリティとコンプライアンスを考慮した設計で、マルチアベイラビリティーゾーンと包括的なログ機能を備えています。

## アーキテクチャ

Terraform設定は `terraform/` ディレクトリ内のサービス別ファイルに整理されています：

### コアインフラストラクチャ
- `provider.tf` - リモート状態管理用S3バックエンド付きのAWSプロバイダー設定
- `vpc.tf` - プライマリ(10.0.0.0/22)とセカンダリ(10.1.4.0/24) CIDRブロック、S3 VPCエンドポイント付きのマルチAZ VPC
- `security_group.tf` - VPCおよび外部アクセス用のHTTPS イングレスルール付きセキュリティグループ
- `iam_role.tf` - EC2、自動化、サービス統合(SSM、Config、S3)用のIAMロール
- `variables.tf` - IPアドレス設定を含む入力変数

### ログ記録とコンプライアンス
- `cloudtrail.tf` - `modules/cloudtrail/`のモジュラーアプローチを使用したCloudTrail設定
- `config.tf` - 設定スナップショット用S3バケット付きのAWS Configサービス
- `athena.tf` - CloudWatchメトリクス付きログ分析用のAthenaワークグループ

### GitHub Actions統合
- `assume_role_policy.json` - GitHub OIDCプロバイダー統合用のIAM信頼ポリシーテンプレート
- リモート状態はS3バケットに保存: `apricot1224v1-terraform`

## 主要な設定詳細

- **マルチAZ設定**: リソースはap-northeast-1aとap-northeast-1cに配置
- **ネットワークセグメンテーション**: 専用ルートテーブル付きのプライマリおよびセカンダリCIDRブロック
- **状態管理**: 状態ロック付きS3を使用したリモートバックエンド
- **セキュリティ**: `ip_address`変数によるIP制限アクセス、プライベートAWS APIアクセス用VPCエンドポイント
- **コンプライアンス**: API インサイト付きCloudTrail、設定ドリフト検出用のAWS Config

## 基本コマンド

### Terraform操作
```bash
# Terraformを初期化 (terraform/ ディレクトリから実行)
cd terraform && terraform init

# インフラストラクチャの変更を計画 (ip_address変数が必要)
cd terraform && terraform plan -var="ip_address=YOUR_IP_HERE"

# インフラストラクチャの変更を適用
cd terraform && terraform apply -var="ip_address=YOUR_IP_HERE"

# インフラストラクチャを削除
cd terraform && terraform destroy

# 設定を検証
cd terraform && terraform validate

# Terraformファイルをフォーマット
cd terraform && terraform fmt -recursive
```

### PR自動化
```bash
# 現在の変更をPRとして作成
gh pr create --title "変更のタイトル" --body "変更の詳細説明"

# 自動でブランチ作成してPR作成（Claude使用時）
# 変更をステージング → コミット → プッシュ → PR作成を自動実行
```

### 変数設定
`ip_address`変数はセキュリティグループ設定に必要です。以下の方法で設定できます：
- コマンドライン: `-var="ip_address=1.2.3.4"`
- 環境変数: `TF_VAR_ip_address=1.2.3.4`
- 変数ファイル: `ip_address = "1.2.3.4"`を含む`terraform.tfvars`を作成

## 重要な注意点

- 状態はS3にリモート保存されています - 適切なAWS認証情報が設定されていることを確認してください
- CloudTrailモジュールは`policy.json`で定義された適切なバケットポリシーが必要です
- VPCエンドポイントはAWSサービスへのプライベートアクセスを提供し、NATゲートウェイのコストを削減します
- セキュリティグループは制限的です - `ip_address`変数が実際のIPと一致することを確認してください
- すべてのリソースはコスト配分と管理のために一貫したタグ付けを使用しています
