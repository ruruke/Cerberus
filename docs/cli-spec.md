# Cerberus CLI Specification (Rust Edition)

## 概要

CerberusはRust製のコマンドラインツールで、TOML設定ファイルから多層プロキシアーキテクチャを自動生成します。高性能・メモリセーフ・型安全な実装により、設定生成からサービス管理まで統合的に提供します。

## 設計原則

1. **型安全性**: Rust型システムによるコンパイル時エラー検出
2. **パフォーマンス**: ゼロコスト抽象化による高速処理
3. **信頼性**: Result型による適切なエラーハンドリング
4. **拡張性**: モジュラー設計による機能追加容易性

## コマンド体系

### 基本構文
```bash
cargo run -- <command> [options] [arguments]
# または
./target/release/cerberus <command> [options] [arguments]
```

### グローバルオプション
```bash
-c, --config <file>     # 設定ファイル指定（デフォルト: config.toml）
-v, --verbose           # 詳細出力
-q, --quiet             # 静寂モード  
-h, --help              # ヘルプ表示
-V, --version           # バージョン表示
```

## コマンド仕様

### 1. 設定管理コマンド

#### generate - 設定生成
```bash
cargo run -- generate
```

**機能**:
- config.tomlから全設定ファイルを非同期生成
- docker-compose.yaml, Dockerfile, プロキシ設定等を型安全に出力
- built/ディレクトリに生成物を配置
- エラー時はResult型によるエラー伝播

**例**:
```bash
cargo run -- generate
RUST_LOG=debug cargo run -- generate  # デバッグログ付き
```

#### validate - 設定検証
```bash
cargo run -- validate
```

**機能**:
- config.tomlの構文・論理チェック（serde使用）
- 型レベルでの必須項目存在確認
- 値の範囲・形式検証（コンパイル時＋実行時）

**例**:
```bash
cargo run -- validate
```

#### clean - クリーンアップ
```bash
cargo run -- clean
```

**機能**:
- built/ディレクトリの内容削除
- 生成ファイルの安全な除去

**例**:
```bash
cargo run -- clean
```

### 2. 開発・テストコマンド

#### test - テスト実行
```bash
cargo test
cargo test config           # 設定テストのみ
cargo test docker_compose   # Docker Composeテストのみ
```

**機能**:
- 包括的なテストスイート実行（28+テスト）
- TDD方式による品質保証
- 統合テスト・単体テスト両対応

**例**:
```bash
cargo test                    # 全テスト実行
cargo test -- --nocapture   # テスト出力表示
cargo watch -x test         # ファイル変更時自動テスト
```

#### build - ビルド
```bash
cargo build                 # デバッグビルド
cargo build --release       # リリースビルド（最適化）
cargo install --path .      # バイナリインストール
```

**機能**:
- Rustコンパイル・最適化
- 実行可能バイナリ生成
- 型チェック・エラー検出

#### check - 静的解析
```bash
cargo check                 # 型チェック
cargo clippy               # リント
cargo fmt                  # フォーマット
cargo audit                # セキュリティ監査
```

**機能**:
- コンパイル時エラー検出
- コード品質チェック
- セキュリティ脆弱性検出

### 3. ドキュメント・メタデータ

#### doc - ドキュメント生成
```bash
cargo doc --open           # API ドキュメント生成・表示
cargo doc --no-deps        # 依存関係除外版
```

**機能**:
- rustdoc による API ドキュメント生成
- ブラウザでの自動表示

#### version - バージョン情報
```bash
cargo run -- --version     # アプリケーションバージョン
cargo --version            # Rustツールチェーンバージョン
```

**機能**:
- バージョン・ビルド情報表示
- 依存関係情報表示

## エラーハンドリング

### 終了コード
- `0`: 正常終了
- `1`: 一般的なエラー（CerberusError）
- `101`: 設定エラー（Config解析失敗）
- `102`: TOML解析エラー
- `103`: I/Oエラー（ファイル操作失敗）
- `104`: テンプレートエラー（Handlebars）

### エラーメッセージ形式（thiserror使用）
```
Error: Configuration error: Proxy proxy-layer1 name cannot be empty

Caused by:
    0: TOML parsing error in config.toml
    1: invalid value: expected string, found null at line 12 column 5

Help: Check config.toml syntax and ensure all required fields are present
```

## 設定ファイル連携

### 設定ファイル検索順序
1. `--config`オプション指定ファイル
2. `CERBERUS_CONFIG`環境変数
3. `./config.toml`（カレントディレクトリ）
4. `./config-example.toml`（存在する場合）

### 環境変数
```bash
CERBERUS_CONFIG=/path/to/config.toml
CERBERUS_DEBUG=true
CERBERUS_LOG_LEVEL=DEBUG
DOCKER_COMPOSE_FILE=/path/to/docker-compose.yaml
```

## ログ出力

### ログレベル
- `DEBUG`: デバッグ情報
- `INFO`: 一般情報
- `WARN`: 警告
- `ERROR`: エラー

### ログ形式
```
[LEVEL] YYYY-MM-DD HH:MM:SS <message>
```

### ログ出力先
- 標準出力: 一般メッセージ
- 標準エラー: エラー・警告メッセージ
- ファイル: `built/logs/cerberus.log`（設定可能）

## パフォーマンス考慮事項

### 最適化
- 設定キャッシュによる高速化
- 並列処理での処理時間短縮
- 不必要な処理のスキップ

### 制限事項
- 大規模構成での処理時間
- メモリ使用量の上限
- 同時実行数の制限

## セキュリティ

### 権限管理
- Docker操作に必要な権限確認
- ファイル作成権限の検証
- 実行ユーザーの適切性チェック

### 機密情報
- パスワード・キーの安全な取り扱い
- ログファイルでの機密情報マスク
- 設定ファイルの権限設定

## 使用例

### 基本的な使用フロー
```bash
# 1. 初期設定
./cerberus.sh init --template misskey --interactive

# 2. 設定生成
./cerberus.sh generate --validate

# 3. サービス起動
./cerberus.sh up --detach --build

# 4. 状態確認
./cerberus.sh status --detailed

# 5. 自動スケーリング有効化
./cerberus.sh scale auto --enable

# 6. ログ監視
./cerberus.sh logs --follow
```

### トラブルシューティング
```bash
# 設定検証
./cerberus.sh validate --strict

# ヘルスチェック
./cerberus.sh health --timeout 30

# 詳細ログ確認
./cerberus.sh logs --tail 100 --since "1 hour ago"

# サービス再起動
./cerberus.sh restart --timeout 60

# クリーンアップ
./cerberus.sh clean --all --confirm
```

## 拡張性

### プラグインシステム
- カスタムコマンドの追加
- 外部ツールとの連携
- 設定生成の拡張

### API連携
- REST API経由での操作
- Webhook通知機能
- 外部監視システム連携

この仕様に基づいて、使いやすく強力なCLIインターフェースを提供します。