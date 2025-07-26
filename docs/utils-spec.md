# Core Libraries Specification (Rust Edition)

## 概要

Cerberus Rustエディションは、モジュラー設計による高性能・型安全なコアライブラリシステムを提供します。非同期処理、構造化ログ、エラーハンドリングなど、現代的なシステム開発のベストプラクティスを実装しています。

## 設計原則

1. **メモリ安全性**: Rust所有権システムによる安全なメモリ管理
2. **型安全性**: コンパイル時型チェックによるエラー排除
3. **パフォーマンス**: ゼロコスト抽象化と効率的な非同期処理
4. **拡張性**: トレイト指向設計による機能拡張容易性

## コアライブラリ構成

### 1. エラーハンドリング (src/error.rs)

```rust
#[derive(Error, Debug)]
pub enum CerberusError {
    #[error("Configuration error: {0}")]
    Config(String),
    
    #[error("TOML parsing error in {file}: {source}")]
    TomlParse {
        file: String,
        #[source]
        source: toml::de::Error,
    },
    
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("Template rendering error: {0}")]
    Template(#[from] handlebars::RenderError),
}
```

### 2. 非同期処理基盤

- **tokio ランタイム**: 非ブロッキングI/O・並行処理
- **async/await**: 高効率な非同期プログラミングモデル
- **futures**: 並行タスク管理・エラー処理

### 3. 構造化ログ (tracing)

```rust
use tracing::{debug, info, warn, error, instrument};

#[instrument]
async fn generate_config() -> Result<(), CerberusError> {
    info!("Starting configuration generation");
    debug!("Processing TOML file: {}", config_path);
    // ...
}
```

### 2. ログ機能

#### ログ出力関数
```bash
log_message <level> <message>    # 基本ログ出力
log_debug <message>              # デバッグログ
log_info <message>               # 情報ログ  
log_warn <message>               # 警告ログ
log_error <message>              # エラーログ
```

#### ユーザー向け表示
```bash
print_success <message>          # 成功メッセージ (✓)
print_info <message>             # 情報メッセージ (ℹ)
print_warning <message>          # 警告メッセージ (⚠)
print_error <message>            # エラーメッセージ (✗)
print_step <message>             # 処理ステップ (→)
```

**仕様**:
- タイムスタンプ付きログ出力
- ログレベルによる出力制御
- カラー出力対応
- stderr/stdoutの適切な使い分け

### 3. エラーハンドリング

#### 基本エラー処理
```bash
die <message>                    # エラー終了
require_command <cmd> [hint]     # コマンド存在確認
require_file <file> [desc]       # ファイル存在確認
require_directory <dir> [desc]   # ディレクトリ確認/作成
```

#### 入力検証
```bash
validate_not_empty <value> <name>           # 空文字チェック
validate_number <value> <name> [min] [max]  # 数値検証
```

**仕様**:
- 統一されたエラーメッセージ形式
- 適切な終了コード設定
- 事前条件の検証
- わかりやすいエラー説明

### 4. ファイル・ディレクトリ操作

#### 安全な操作
```bash
safe_mkdir <dir> [mode]          # ディレクトリ作成
safe_remove <path>               # ファイル/ディレクトリ削除
safe_copy <src> <dest> [backup]  # ファイルコピー
```

#### ファイル情報
```bash
get_file_mtime <file>            # 更新時刻取得
is_file_newer <file1> <file2>    # ファイル更新比較
```

**仕様**:
- 自動バックアップ機能
- パーミッション管理
- クロスプラットフォーム対応
- 原子的操作の保証

### 5. 文字列操作

```bash
trim <string>                    # 空白文字除去
to_lower <string>                # 小文字変換
to_upper <string>                # 大文字変換
contains <string> <substring>    # 部分文字列検索
join_array <delimiter> <array>   # 配列結合
random_string [length] [charset] # ランダム文字列生成
```

