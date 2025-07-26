# Cerberus CLI Specification (cerberus.sh)

## 概要

`cerberus.sh`はCerberusシステムの統合コマンドラインインターフェースです。設定生成からサービス管理まで、すべての操作を単一のコマンドで提供します。

## 設計原則

1. **統合性**: 全機能への単一エントリーポイント
2. **使いやすさ**: 直感的なコマンド体系
3. **堅牢性**: 包括的なエラーハンドリング
4. **拡張性**: 新しいサブコマンドの追加が容易

## コマンド体系

### 基本構文
```bash
./cerberus.sh <command> [subcommand] [options] [arguments]
```

### グローバルオプション
```bash
-c, --config <file>     # 設定ファイル指定（デフォルト: config.toml）
-v, --verbose           # 詳細出力
-q, --quiet             # 静寂モード
-h, --help              # ヘルプ表示
--version               # バージョン表示
--debug                 # デバッグモード
```

## コマンド仕様

### 1. 設定管理コマンド

#### generate - 設定生成
```bash
./cerberus.sh generate [--force] [--validate]
```

**機能**:
- config.tomlから全設定ファイルを生成
- docker-compose.yaml, Dockerfile, Caddyfile等を出力
- built/ディレクトリに生成物を配置

**オプション**:
- `--force`: 既存ファイルを強制上書き
- `--validate`: 生成後に設定検証実行

**例**:
```bash
./cerberus.sh generate --force --validate
```

#### validate - 設定検証
```bash
./cerberus.sh validate [--strict]
```

**機能**:
- config.tomlの構文・論理チェック
- 必須項目の存在確認
- 値の範囲・形式検証

**オプション**:
- `--strict`: 厳格検証モード（警告もエラー扱い）

#### clean - クリーンアップ
```bash
./cerberus.sh clean [--all] [--confirm]
```

**機能**:
- built/ディレクトリの内容削除
- 生成ファイルの完全除去

**オプション**:
- `--all`: ログファイルも含めて削除
- `--confirm`: 確認なしで実行

### 2. サービス管理コマンド

#### up - サービス起動
```bash
./cerberus.sh up [service...] [--detach] [--build]
```

**機能**:
- Docker Composeサービスの起動
- 必要に応じて事前設定生成
- ヘルスチェック実行

**オプション**:
- `--detach, -d`: バックグラウンド実行
- `--build`: イメージを強制リビルド

**例**:
```bash
./cerberus.sh up --detach --build
./cerberus.sh up proxy anubis --detach
```

#### down - サービス停止
```bash
./cerberus.sh down [service...] [--volumes] [--remove-orphans]
```

**機能**:
- Docker Composeサービスの停止
- コンテナ・ネットワークの削除

**オプション**:
- `--volumes, -v`: ボリュームも削除
- `--remove-orphans`: 孤立コンテナも削除

#### restart - サービス再起動
```bash
./cerberus.sh restart [service...] [--timeout <seconds>]
```

**機能**:
- サービスの安全な再起動
- 設定変更の自動検出・適用

**オプション**:
- `--timeout <n>`: タイムアウト秒数（デフォルト: 30）

#### logs - ログ表示
```bash
./cerberus.sh logs [service...] [--follow] [--tail <lines>] [--since <time>]
```

**機能**:
- サービスログの表示
- リアルタイムログ追跡
- 時間・行数フィルタリング

**オプション**:
- `--follow, -f`: ログ追跡モード
- `--tail <n>`: 最新n行のみ表示
- `--since <time>`: 指定時刻以降のログ

#### ps - サービス状態
```bash
./cerberus.sh ps [--format <format>] [--all]
```

**機能**:
- 実行中サービスの一覧表示
- リソース使用状況の表示

**オプション**:
- `--format <fmt>`: 出力形式指定（table, json, yaml）
- `--all, -a`: 停止中サービスも表示

#### build - イメージビルド
```bash
./cerberus.sh build [service...] [--no-cache] [--parallel]
```

**機能**:
- Dockerイメージのビルド
- 並列ビルド対応

**オプション**:
- `--no-cache`: キャッシュを使用しない
- `--parallel`: 並列ビルド実行

### 3. スケーリング管理コマンド

#### scale - スケール操作
```bash
./cerberus.sh scale <service>=<count>
./cerberus.sh scale auto [--enable|--disable]
./cerberus.sh scale status
```

**機能**:
- サービスインスタンス数の手動変更
- 自動スケーリングの有効/無効切り替え
- 現在のスケール状況表示

**例**:
```bash
./cerberus.sh scale proxy=3 proxy-2=2
./cerberus.sh scale auto --enable
./cerberus.sh scale status
```

### 4. 初期設定・テンプレートコマンド

#### init - 初期設定
```bash
./cerberus.sh init [--template <name>] [--interactive]
```

**機能**:
- 設定ファイルの初期作成
- テンプレートベースの設定生成
- 対話式設定ウィザード

**オプション**:
- `--template <name>`: テンプレート指定
- `--interactive, -i`: 対話式モード

**例**:
```bash
./cerberus.sh init --template misskey --interactive
```

#### template - テンプレート管理
```bash
./cerberus.sh template list
./cerberus.sh template show <name>
./cerberus.sh template apply <name> [--force]
```

**機能**:
- 利用可能テンプレートの一覧表示
- テンプレート内容の表示
- 既存設定へのテンプレート適用

### 5. 監視・デバッグコマンド

#### status - システム状態
```bash
./cerberus.sh status [--detailed] [--json]
```

**機能**:
- システム全体の状態表示
- サービス、スケーリング、リソース状況

**オプション**:
- `--detailed`: 詳細情報表示
- `--json`: JSON形式で出力

#### health - ヘルスチェック
```bash
./cerberus.sh health [service...] [--timeout <seconds>]
```

**機能**:
- サービスのヘルスチェック実行
- 応答時間・可用性の確認

#### metrics - メトリクス表示
```bash
./cerberus.sh metrics [service...] [--interval <seconds>] [--format <fmt>]
```

**機能**:
- CPU、メモリ、ネットワーク使用量表示
- リアルタイム監視

**オプション**:
- `--interval <n>`: 更新間隔秒数
- `--format <fmt>`: 出力形式（text, json, prometheus）

#### docs - ドキュメント表示
```bash
./cerberus.sh docs [--serve] [--port <port>]
```

**機能**:
- HTMLドキュメントの生成・表示
- ローカルWebサーバーでの提供

**オプション**:
- `--serve`: HTTPサーバー起動
- `--port <n>`: サーバーポート指定

### 6. テスト・検証コマンド

#### test - テスト実行
```bash
./cerberus.sh test [--integration] [--coverage] [pattern...]
```

**機能**:
- 単体テスト・統合テストの実行
- 設定ファイルの検証テスト

**オプション**:
- `--integration`: 統合テストも実行
- `--coverage`: カバレッジ測定
- `pattern`: テストパターン指定

## エラーハンドリング

### 終了コード
- `0`: 正常終了
- `1`: 一般的なエラー
- `2`: 設定エラー
- `3`: Docker関連エラー
- `4`: ネットワークエラー
- `5`: 権限エラー
- `125`: コマンド実行エラー
- `126`: コマンド実行権限なし
- `127`: コマンドが見つからない

### エラーメッセージ形式
```
Error: <error_description>
File: <config_file>
Line: <line_number> (if applicable)
Suggestion: <fix_suggestion>

For more help: ./cerberus.sh help <command>
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