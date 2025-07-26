# Config Library Specification (lib/core/config.sh)

## 概要

`lib/core/config.sh`はTOML形式の設定ファイル（config.toml）を解析し、Cerberusシステム全体で利用可能な設定情報を提供するライブラリです。

## 設計原則

1. **正確性**: TOML仕様に準拠した解析
2. **エラー検出**: 設定エラーの詳細な報告
3. **パフォーマンス**: キャッシュ機能による高速アクセス
4. **拡張性**: 新しい設定項目の追加が容易

## 対応TOML仕様

### サポート機能
- **基本データ型**: String, Integer, Float, Boolean, Datetime
- **配列**: 基本型の配列、テーブル配列
- **テーブル**: 標準テーブル、インラインテーブル
- **配列テーブル**: `[[section]]` 形式
- **ネスト**: 深いネスト構造対応
- **コメント**: `#` による行コメント

### 制限事項
- **複雑なデータ型**: 複合型の一部制限
- **Unicode**: 基本的なUTF-8サポート
- **大容量ファイル**: メモリ効率を考慮した上限設定

## 機能仕様

### 1. 基本解析機能

#### 設定ファイル読み込み
```bash
config_load [config_file]        # 設定ファイル読み込み
config_reload                    # 設定再読み込み
config_is_loaded                 # 読み込み状態確認
```

#### 基本値取得
```bash
config_get <key> [default]       # 設定値取得
config_get_string <key> [default]    # 文字列取得
config_get_int <key> [default]       # 整数取得
config_get_bool <key> [default]      # 真偽値取得
config_get_array <key>               # 配列取得
```

**仕様**:
- デフォルト値サポート
- 型チェック機能
- エラー時の適切な値返却
- キャッシュによる高速アクセス

### 2. 複合データ処理

#### テーブル操作
```bash
config_get_table <key>           # テーブル取得
config_get_table_keys <key>      # テーブルキー一覧
config_has_table <key>           # テーブル存在確認
```

#### 配列テーブル操作
```bash
config_get_array_table <key>     # 配列テーブル取得
config_get_array_table_count <key>   # 配列テーブル要素数
config_get_array_table_item <key> <index>  # 指定要素取得
```

**仕様**:
- ネストしたテーブル対応
- インデックスベースアクセス
- 存在チェック機能
- 型安全なアクセス

### 3. 設定検証

#### 必須項目チェック
```bash
config_require <key> [message]   # 必須設定確認
config_validate_schema [schema]  # スキーマ検証
config_check_dependencies        # 依存関係確認
```

#### 値検証
```bash
config_validate_range <key> <min> <max>     # 数値範囲確認
config_validate_enum <key> <values...>      # 列挙値確認
config_validate_regex <key> <pattern>       # 正規表現確認
config_validate_file <key>                  # ファイル存在確認
config_validate_directory <key>             # ディレクトリ確認
```

**仕様**:
- 包括的な検証機能
- カスタム検証ルール
- わかりやすいエラーメッセージ
- 検証結果のレポート

### 4. キーパス処理

#### パス操作
```bash
config_normalize_key <key>       # キー正規化
config_split_key <key>           # キー分割
config_join_key <parts...>       # キー結合
config_key_exists <key>          # キー存在確認
```

#### パス検索
```bash
config_find_keys <pattern>       # パターン検索
config_list_keys [prefix]        # キー一覧取得
config_get_key_type <key>        # キータイプ取得
```

**仕様**:
- ドット記法サポート（`proxy.port`）
- 配列インデックス（`services[0].name`）
- ワイルドカード検索
- 型情報の提供

### 5. 設定操作（実行時）

#### 動的設定変更
```bash
config_set <key> <value>         # 設定値変更
config_unset <key>               # 設定削除
config_merge <table>             # テーブル結合
```

#### 設定保存
```bash
config_save [file]               # 設定保存
config_backup [file]             # 設定バックアップ
config_restore [file]            # 設定復元
```

**仕様**:
- メモリ内での設定変更
- 原子的な保存操作
- 自動バックアップ機能
- 変更履歴の管理

## 設定スキーマ定義

