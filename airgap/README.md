# Airgap 環境対応 Ansible 研修環境セットアップ

インターネット接続のない（エアギャップ）環境で Ansible 研修を実施するためのツールキットです。
RHEL 10 および Windows 11 をターゲットOSとしてサポートしています。

## 概要

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│ オンライン環境       │  USB等  │ エアギャップ環境                  │
│                     │ ──────> │                                  │
│ prepare-offline-    │         │  Ansible Controller              │
│ bundle.sh を実行    │         │    │                              │
│                     │         │    ├─> RHEL 10 VM (podman)       │
│ offline-resources/  │         │    │     └─ 研修コンテナ×5        │
│ を生成              │         │    │                              │
│                     │         │    └─> Windows 11 VM (podman)    │
│                     │         │          └─ 研修コンテナ×5        │
└─────────────────────┘         └──────────────────────────────────┘
```

## クイックスタート

### Step 1: オフラインバンドルの作成（オンライン環境で実行）

```bash
# インターネット接続のある RHEL 10 マシンで実行
cd airgap/
./prepare-offline-bundle.sh
```

生成される `offline-resources/` ディレクトリには以下が含まれます:
- ビルド済みコンテナイメージ（controller, node）
- RPMパッケージ（podman + 依存関係）
- docker-compose バイナリ
- pip パッケージ（ansible, pywinrm 等）
- Ansible コレクション
- 研修資材アーカイブ

### Step 2: バンドルの転送

`airgap/` ディレクトリ全体をUSBドライブ等でエアギャップ環境に転送します。

### Step 3: KVM テスト環境の構築（オプション）

KVM 対応ホストでテスト用 VM を作成する場合:

```bash
cd airgap/kvm/

# KVM ホストの準備
./prepare-kvm-host.sh

# RHEL 10 VM の作成（隔離ネットワーク接続）
./create-rhel-vm.sh /path/to/rhel-10-x86_64-dvd.iso

# Windows 11 VM の作成（隔離ネットワーク接続）
./create-windows-vm.sh /path/to/Win11_Japanese_x64.iso
```

### Step 4: RHEL 10 ターゲットへのデプロイ

```bash
cd airgap/

# 1. バンドルをターゲットに転送
#    ISO方式（KVM VMの場合）:
#    mkisofs -o /tmp/bundle.iso -R -J offline-resources/
#    virsh attach-disk rhel10-target /tmp/bundle.iso sdb --type cdrom

# 2. ターゲットのVM内でISO をマウントしてバンドルをコピー
#    mount /dev/sr0 /mnt
#    cp -r /mnt/* /opt/airgap-bundle/

# 3. inventory を編集
vi inventory/rhel-hosts.yml

# 4. Playbook を実行
ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml

# 5. 検証
ansible-playbook -i inventory/rhel-hosts.yml playbooks/verify.yml
```

### Step 5: Windows 11 ターゲットへのデプロイ

```bash
# 1. Windows に WinRM を設定（管理者PowerShellで実行）
#    Set-ExecutionPolicy RemoteSigned -Force
#    .\templates\enable-winrm.ps1

# 2. バンドルを C:\airgap-bundle にコピー

# 3. inventory を編集
vi inventory/windows-hosts.yml

# 4. Playbook を実行
ansible-playbook -i inventory/windows-hosts.yml playbooks/windows-setup.yml
```

## ディレクトリ構成

```
airgap/
├── README.md                     # このファイル
├── prepare-offline-bundle.sh     # オフラインバンドル作成スクリプト
├── ansible.cfg                   # Ansible 設定
├── inventory/                    # インベントリ
│   ├── rhel-hosts.yml
│   └── windows-hosts.yml
├── group_vars/                   # 変数定義
│   ├── all.yml                   # 共通変数
│   ├── rhel.yml                  # RHEL固有変数
│   └── windows.yml               # Windows固有変数
├── playbooks/
│   ├── site.yml                  # マスターPlaybook
│   ├── rhel-setup.yml            # RHEL 10 セットアップ
│   ├── windows-setup.yml         # Windows 11 セットアップ
│   ├── verify.yml                # デプロイ後検証
│   └── roles/
│       ├── common/               # バンドル検証
│       ├── rhel_podman/          # podman + docker-compose インストール
│       ├── rhel_training/        # イメージロード・環境起動
│       ├── win_podman/           # WSL2 + Podman インストール
│       └── win_training/         # イメージロード・環境起動
├── offline-resources/            # オフラインリソース（自動生成）
├── templates/
│   ├── docker-compose-airgap.yml.j2   # Airgap版 compose テンプレート
│   └── enable-winrm.ps1              # WinRM 有効化スクリプト
└── kvm/
    ├── create-airgap-network.xml      # 隔離ネットワーク定義
    ├── prepare-kvm-host.sh            # KVM ホスト準備
    ├── create-rhel-vm.sh              # RHEL VM 作成
    └── create-windows-vm.sh           # Windows VM 作成
```

## 研修環境構成

デプロイ後、各ターゲットマシン上に以下のコンテナが起動します:

| コンテナ | IP | 役割 |
|----------|-----|------|
| controller | 172.20.0.10 | Ansible 実行環境（SSH: port 2220） |
| node1 | 172.20.0.11 | Web サーバ |
| node2 | 172.20.0.12 | Web サーバ |
| node3 | 172.20.0.13 | Web サーバ |
| lb | 172.20.0.14 | ロードバランサ |

研修受講者は `ssh -p 2220 root@localhost`（パスワード: `password`）でコントローラに接続し、Ansible の演習を実施します。

## 必要条件

### オンライン環境（バンドル作成用）
- RHEL 10 / CentOS 10 または互換OS
- podman
- python3 + pip
- ansible（pip経由）
- インターネット接続

### ターゲット RHEL 10
- 最小インストール以上
- 4GB RAM, 4 vCPU, 100GB ディスク
- SSH 有効

### ターゲット Windows 11
- Pro または Enterprise エディション
- 8GB RAM, 4 vCPU, 120GB ディスク
- WinRM 有効（`enable-winrm.ps1` で設定）

## トラブルシューティング

### コンテナが起動しない
```bash
podman ps -a                          # 全コンテナの状態確認
podman logs controller                # ログ確認
docker-compose -f containers/docker-compose.yml logs
```

### ansible ping が失敗する
```bash
# コントローラ内でSSH接続をテスト
podman exec controller sshpass -p password ssh -o StrictHostKeyChecking=no root@172.20.0.11 hostname
```

### RPMインストールが失敗する（RHEL）
```bash
# ローカルリポジトリの状態確認
ls /opt/airgap-bundle/rpm-packages/podman/
createrepo_c /opt/airgap-bundle/rpm-packages/podman/
dnf repolist
```
