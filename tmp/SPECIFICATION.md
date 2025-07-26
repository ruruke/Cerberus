# Cerberus Multi-Layer Proxy Architecture - 仕様書

## 概要

Cerberusは、設定ファイル（TOML）からDocker構成を動的生成する多層プロキシアーキテクチャシステムです。DDoS保護、負荷分散、自動スケーリング機能を提供します。

## アーキテクチャ

```
Internet → HAProxy/Proxy → Anubis (DDoS) → Proxy-2 → Backend Services
```

## ファイル構成

```
cerberus/
├── cerberus.sh                   # メインCLI
├── config.toml                   # 実設定（.gitignore対象）
├── config-example.toml           # サンプル設定
├── SPECIFICATION.md              # 本仕様書
├── lib/
│   ├── core/                     # コア機能
│   │   ├── config.sh            # TOML解析・設定管理
│   │   ├── validation.sh        # 設定検証
│   │   └── utils.sh             # 共通関数
│   ├── generators/               # 生成エンジン
│   │   ├── docker-compose.sh    # Docker Compose生成
│   │   ├── dockerfiles.sh       # Dockerfile生成
│   │   ├── caddyfiles.sh        # Caddyfile生成
│   │   ├── haproxy.sh           # HAProxy設定生成
│   │   └── anubis.sh            # Anubis/botPolicy生成
│   ├── scaling/                  # スケーリング機能
│   │   ├── monitor.sh           # 負荷監視
│   │   ├── scaler.sh            # 自動スケール
│   │   └── metrics.sh           # メトリクス収集
│   ├── templates/                # テンプレート管理
│   │   ├── manager.sh           # テンプレート操作
│   │   └── wizard.sh            # 対話式設定
│   └── testing/                  # テスト・検証
│       ├── runner.sh            # テスト実行
│       ├── fixtures.sh          # テストデータ
│       └── integration.sh       # 結合テスト
├── templates/                    # 設定テンプレート
│   ├── configs/                  # 構成テンプレート
│   │   ├── simple.toml          # シンプル構成
│   │   ├── misskey.toml         # Misskey特化
│   │   └── multi-layer.toml     # 複数層構成
│   └── botpolicy/                # Anubis設定テンプレート
│       ├── strict.json          # 厳格設定
│       ├── moderate.json        # 標準設定
│       └── permissive.json      # 緩い設定
├── tests/                        # テストスイート
│   ├── fixtures/                 # テストデータ
│   └── integration/              # 結合テスト
└── built/                        # 生成物（.gitignore対象）
    ├── docker-compose.yaml       # メイン構成
    ├── proxy/                    # プロキシ設定
    ├── haproxy/                  # HAProxy設定
    ├── anubis/                   # Anubis設定
    ├── scaler/                   # スケーラー
    └── docs/                     # HTMLドキュメント
```

## config.toml 仕様

### 基本構成

```toml
[project]
name = "cerberus"
version = "1.0.0"
scaling = true                    # スケーリング機能有効化

# プロキシ層定義（複数対応）
[[proxies]]
name = "haproxy-lb"              # HAProxy ロードバランサー
type = "haproxy"                 # haproxy, caddy, nginx, traefik
external_port = 8080
internal_port = 80
algorithm = "roundrobin"          # leastconn, source, uri
health_check = "/health"
instances = 1                     # インスタンス数
min_instances = 1                 # 最小インスタンス数
max_instances = 5                 # 最大インスタンス数

[[proxies]]
name = "proxy"
type = "caddy"
internal_port = 80
upstream = "anubis:8080"          # 次の層
instances = 2
min_instances = 1
max_instances = 10
scale_metric = "cpu"              # cpu, memory, connections
scale_threshold = 70              # スケール閾値（%）

# 直接ルーティング（Anubis回避）
direct_routes = [
    "media.ruruke.moe",
    "storage.ruruke.moe"
]

# DDoS保護設定
[anubis]
enabled = true
image = "ghcr.io/techarohq/anubis:latest"
bind = ":8080"
difficulty = 5                    # 1-10の難易度
metrics_bind = ":9090"
serve_robots_txt = true
target = "proxy-2:80"            # 転送先
policy_template = "moderate"      # strict/moderate/permissive
custom_policy = ""               # カスタムポリシーパス

# カスタムルール
[[anubis.allow_paths]]
path = "/api/*"
reason = "API access"

[[anubis.challenge_user_agents]]
pattern = "Mozilla/*"
difficulty = 3

# バックエンドサービス
[[services]]
name = "misskey"
domain = "mi.ruruke.moe"
upstream = "http://100.103.133.21:3000"
max_body_size = "100MB"
websocket = true
access_log = "/var/log/caddy/misskey_access.log"

[[services]]
name = "media"
domain = "media.ruruke.moe"
upstream = "http://100.97.11.65:12766"
access_log = "/var/log/caddy/media_access.log"

[[services]]
name = "storage"
domain = "storage.ruruke.moe"
upstream = "https://s3.ap-northeast-2-ntt.wasabisys.com/storage.ruruke.moe/"
max_body_size = "1000MB"
compress = true
access_log = "/var/log/caddy/storage_access.log"

[services.headers.request]
Host = "s3.us-east-2.wasabisys.com"
X-Forwarded-Proto = "https"

[services.headers.response]
Cache-Control = "public, max-age=2592000"
Pragma = "public"

# スケーリング設定
[scaling]
enabled = true
check_interval = "30s"            # 負荷チェック間隔
scale_up_cooldown = "5m"          # スケールアップ後待機時間
scale_down_cooldown = "10m"       # スケールダウン後待機時間

[scaling.metrics]
cpu_threshold = 70                # CPU使用率閾値（%）
memory_threshold = 80             # メモリ使用率閾値（%）
connections_threshold = 1000      # 接続数閾値

# ログ設定
[logging]
level = "INFO"                    # DEBUG, INFO, WARN, ERROR
format = "json"                   # json, console
output = "/var/log/caddy/caddy.log"

# TLS設定（オプション）
[tls]
enabled = false
auto_https = false

[tls.ca]
enabled = false
root_cert = "/etc/ssl/ca.crt"
root_key = "/etc/ssl/ca.key"

[[tls.certificates]]
domain = "*.ruruke.moe"
cert_file = "/etc/ssl/wildcard.crt"
key_file = "/etc/ssl/wildcard.key"
```

