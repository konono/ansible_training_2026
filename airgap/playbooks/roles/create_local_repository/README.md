# Create Local Repository Role

このroleはRHELローカルリポジトリをHTTP経由で配信するためのNginx設定を行います。

## 機能
- NginxのインストールとHTTPサーバー設定
- ISO マウントポイントのHTTP配信設定
- ファイアウォール設定（HTTP ポート開放）
- use_loop_isoがtrueの場合のみ実行

## 前提条件
- `use_loop_iso`変数がtrueに設定されている必要があります
- ISOファイルが既にマウントされている必要があります
- 通常は`setup_rhel_image_repository` roleの後に実行します

## 変数

### ISO設定
- `iso_mount_point`: ISOマウントポイント（デフォルト: /mnt/cdrom）

### Nginx設定
- `nginx_package_name`: Nginxパッケージ名（デフォルト: nginx）
- `nginx_service_name`: Nginxサービス名（デフォルト: nginx）
- `nginx_service_state`: Nginxサービス状態（デフォルト: started）
- `nginx_service_enabled`: Nginxサービス自動起動（デフォルト: true）
- `nginx_repo_config_path`: Nginx設定ファイルパス
- `nginx_listen_port`: リスニングポート（デフォルト: 80）
- `nginx_server_name`: サーバー名（デフォルト: _）
- `nginx_repo_location`: リポジトリのURLパス（デフォルト: /repo/）
- `nginx_autoindex`: ディレクトリ一覧表示（デフォルト: on）

### ファイアウォール設定
- `firewall_cmd_path`: firewall-cmdのパス
- `firewall_service_name`: 開放するサービス名（デフォルト: http）

## 使用例
```yaml
- hosts: localhost
  roles:
    - setup_rhel_image_repository
    - create_local_repository
  vars:
    rhel_installer_iso: "rhel-8.8-x86_64-dvd.iso"
    use_loop_iso: true
```

## 動作条件
- `use_loop_iso`がfalseまたは未定義の場合、全タスクがスキップされます
- 物理CD-ROMを使用する場合（use_existing_cdrom）には実行されません

## HTTP アクセス
役割実行後、以下のURLでリポジトリにアクセス可能です：
- `http://<server_ip>/repo/BaseOS/`
- `http://<server_ip>/repo/AppStream/`

## セキュリティ考慮事項
- HTTPポート（80）がファイアウォールで開放されます
- 自動インデックス機能が有効になります
- 内部ネットワークでの使用を前提としています