**仕様**:
- UTF-8対応
- 特殊文字の適切な処理
- パフォーマンス重視の実装

### 6. Docker操作

#### Docker環境確認
```bash
check_docker                     # Docker動作確認
check_docker_compose             # Docker Compose確認
get_docker_compose_cmd           # Compose コマンド取得
```

#### Docker Compose操作
```bash
run_docker_compose <file> <args> # Compose実行
is_service_running <file> <svc>  # サービス状態確認
```

**仕様**:
- Docker/Docker Compose両対応
- エラーハンドリング強化
- ログ出力統合
- プラットフォーム差異の吸収

### 7. システム情報

```bash
get_system_info                  # システム情報取得  
is_root                          # root権限確認
get_current_user                 # 現在ユーザー取得
```

**仕様**:
- クロスプラットフォーム対応
- 詳細なシステム情報提供
- 権限管理サポート

### 8. ネットワーク操作

```bash
is_port_available <port>         # ポート使用状況確認
wait_for_service <host> <port> [timeout] [interval]  # サービス待機
```

**仕様**:
- タイムアウト機能
- 設定可能な待機間隔
- 詳細なログ出力

## 依存関係

### 必須コマンド
- `bash` (4.0以降)
- `date`
- `mkdir`
- `chmod`
- `stat`
- `tr`
- `cut`
- `grep`

### オプショナルコマンド
- `docker`
- `docker-compose`
- `openssl` (ランダム文字列生成用)
- `netstat` (ポート確認用)

## エラーハンドリング戦略

### エラー分類
1. **致命的エラー**: システム続行不可 → `die()`で即座に終了
2. **警告**: 動作に影響するが続行可能 → `log_warn()`で警告
3. **情報**: 正常動作の情報 → `log_info()`で記録

### 復旧戦略
- 自動復旧可能: ディレクトリ作成、権限設定など
- ユーザー介入必要: コマンド不足、権限不足など
- 設定エラー: 明確なエラーメッセージと修正方法提示

## パフォーマンス考慮事項

### 最適化
- 重い処理のキャッシュ化
- 不要なsubshell回避
- 効率的な文字列処理

### 制限事項
- 大容量ファイルの処理制限
- 同時実行時の競合回避
- メモリ使用量の監視

## テスト戦略

### 単体テスト
- 各関数の正常系・異常系テスト
- エラーハンドリングの検証
- 境界値テスト

### 統合テスト  
- 他ライブラリとの連携テスト
- プラットフォーム別動作確認
- パフォーマンステスト

### 対象環境
- Ubuntu 20.04/22.04
- macOS 12+
- WSL2 (Ubuntu)

## 使用例

```bash
#!/bin/bash
source "$(dirname "$0")/lib/core/utils.sh"

# ログ出力
log_info "Processing started"

# エラーハンドリング
require_command "docker" "curl -fsSL https://get.docker.com | sh"
require_file "$CONFIG_FILE" "configuration file"

# ファイル操作
safe_mkdir "$BUILT_DIR/proxy"
safe_copy "template.conf" "$BUILT_DIR/proxy/nginx.conf"

# Docker操作
check_docker
run_docker_compose "$BUILT_DIR/docker-compose.yaml" up -d

print_success "Setup completed successfully"
```

## 拡張計画

### Phase 1 (現在)
- 基本機能実装
- エラーハンドリング強化
- Docker操作サポート

### Phase 2 
- 設定キャッシュ機能
- 並列処理サポート
- 高度な検証機能

### Phase 3
- プラグインシステム連携
- 外部API連携サポート
- 高度なメトリクス収集

## メンテナンス指針

### コード品質
- ShellCheck による静的解析
- 関数の単一責任原則
- 適切なコメント記述

### 互換性
- 後方互換性の維持
- 段階的な機能追加
- 廃止予定機能の適切な警告

この仕様に基づいて、堅牢で再利用可能なユーティリティライブラリを提供します。