## CLI コマンド仕様

### 基本コマンド

```bash
# 生成系
./cerberus.sh generate              # 全設定生成
./cerberus.sh generate --force      # 強制再生成
./cerberus.sh clean                 # built/クリア

# Docker制御系
./cerberus.sh up [service]          # サービス起動
./cerberus.sh down [service]        # サービス停止
./cerberus.sh restart [service]     # サービス再起動
./cerberus.sh logs [service]        # ログ表示
./cerberus.sh logs -f [service]     # ログ追跡
./cerberus.sh ps                    # サービス状態表示
./cerberus.sh build [service]       # イメージビルド

# スケーリング系
./cerberus.sh scale [service] [num] # スケール変更
./cerberus.sh scale up [service]    # スケールアップ
./cerberus.sh scale down [service]  # スケールダウン
./cerberus.sh scale auto            # 自動スケーリング開始
./cerberus.sh scale stop            # 自動スケーリング停止
./cerberus.sh scale status          # スケール状況表示

# テンプレート系
./cerberus.sh init                  # 対話式初期設定
./cerberus.sh init --template [name] # テンプレートから初期化
./cerberus.sh template list         # テンプレート一覧
./cerberus.sh template show [name]  # テンプレート表示

# Anubis設定系
./cerberus.sh anubis config         # Anubis対話式設定
./cerberus.sh anubis policy [type]  # botPolicy生成
./cerberus.sh anubis test           # Anubis設定テスト

# 監視・管理系
./cerberus.sh status                # 全体状況表示
./cerberus.sh health                # ヘルスチェック実行
./cerberus.sh metrics               # メトリクス表示
./cerberus.sh docs                  # HTMLドキュメント表示

# テスト系
./cerberus.sh test                  # テスト実行
./cerberus.sh test --integration    # 結合テスト実行
./cerberus.sh validate              # 設定検証
```

## 生成物仕様

### built/docker-compose.yaml

- サービス定義
- ネットワーク設定
- ボリューム設定
- 環境変数
- ヘルスチェック
- スケーリング設定

### built/proxy/

- Dockerfile（Caddyベース）
- Caddyfile（ルーティング設定）

### built/haproxy/

- Dockerfile（HAProxyベース）
- haproxy.cfg（負荷分散設定）

### built/anubis/

- botPolicy.json（DDoS保護ルール）

### built/scaler/

- Dockerfile（監視・スケーラー）
- monitor.sh（負荷監視スクリプト）

## 動作フロー

1. **設定**: config.tomlを編集または対話式設定
2. **生成**: `./cerberus.sh generate`で全設定生成
3. **起動**: `./cerberus.sh up`でサービス開始
4. **監視**: 自動的に負荷監視・スケーリング実行
5. **管理**: CLI経由でサービス制御・状態確認

## 対応プロキシ

- **Caddy**: HTTP/HTTPS、自動SSL、リバースプロキシ
- **HAProxy**: 高性能負荷分散、ヘルスチェック
- **Nginx**: 静的ファイル配信、リバースプロキシ（予定）
- **Traefik**: 動的設定、サービス発見（予定）

## 対応DDoS保護

- **Anubis**: AI Firewall、チャレンジ・レスポンス
- **Cloudflare**: CDN連携（予定）
- **Fail2ban**: IP制限（予定）

## スケーリング戦略

- **CPU使用率**: しきい値超過時にスケール
- **メモリ使用率**: メモリ不足時にスケール
- **接続数**: 接続数過多時にスケール
- **カスタムメトリクス**: 独自指標によるスケール

## セキュリティ

- **設定ファイル暗号化**: 機密情報の保護
- **SSL/TLS**: 自動証明書取得
- **アクセス制御**: IP制限、認証
- **ログ監査**: セキュリティイベント記録

## 拡張性

- **プラグインシステム**: 独自機能追加
- **カスタムジェネレーター**: 独自設定生成
- **外部連携**: API経由での制御
- **クラウド対応**: AWS、GCP、Azure連携

## パフォーマンス

- **並列生成**: 設定生成の高速化
- **キャッシュ**: 頻繁な操作のキャッシュ化
- **最適化**: 不要な処理の削減
- **監視**: パフォーマンス指標の収集

## 互換性

- **Docker**: 20.10以降
- **Docker Compose**: 2.0以降
- **Shell**: Bash 4.0以降
- **OS**: Linux、macOS、WSL2

## ライセンス

CC0 1.0 Universal - パブリックドメイン

## バージョン履歴

- **v1.0.0**: 初回リリース
  - 基本的な多層プロキシ機能
  - Docker Compose生成
  - Caddy、HAProxy対応
  - Anubis DDoS保護
  - 基本的なスケーリング