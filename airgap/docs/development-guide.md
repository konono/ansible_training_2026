# 開発者ガイド — テスト・アーキテクチャ・改修

オフラインデプロイ用ツールキットの開発・テスト・改修に関するガイドです。

## アーキテクチャ

### コンポーネント構成

```
┌────────────────────────────────────────────────────────────────┐
│ airgap-training ネットワーク (192.168.100.0/24, forward なし)    │
│                                                                │
│  repo-server (.5)          rhel-target (.10)                   │
│  ┌──────────────┐          ┌─────────────────────────────┐     │
│  │ DVD ISO      │          │ podman + docker-compose     │     │
│  │  ↓ mount     │  HTTP    │                             │     │
│  │ nginx        │◄─────── │ ┌─ user1_ansible_net ────┐  │     │
│  │  /repo/      │          │ │ user1_controller :2201 │  │     │
│  │  /packages/  │          │ │ user1_node1-3, lb      │  │     │
│  └──────────────┘          │ ├─ user2_ansible_net ────┤  │     │
│                            │ │ user2_controller :2202 │  │     │
│                            │ │ user2_node1-3, lb      │  │     │
│                            │ └────────────────────────┘  │     │
│  Windows クライアント (.20) └─────────────────────────────┘     │
│  ┌──────────────┐                                              │
│  │ SSH + VSCode │─── ssh -p 220X root@rhel-target              │
│  └──────────────┘                                              │
└────────────────────────────────────────────────────────────────┘
```

### ロール構成

| ロール | 対象 | 機能 |
|---|---|---|
| `setup_rhel_image_repository` | repo-server | DVD ISO マウント + yum repo 定義 |
| `create_local_repository` | repo-server | nginx HTTP 配信 + `/packages/` |
| `repository_management` | rhel-target | HTTP リポジトリをクライアントに設定 |
| `common` | rhel-target | チェックサム検証 |
| `rhel_podman` | rhel-target | podman + docker-compose インストール |
| `rhel_training` | rhel-target | 演習サーバー基盤セットアップ（イメージロード・スクリプト配置） |
| `rhel_training_multi` | rhel-target | マルチユーザー環境デプロイ（per-user コンテナ起動・repo 設定） |
| `win_client_ssh` | windows_clients | Windows OpenSSH 設定 |
| `win_client_vscode` | windows_clients | VSCode + Remote-SSH インストール |

### Playbook 実行順序

```
site.yml
  ├── repo-server-setup.yml (hosts: repo_server)
  │     → setup_rhel_image_repository → create_local_repository
  ├── rhel-setup.yml (hosts: rhel)
  │     → common → rhel_podman → rhel_training
  └── windows-client-setup.yml (hosts: windows_clients)
        → win_client_ssh → win_client_vscode
```

## テスト用 VM イメージの入手

[バンドル作成ガイド](bundle-preparation.md) で生成される `offline-resources/` にはデプロイ先環境で使うリソースのみが含まれます。開発テストでは追加で KVM 用の VM イメージが必要です。

### RHEL KVM ゲストイメージ

Red Hat カスタマーポータルからダウンロード:

```bash
mkdir -p offline-resources/vm-images/
# rhel-version.conf の RHEL_VERSION に合わせたイメージを配置
cp /path/to/rhel-9.4-x86_64-kvm.qcow2 offline-resources/vm-images/
```

- URL: https://access.redhat.com/downloads/content/rhel （Cloud and Container Images セクション）
- サイズ: 約 1GB

### Windows 11 qcow2 イメージ（cocoonstack）

