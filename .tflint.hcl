# TFLint configuration for Terraform security and best practices

config {
  # 変数の未使用を検出
  force = false

  # 警告をエラーとして扱わない
  disabled_by_default = false

  # モジュールの検査タイプ（v0.54.0以降の新しい設定）
  # all: すべてのモジュールを検査
  # local: ローカルモジュールのみ検査
  # none: モジュール検査を無効化
  call_module_type = "all"
}

# AWS プラグイン設定
plugin "aws" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"

  # 深い検査を有効化
  deep_check = false # ⚠️ AWS API呼び出しによるコスト発生の可能性
}

# Terraform標準ルールセット
plugin "terraform" {
  enabled = true
  version = "0.5.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

# ============================================================================
# AWS推奨ルール
# ============================================================================

# リソースタグの必須化（現在はNameタグのみ必須）
# 将来的にEnvironment, ManagedByタグを追加予定
rule "aws_resource_missing_tags" {
  enabled = true
  tags = ["Name"]
}

# 無効なインスタンスタイプを検出
rule "aws_instance_invalid_type" {
  enabled = true
}

# 無効なAMI IDを検出
rule "aws_instance_invalid_ami" {
  enabled = true
}

# ============================================================================
# Terraform標準ルール
# ============================================================================

# 非推奨の構文を検出
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# 非推奨のインデックス構文を検出
rule "terraform_deprecated_index" {
  enabled = true
}

# 未使用の宣言を検出
rule "terraform_unused_declarations" {
  enabled = true
}

# コメントの構文エラーを検出
rule "terraform_comment_syntax" {
  enabled = true
}

# ドキュメント化されていない変数を検出
rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

# モジュールのバージョン指定を強制
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"  # セマンティックバージョニングを推奨
}

# 命名規則の検証
rule "terraform_naming_convention" {
  enabled = true

  # リソース名の形式
  resource {
    format = "snake_case"
  }

  # 変数名の形式
  variable {
    format = "snake_case"
  }

  # 出力名の形式
  output {
    format = "snake_case"
  }
}

# 必須バージョンの指定を強制
rule "terraform_required_version" {
  enabled = true
}

# プロバイダーバージョンの指定を強制
rule "terraform_required_providers" {
  enabled = true
}

# 型指定の強制
rule "terraform_typed_variables" {
  enabled = true
}

# Standardモジュールソースの使用
rule "terraform_standard_module_structure" {
  enabled = true
}

# ワークスペース指定の検証
rule "terraform_workspace_remote" {
  enabled = false  # ローカル開発用に無効化
}
