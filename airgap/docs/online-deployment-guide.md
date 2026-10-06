# 非airgap 構築ガイド（インターネット接続あり）

閉域（airgap）ではなく、インターネット接続のある環境に研修環境を構築する手順です。
DVD ISO もオフラインバンドル（`offline-resources/`）も不要です。

airgap 環境に構築する場合は [構築ガイド](deployment-guide.md) を参照してください。

## airgap 構成との違い

| 項目 | airgap | 非airgap |
|---|---|---|
| ローカルリポジトリサーバー | 必要（repo-server VM + nginx + DVD ISO） | **不要** |
| dnf リポジトリ | ISO をマウントした nginx 配信 | RHSM / Red Hat CDN をそのまま使用 |
| ansible-core | バンドルの wheel を `pip --no-index` | PyPI から取得 |
| Ansible コレクション | バンドルの tar.gz | Ansible Galaxy から取得 |
| sshpass | ソースからビルド | `dnf install sshpass` |
| コンテナイメージ | `podman load` (バンドルの tar) | `containers/` から `podman build` |
| docker-compose | バンドルのバイナリ | GitHub Releases からダウンロード |
| コンテナ内 dnf | ローカル nginx を指す repo を注入 | UBI 既定の CDN をそのまま使用 |
| インベントリ | `inventory/hosts.yml` | `inventory/hosts-online.yml` |

## 前提条件

- 演習サーバー（RHEL 9）がインターネットに到達できること
- 演習サーバーで RHSM のサブスクリプションが有効で、BaseOS / AppStream が使えること
  （`dnf repolist --enabled` に何か表示されること）
- コントローラ（Ansible 実行マシン）もインターネットに到達できること

> UBI ベースイメージ（`registry.access.redhat.com/ubi10/ubi-init`）の pull に
> サブスクリプションは不要です。

## 手順

### 1. コントローラのセットアップ

```bash
cd airgap/
./setup-controller.sh --online
```

`ansible-core`・`sshpass`・Ansible コレクション（`requirements.yml`）を
インターネットから取得してインストールします。

### 2. インベントリの編集

```bash
vi inventory/hosts-online.yml
```

`rhel-target` の `ansible_host` を演習サーバーの IP に変更してください。
`repo_server` グループはありません（不要です）。

`airgap_mode: false` がこのファイルに入っていることがモード切り替えの実体です。

### 3. リソース配布

```bash
SSH_ARGS='-e ansible_ssh_common_args="-o StrictHostKeyChecking=no"'
ansible-playbook -i inventory/hosts-online.yml playbooks/distribute-resources.yml $SSH_ARGS
```

非airgap では以下だけを配ります（ISO・イメージ tar・pip wheel は配りません）。

- 研修資材アーカイブ — 手元のリポジトリからコントローラ上で tar.gz を生成して転送
- `containers/` の Containerfile — 演習サーバー上で `podman build` するため

### 4. 演習サーバーのセットアップ

```bash
ansible-playbook -i inventory/hosts-online.yml playbooks/rhel-setup.yml $SSH_ARGS
```

`repo-server-setup.yml` は実行不要です。

この時点で演習サーバーに `/opt/airgap/deploy-mode.conf` が生成されます。
受講者が実行する `deploy-training.sh` はこのファイルを読んでモードを引き継ぐため、
受講者側で追加の指定は不要です。

### 5. 受講者の環境作成

airgap と同じです。

```bash
ssh <受講者ユーザー>@<演習サーバー IP>
cd /opt/airgap
./deploy-training.sh
```

## 設定変数

`inventory/hosts-online.yml` の `all.vars` で指定します。

| 変数 | 既定値 | 説明 |
|---|---|---|
| `airgap_mode` | `true` | `false` で非airgap モード。この切り替えが全分岐の起点 |
| `container_image_mode` | `build` | `build` = Containerfile からビルド / `pull` = レジストリから取得 |
| `container_image_registry` | `""` | `pull` の場合に指定（例 `registry.example.com/training`） |
| `training_source_mode` | `archive` | `archive` = tar.gz を転送して展開 / `git` = 演習サーバーで clone |
| `training_git_repo` | `""` | `git` の場合のリポジトリ URL |
| `training_git_version` | `main` | `git` の場合の branch / tag |
| `docker_compose_version` | `v2.29.7` | ダウンロードする docker-compose のバージョン |

> **注意**: これらを `group_vars/all.yml` に書かないでください。
> 各 playbook は `vars_files` で `group_vars/all.yml` を読み込んでおり、
> `vars_files` はインベントリ変数より優先順位が高いため、
> `inventory/hosts-online.yml` の設定を上書きしてしまいます。

### レジストリから pull する場合

```yaml
all:
  vars:
    airgap_mode: false
    container_image_mode: pull
    container_image_registry: registry.example.com/training
```

`registry.example.com/training/training-controller:latest` と
`.../training-linux-node:latest` を事前に push しておいてください。
pull 後にローカルタグ（`training-controller:latest` 等）が付与されます。

### git clone で研修資材を取得する場合

```yaml
all:
  vars:
    airgap_mode: false
    training_source_mode: git
    training_git_repo: https://github.com/konono/ansible_training_2026.git
    training_git_version: main
```

演習サーバーから git リポジトリに到達できる必要があります。

## KVM での検証

`Makefile` に非airgap 検証用のターゲットがあります。NAT ネットワーク
（`training-nat`, 192.168.130.0/24）上に VM を作って一連の流れを確認できます。

```bash
make setup-online-vm       # NAT ネットワーク + online-rhel-target VM を作成
make verify-online         # インターネット到達性を確認
make deploy-online-rhel    # 非airgap でデプロイ
make online-full-test      # 上記を一括実行して verify.yml まで回す
make destroy-online-vm     # 後片付け
```

`deploy-online-rhel` は `/tmp/online-test-inventory.yml` を使います。
`inventory/hosts-online.yml` をコピーして IP を合わせてください。

```bash
cp inventory/hosts-online.yml /tmp/online-test-inventory.yml
```

`make verify-airgap` は `AIRGAP_MODE=false` を付けるとスキップされます
（非airgap では「インターネットに到達できる」のが正常なため）。

## 資材の更新

```bash
AIRGAP_MODE=false ./update-airgap.sh
```

`offline-resources/` の不在を警告しなくなり、コード同期で
`inventory/hosts-online.yml` を使うようになります。

## トラブルシューティング

### `repo_server_ip が未設定です` で失敗する

`airgap_mode` が `true` のままです。`inventory/hosts-online.yml` を使っているか、
`-e airgap_mode=false` を付けているか確認してください。

### コンテナ内の `dnf install` が失敗する

UBI 既定の `ubi.repo` は Red Hat CDN を参照します。
演習サーバーからコンテナ経由で CDN に到達できるか確認してください。

### `podman build` が失敗する

`distribute-resources.yml` が先に実行されていない可能性があります。
`/opt/airgap-bundle/containers/controller/Containerfile` の有無を確認してください。
