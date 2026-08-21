# Repository Management Role

このroleはクライアントサーバーでのリポジトリ設定を管理します。管理対象リポジトリの設定と、管理対象外リポジトリの無効化を行います。

## 機能
- 辞書ベースの柔軟なリポジトリ設定
- 管理対象外リポジトリの自動無効化
- 特定リポジトリファイルの保護機能
- DNFメタデータのクリーンアップ
- Red Hat Subscription Managerのリポジトリ管理制御

## 変数

### リポジトリサーバー設定
- `repo_server_ip`: リポジトリサーバーのIPアドレス
- `repo_base`: リポジトリのベースURL（デフォルト: `http://{{ repo_server_ip }}/repo`）

### リポジトリ管理制御
- `disable_unmanaged_repos`: 管理対象外リポジトリを無効化するか（デフォルト: true）
- `repos_to_preserve`: 無効化から除外するリポジトリファイル名のリスト（例: ['redhat.repo']）

### リポジトリ設定
- `repositories`: リポジトリ設定の辞書リスト（以下のパラメータを含む）
  - `name`: リポジトリ名（必須）
  - `file`: リポジトリファイル名（必須）
  - `description`: リポジトリの説明（必須）
  - `baseurl`: リポジトリのベースURL（必須）
  - `enabled`: 有効/無効（デフォルト: true）
  - `gpgcheck`: GPGチェック（デフォルト: true）
  - `gpgkey`: GPGキーのパス（オプション）
  - `metadata_expire`: メタデータ有効期限（デフォルト: -1）
  - `state`: リポジトリの状態（デフォルト: present）
  - `priority`: リポジトリ優先度（オプション）
  - `includepkgs`: 含めるパッケージ（オプション）
  - `excludepkgs`: 除外するパッケージ（オプション）
  - `skip_if_unavailable`: 利用不可時のスキップ（オプション）
  - `sslverify`: SSL検証（オプション）
  - `proxy`: プロキシ設定（オプション）

### その他の設定
- `rhsm_manage_repos`: リポジトリ管理の設定（0=無効, 1=有効）
- `dnf_clean_options`: DNFクリーンオプション（デフォルト: all）

## 使用例

### 基本的な使用方法
```yaml
- hosts: automation_mesh
  roles:
    - repository_management
  vars:
    repo_server_ip: "192.168.121.50"
```

### Red Hat公式リポジトリを保護して使用
```yaml
- hosts: automation_mesh
  roles:
    - repository_management
  vars:
    repo_server_ip: "192.168.121.50"
    repos_to_preserve: 
      - "redhat.repo"
      - "rhel-9-for-x86_64-baseos-rpms.repo"
```

### 管理対象外リポジトリを無効化せずに使用
```yaml
- hosts: automation_mesh
  roles:
    - repository_management
  vars:
    repo_server_ip: "192.168.121.50"
    disable_unmanaged_repos: false
```

### カスタムリポジトリの追加
```yaml
- hosts: automation_mesh
  roles:
    - repository_management
  vars:
    repo_server_ip: "192.168.121.50"
    repositories:
      - name: "BaseOS"
        file: "baseos-http"
        description: "RHEL BaseOS via local nginx"
        baseurl: "{{ repo_base }}/BaseOS"
        enabled: true
        gpgcheck: true
        gpgkey: "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release"
        
      - name: "AppStream"
        file: "appstream-http"
        description: "RHEL AppStream via local nginx"
        baseurl: "{{ repo_base }}/AppStream"
        enabled: true
        gpgcheck: true
        gpgkey: "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release"
        
      - name: "CustomRepo"
        file: "custom-repo"
        description: "Custom package repository"
        baseurl: "{{ repo_base }}/Custom"
        enabled: true
        gpgcheck: false
        priority: 10
        skip_if_unavailable: true

## 処理フロー
1. EPELリポジトリファイルの削除
2. 辞書リストに基づくリポジトリ設定（ループ処理）
3. DNFメタデータのクリーンアップ
4. Subscription Managerのリポジトリ管理制御

## 前提条件
- リポジトリサーバー側でHTTP配信が設定済みであること
- 対象サーバーからリポジトリサーバーにHTTPアクセス可能であること
- 必要に応じてGPGキーが適切に配置されていること

## 利点
- **柔軟性**: 任意の数のリポジトリを設定可能
- **再利用性**: 同じタスクで異なるリポジトリタイプに対応
- **保守性**: リポジトリ追加時はdefaultsの変更のみ
- **拡張性**: yum_repositoryモジュールの全パラメータに対応