### Cerberus設定構造
```toml
# プロジェクト基本情報
[project]
name = "string"                  # プロジェクト名
version = "string"               # バージョン
scaling = boolean                # スケーリング有効/無効

# プロキシ層定義
[[proxies]]
name = "string"                  # プロキシ名（必須）
type = "string"                  # プロキシタイプ（必須）
external_port = integer          # 外部ポート
internal_port = integer          # 内部ポート
instances = integer              # インスタンス数
min_instances = integer          # 最小インスタンス数
max_instances = integer          # 最大インスタンス数
upstream = "string"              # 上流サーバー
direct_routes = ["string"]       # 直接ルーティング

# DDoS保護設定
[anubis]
enabled = boolean                # 有効/無効
bind = "string"                  # バインドアドレス
difficulty = integer             # 難易度（1-10）
target = "string"                # 転送先

# サービス定義
[[services]]
name = "string"                  # サービス名（必須）
domain = "string"                # ドメイン（必須）
upstream = "string"              # アップストリーム（必須）
max_body_size = "string"         # 最大ボディサイズ
websocket = boolean              # WebSocket対応
compress = boolean               # 圧縮有効

# スケーリング設定
[scaling]
enabled = boolean                # 有効/無効
check_interval = "string"        # チェック間隔
scale_up_cooldown = "string"     # スケールアップ待機時間
scale_down_cooldown = "string"   # スケールダウン待機時間

[scaling.metrics]
cpu_threshold = integer          # CPU閾値（%）
memory_threshold = integer       # メモリ閾値（%）
connections_threshold = integer  # 接続数閾値
```

### スキーマ検証ルール
```bash
# 必須項目
REQUIRED_KEYS=(
    "project.name"
    "proxies[].name"
    "proxies[].type"
    "services[].name"
    "services[].domain"
    "services[].upstream"
)

# 数値範囲
NUMERIC_RANGES=(
    "anubis.difficulty:1:10"
    "scaling.metrics.cpu_threshold:1:100"
    "scaling.metrics.memory_threshold:1:100"
)

# 列挙値
ENUM_VALUES=(
    "proxies[].type:caddy,haproxy,nginx,traefik"
)
```

## エラーハンドリング

### エラー分類
1. **構文エラー**: TOML形式の誤り
2. **スキーマエラー**: 必須項目不足、型不一致
3. **論理エラー**: 設定の矛盾、依存関係違反
4. **システムエラー**: ファイル読み込み失敗など

### エラーレポート形式
```
Error: Configuration validation failed
File: /path/to/config.toml
Line: 15
Key: proxies[0].port
Issue: Value must be between 1 and 65535, got: 100000
Suggestion: Use a valid port number (e.g., 8080)
```

## パフォーマンス最適化

### キャッシュ戦略
- **解析結果キャッシュ**: 初回解析結果の保存
- **頻繁アクセスキャッシュ**: よく使われる値の高速化
- **部分更新**: 変更部分のみ再解析
- **遅延読み込み**: 必要時のみ詳細解析

### メモリ管理
- **軽量構造**: 最小限のメモリ使用
- **循環参照回避**: メモリリーク防止
- **ガベージコレクション**: 不要データの自動削除

## 使用例

### 基本的な使用方法
```bash
#!/bin/bash
source "$(dirname "$0")/lib/core/utils.sh"
source "$(dirname "$0")/lib/core/config.sh"

# 設定読み込み
config_load "config.toml"

# 基本値取得
project_name=$(config_get_string "project.name" "cerberus")
scaling_enabled=$(config_get_bool "scaling.enabled" false)

# 配列テーブル処理
proxy_count=$(config_get_array_table_count "proxies")
for ((i=0; i<proxy_count; i++)); do
    proxy_name=$(config_get "proxies[$i].name")
    proxy_type=$(config_get "proxies[$i].type")
    echo "Proxy: $proxy_name ($proxy_type)"
done

# 設定検証
config_require "services[0].domain" "At least one service must be defined"
config_validate_range "anubis.difficulty" 1 10
```

### 高度な使用例
```bash
# 動的設定変更
config_set "proxies[0].instances" 5
config_set "scaling.enabled" true

# 条件付き設定
if config_get_bool "anubis.enabled"; then
    difficulty=$(config_get_int "anubis.difficulty" 5)
    generate_anubis_config "$difficulty"
fi

# 設定テンプレート適用
config_load_template "misskey" "config.toml"
config_override "project.name" "my-misskey"
```

## テスト戦略

### 単体テスト
- TOML解析の正確性テスト
- エラーハンドリングテスト
- 型変換テスト
- キャッシュ機能テスト

### 統合テスト
- 実際の設定ファイルでのテスト
- 他ライブラリとの連携テスト
- パフォーマンステスト

### テストデータ
```bash
# tests/fixtures/config/
├── valid/
│   ├── minimal.toml          # 最小設定
│   ├── complete.toml         # 完全設定
│   └── complex.toml          # 複雑設定
├── invalid/
│   ├── syntax-error.toml     # 構文エラー
│   ├── missing-required.toml # 必須項目不足
│   └── invalid-values.toml   # 不正値
```

## 拡張計画

### Phase 1 (現在)
- 基本TOML解析機能
- スキーマ検証
- キャッシュ機能

### Phase 2
- 環境変数展開
- 設定テンプレート機能
- 動的設定変更API

### Phase 3
- 設定の暗号化サポート
- リモート設定取得
- 設定変更の監視機能

この仕様に基づいて、堅牢で高性能な設定管理システムを提供します。