[cocoonstack/windows](https://github.com/cocoonstack/windows) が WinRM/SSH 設定済みの Windows 11 VM イメージを GitHub Container Registry に OCI アーティファクトとして公開しています。

14GB の qcow2 ファイルが約 1.9GB × 8 パーツに分割して格納されており、`oras` CLI でダウンロードして結合します。

```bash
# oras CLI のインストール
# OCI Registry As Storage — コンテナレジストリから任意のファイルを取得する CLI
curl -fsSL https://github.com/oras-project/oras/releases/download/v1.2.2/oras_1.2.2_linux_amd64.tar.gz \
  | tar xz -C /usr/local/bin/ oras

# ダウンロード（9ファイル: 8パーツ + SHA256SUMS, 計 約14GB）
mkdir -p offline-resources/vm-images/win11-parts/
cd offline-resources/vm-images/win11-parts/
oras pull ghcr.io/cocoonstack/windows/win11:25h2

# ダウンロードされるファイル:
#   windows-11-25h2.qcow2.00.qcow2.part  (1.9GB)
#   windows-11-25h2.qcow2.01.qcow2.part  (1.9GB)
#   ...（計 8 パーツ）
#   windows-11-25h2.qcow2.07.qcow2.part  (756MB)
#   SHA256SUMS

# チェックサム検証 → パーツ結合 → クリーンアップ
sha256sum -c SHA256SUMS
cat *.part > ../windows-11-25h2.qcow2
cd .. && rm -rf win11-parts/
ls -lh windows-11-25h2.qcow2  # 約 14GB
```

cocoonstack イメージの仕様:

| 項目 | 値 |
|---|---|
| OS | Windows 11 Pro (Build 26200) |
| ユーザー / パスワード | `cocoon` / `C@c#on160` |
| WinRM | Basic 認証, ポート 5985 |
| OpenSSH | ポート 22（デフォルトシェル: cmd.exe） |
| 仮想ディスク | 40GB (シンプロビジョニング) |

> Ansible SSH 接続時のシェル設定は `group_vars/windows_clients.yml` で定義されています。

## テスト環境（Makefile）

### 前提

- KVM 対応ホスト（`/dev/kvm` 有り、bare-metal 推奨）
- `offline-resources/` が作成済み（バンドル + VM イメージ）
- メモリ: 16GB 以上（RHEL 2台 + Windows 1台 = 14GB）

### コマンド一覧

```bash
cd airgap/
make help

# 主要コマンド:
make setup-vms      # 全 VM を作成・起動
make deploy-all     # 全 Playbook を実行
make verify-airgap  # airgap 状態を検証
make test           # airgap + RHEL 検証
make destroy-vms    # 全 VM を削除
make full-test      # 削除→作成→デプロイ→検証（一気通貫）
```

テスト用インベントリ (`/tmp/airgap-test-inventory.yml`) が必要です:

```yaml
all:
  children:
    repo_server:
      hosts:
        repo-server:
          ansible_host: 192.168.100.5
          ansible_user: root
          ansible_password: password
    rhel:
      hosts:
        rhel-target:
          ansible_host: 192.168.100.10
          ansible_user: root
          ansible_password: password
    # Windows クライアントがある場合
    # windows_clients:
    #   hosts:
    #     win-client-01:
    #       ansible_host: 192.168.100.20
    #       ansible_user: cocoon
    #       ansible_password: "C@c#on160"
```

## テスト時の注意事項

### `-netdev user` は絶対に使わない

QEMU の `-netdev user` はホスト経由でインターネットに到達可能な NAT ゲートウェイ (10.0.2.2) を提供します。この環境でテストすると、オフライン環境で失敗すべきオンラインフォールバックが成功してしまいます。

VM は必ず libvirt の `airgap-training` ネットワーク（`<forward>` なし）上で起動してください。

### オフライン検証は必須

テスト前に全 VM で `ping 8.8.8.8` が `Network is unreachable` を返すことを確認してください。

```bash
make verify-airgap
```

### Windows クライアントの接続

Windows クライアントへの Ansible 接続は SSH を使用します（`group_vars/windows_clients.yml` で設定）。Windows 上ではコンテナを起動せず、OpenSSH と VSCode のセットアップのみを行います。受講者は SSH で Linux training サーバーに接続して演習を実施します。

### KVM ゲストイメージのディスク拡張

Red Hat 提供の KVM ゲストイメージはデフォルトで 10GB 未満のパーティションを持ちます。DVD ISO (11GB) の転送前にディスク拡張が必要です。

```bash
qemu-img resize image.qcow2 20G  # VM 作成前
# VM 内で（パーティション番号は lsblk で確認）:
growpart /dev/vda 4 && xfs_growfs /
# ディスクフル状態では TMPDIR 指定が必要:
# TMPDIR=/dev/shm growpart /dev/vda 4 && xfs_growfs /
```

> RHEL 9.4 KVM ゲストイメージのパーティション構成: vda1 (1M BIOS), vda2 (200M EFI), vda3 (1G boot), vda4 (rootfs)。`growpart` の引数はパーティション番号 `4` です。

## 改修時のガイドライン

### コンテナイメージの更新

```bash
# Containerfile を編集
vi containers/controller/Containerfile

# バンドルを再作成
cd airgap/
./prepare-offline-bundle.sh

# テスト
make full-test
```

### 新しいパッケージの追加

`packages/` ディレクトリに MSI/nupkg を追加し、チェックサムを再生成:

```bash
cp new-package.msi offline-resources/packages/
cd offline-resources/ && find . -type f ! -name 'checksums.sha256' -exec sha256sum {} \; > checksums.sha256
```

リポジトリサーバーの nginx は `/packages/` 配下を autoindex で配信するため、ファイルを置くだけで HTTP アクセス可能になります。

### トレーニングコンテナ内のリポジトリ設定

トレーニングコンテナ（UBI 10 ベース）は UBI リポジトリがデフォルトで有効です。オフライン環境では以下が自動実行されます:

1. UBI リポジトリ (`ubi.repo`) の無効化
2. `subscription-manager` の repo 管理無効化
3. リポジトリサーバーの BaseOS/AppStream を設定

これにより `dnf install nginx` 等がリポジトリサーバー経由で動作します。

## RHEL バージョンの切り替え

VM の RHEL バージョンは以下の 2 ファイルで管理されています。両方を同時に変更してください。

| ファイル | 用途 | 変更する値 |
|---|---|---|
| `rhel-version.conf` | Shell スクリプト・Makefile | `RHEL_VERSION`, `RHEL_MAJOR` |
| `group_vars/all.yml` | Ansible Playbook | `rhel_version` |

```bash
# 例: RHEL 9.4 → 10.2 に切り替え

# 1. rhel-version.conf
sed -i 's/RHEL_VERSION=9.4/RHEL_VERSION=10.2/' rhel-version.conf
sed -i 's/RHEL_MAJOR=9/RHEL_MAJOR=10/' rhel-version.conf

# 2. group_vars/all.yml
sed -i 's/rhel_version: "9.4"/rhel_version: "10.2"/' group_vars/all.yml

# 3. 対応する DVD ISO と KVM イメージを配置
cp /path/to/rhel-10.2-x86_64-dvd.iso offline-resources/iso/
cp /path/to/rhel-10.2-x86_64-kvm.qcow2 offline-resources/vm-images/
```

コンテナイメージ (UBI 10) は RHEL バージョンに依存しないため、切り替え不要です。

## 既知の制限事項

| 制限 | 影響 | 回避策 |
|---|---|---|
| ネスト仮想化の性能 | Windows VM が極端に遅い | 物理マシンでテスト、または VM メモリを 8GB 以上に |
| Chocolatey パッケージ | 個別の nupkg を事前取得が必要 | `packages/` に nupkg を追加 |
| `win_feature` (IIS) | Windows 11 Pro では利用不可 | Windows Server 環境でのみ使用 |
| 演習 11 の 7-Zip | インターネット URL からのダウンロード不可 | `path=http://repo-server/packages/7z.msi` に変更 |
