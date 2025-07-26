# Multi-Layer Proxy Architecture

高可用性とDDoS保護を提供する多層リバースプロキシシステム。Caddyベースの軽量で高性能なプロキシソリューションです。

## 🏗️ アーキテクチャ

```
Internet → proxy (Layer 1) → anubis (DDoS Protection) → proxy-2 (Layer 2) → Backend Services
```

### 構成要素

- **proxy** (Layer 1): 初期トラフィックフィルタリングと基本ルーティング
- **anubis** (DDoS Protection): チャレンジレスポンス型DDoS保護ミドルウェア
- **proxy-2** (Layer 2): 最終的なサービスルーティング

## 🚀 クイックスタート

### 前提条件

- Docker & Docker Compose
- Bash 4.0+
- （オプション）yq - YAML構文検証用
- （オプション）caddy - Caddyfile検証用

### セットアップ

1. **設定ファイルの作成**
   ```bash
   cp config-example.yaml config.yaml
   # config.yamlを環境に合わせて編集
   ```

2. **Caddyfile生成**
   ```bash
   # プレビュー
   ./generate-caddyfile.sh --dry-run
   
   # 実際に生成（バックアップ付き）
   ./generate-caddyfile.sh --backup --verbose
   ```

3. **サービス起動**
   ```bash
   docker-compose up -d --build
   ```

## 📋 generate-caddyfile.sh の使い方

### 基本的な使用方法

```bash
./generate-caddyfile.sh [OPTIONS] [CONFIG_FILE] [OUTPUT_DIR]
```

### オプション

| オプション | 短縮形 | 説明 |
|-----------|-------|------|
| `--dry-run` | `-d` | ファイルを書き込まずにプレビュー表示 |
| `--backup` | `-b` | 既存Caddyfileのバックアップを作成 |
| `--verbose` | `-v` | 詳細なログ出力を有効化 |
| `--help` | `-h` | ヘルプメッセージを表示 |
| `--no-color` | | カラー出力を無効化 |
| `--validate-only` | | 設定検証のみ実行 |

### 使用例

```bash
# デフォルト設定でプレビュー
./generate-caddyfile.sh --dry-run

# バックアップ付きで詳細ログ出力
./generate-caddyfile.sh --backup --verbose

# カスタム設定ファイルと出力ディレクトリ
./generate-caddyfile.sh my-config.yaml ./output/

# 設定検証のみ
./generate-caddyfile.sh --validate-only
```

## 🔧 設定ファイル

### config.yaml の構造

```yaml
# Global Caddy設定
global:
  auto_https: "off"
  admin: "off"

# ログ設定
logging:
  level: "INFO"
  format: "json"
  output: "/var/log/caddy/caddy.log"

# TLS設定
tls:
  enabled: false
  ca:
    enabled: false
    root_cert: "/etc/ssl/ca.crt"
    root_key: "/etc/ssl/ca.key"
```

詳細な設定例は `config-example.yaml` を参照してください。

## 🐳 Docker Compose

### 全サービス起動

```bash
# ビルドして起動
docker-compose up -d --build

# ログ確認
docker-compose logs -f [service-name]

# 停止
docker-compose down
```

### 個別サービス管理

```bash
# 特定サービスの再ビルド
docker-compose up -d --build proxy-2

# サービス再起動
docker-compose restart anubis

# サービススケール（必要に応じて）
docker-compose up -d --scale proxy=2
```

## 📊 ログとモニタリング

### ログファイル場所

- `logs/access.log` - 一般アクセスログ
- `logs/error.log` - エラーログ
- `logs/[service]_access.log` - サービス別アクセスログ

### ヘルスチェック

```bash
# サービス状態確認
docker-compose ps

# リソース使用量確認
docker stats

# エラーログ確認
docker-compose logs --tail=100 | grep -i error
```

## 🔒 セキュリティ機能

### DDoS保護（anubis）

- チャレンジレスポンス型保護
- 設定可能なボットポリシー
- 特定パスのバイパス機能

### アクセス制御

- 多層防御アーキテクチャ
- 内部ネットワーク分離
- 指定ポートのみ外部公開

## 🛠️ 開発とテスト

### ローカル開発

1. 設定ファイルのバックエンドIPをlocalhostに変更
2. docker-compose override fileを使用
3. デバッグログを有効化

### 設定変更のテスト

```bash
# Caddyfile構文チェック
docker-compose exec proxy caddy validate --config /etc/caddy/Caddyfile
docker-compose exec proxy-2 caddy validate --config /etc/caddy/Caddyfile

# 設定変更後のリロード
docker-compose exec proxy caddy reload --config /etc/caddy/Caddyfile
docker-compose exec proxy-2 caddy reload --config /etc/caddy/Caddyfile
```

## 🐛 トラブルシューティング

### よくある問題

1. **サービスが起動しない**
   ```bash
   docker-compose logs [service-name]
   ```

2. **502 Bad Gateway**
   - バックエンドサービスの可用性確認
   - ネットワーク接続確認

3. **SSL/TLS問題**
   - 証明書のマウント確認
   - 設定ファイルの証明書パス確認

### デバッグコマンド

```bash
# ネットワーク接続テスト
docker-compose exec proxy nc -zv anubis 8080
docker-compose exec anubis nc -zv proxy-2 80

# リアルタイムログ監視
docker-compose logs -f --tail=0

# Caddyfile構文確認
caddy validate --config ./proxy/Caddyfile
```

## 🔄 アップデート

### サービス更新

```bash
# anubisイメージ更新
docker-compose pull anubis
docker-compose up -d anubis

# カスタムイメージ再ビルド
docker-compose build --no-cache
docker-compose up -d
```

### 設定更新

1. 設定ファイル修正
2. Caddyfile再生成
3. 設定リロードまたはサービス再起動

## 📁 ディレクトリ構造

```
.
├── README.md                   # このファイル
├── docker-compose.yaml        # メイン構成ファイル
├── config.yaml                 # 設定ファイル
├── config-example.yaml         # 設定例
├── generate-caddyfile.sh       # Caddyfile生成スクリプト
├── botPolicy.json             # DDoS保護ポリシー
├── proxy/
│   ├── Dockerfile
│   └── Caddyfile              # 生成されるLayer 1設定
├── proxy-2/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── Caddyfile              # 生成されるLayer 2設定
├── logs/                      # ログファイル
└── ssl/                       # SSL証明書
```

## 🤝 コントリビューション

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/AmazingFeature`)
3. 変更をコミット (`git commit -m 'Add some AmazingFeature'`)
4. ブランチにプッシュ (`git push origin feature/AmazingFeature`)
5. プルリクエストを作成

## 📄 ライセンス

このプロジェクトは[MIT License](LICENSE)の下で公開されています。

## ⚡ パフォーマンス

- **Caddy**: 高性能Go製リバースプロキシ
- **Docker**: コンテナベースの軽量デプロイメント
- **多層アーキテクチャ**: 負荷分散とフォルトトレラント

## 🔍 モニタリング

推奨監視項目：
- CPU/メモリ使用率
- レスポンス時間
- エラー率
- DDoS攻撃検知数
- SSL証明書有効期限

---

質問や問題がありましたら、Issueを作成するかプロジェクト管理者にお問い合わせください。