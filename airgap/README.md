# Airgap 環境対応 Ansible 研修環境

インターネット接続のないエアギャップ環境で Ansible 研修を実施するためのツールキットです。

## アーキテクチャ

```
┌─────────────────────────┐         ┌──────────────────────────────────────────┐
│ オンライン環境            │  USB等  │ エアギャップ環境                          │
│                         │ ──────> │                                          │
│ prepare-offline-        │         │  repo-server (192.168.100.5)             │
│ bundle.sh を実行         │         │    └─ RHEL 10 DVD ISO → nginx HTTP 配信  │
│                         │         │                                          │
│ offline-resources/      │         │  rhel-target (192.168.100.10)            │
│ を生成                   │         │    └─ podman + 研修コンテナ×5             │
│                         │         │         controller / node1-3 / lb        │
│                         │         │                                          │
│                         │         │  win11-target (192.168.100.20) [オプション]│
│                         │         │    └─ WSL2 + Podman + 研修コンテナ×5      │
└─────────────────────────┘         └──────────────────────────────────────────┘
```

## ドキュメント

| ドキュメント | 対象者 | 内容 |
|---|---|---|
| [バンドル作成ガイド](docs/bundle-preparation.md) | エンジニア | オンライン環境でバンドルを作成する手順 |
| [構築ガイド](docs/deployment-guide.md) | エンジニア / お客様 | airgap 環境に研修環境を構築する手順 |
| [開発者ガイド](docs/development-guide.md) | 開発者 | テスト環境構築・アーキテクチャ・改修方法 |

## クイックスタート

```bash
# 1. オンライン環境でバンドルを作成
cd airgap/
./prepare-offline-bundle.sh

# 2. DVD ISO / VM イメージを offline-resources/ に配置
#    → 詳細は docs/bundle-preparation.md

# 3. airgap/ ディレクトリ全体を USB 等で持ち込み

# 4. お客様環境でデプロイ
#    → 詳細は docs/deployment-guide.md
```

## ディレクトリ構成

```
airgap/
├── README.md                          このファイル
├── Makefile                           開発用 VM 管理コマンド
├── prepare-offline-bundle.sh          バンドル作成スクリプト
├── ansible.cfg                        Ansible 設定
├── inventory/                         インベントリテンプレート
│   ├── rhel-hosts.yml
│   └── windows-hosts.yml
├── group_vars/                        変数定義
│   ├── all.yml                        共通変数
│   ├── rhel.yml                       RHEL 固有
│   └── windows.yml                    Windows 固有
├── playbooks/
│   ├── site.yml                       マスター Playbook
│   ├── repo-server-setup.yml          リポジトリサーバー構築
│   ├── rhel-setup.yml                 RHEL 研修環境構築
│   ├── windows-setup.yml              Windows 研修環境構築
│   ├── verify.yml                     検証
│   └── roles/
│       ├── common/                    チェックサム検証
│       ├── setup_rhel_image_repository/ ISO マウント + yum repo
│       ├── create_local_repository/   nginx HTTP 配信
│       ├── repository_management/     クライアント側 repo 設定
│       ├── rhel_podman/               podman + docker-compose
│       ├── rhel_training/             イメージロード・コンテナ起動
│       ├── win_podman/                WSL2 + Podman
│       └── win_training/              イメージロード・コンテナ起動
├── offline-resources/                 オフラインリソース（git 管理外）
│   ├── iso/                           RHEL 10 DVD ISO
│   ├── vm-images/                     KVM ゲストイメージ
│   ├── container-images/              コンテナイメージ (.tar)
│   ├── binaries/                      docker-compose, sshpass 等
│   ├── packages/                      7-Zip MSI, Chocolatey nupkg 等
│   ├── pip-packages/                  Python パッケージ (.whl)
│   ├── ansible-collections/           Ansible コレクション
│   ├── training-materials/            研修資材アーカイブ
│   └── checksums.sha256
├── templates/
│   ├── enable-ssh.ps1                 Windows SSH 有効化（標準）
│   └── enable-winrm.ps1              Windows WinRM 有効化（代替）
├── kvm/                               テスト用 KVM スクリプト
│   ├── create-airgap-network.xml
│   ├── prepare-kvm-host.sh
│   ├── create-rhel-vm.sh
│   └── create-windows-vm.sh
└── docs/
    ├── bundle-preparation.md          バンドル作成ガイド
    ├── deployment-guide.md            構築ガイド
    └── development-guide.md           開発者ガイド
```

## 研修環境構成

デプロイ後、各ターゲット上に以下のコンテナが起動します。

| コンテナ | IP | 役割 |
|---|---|---|
| controller | 172.20.0.10 | Ansible 実行環境（SSH: port 2220） |
| node1 | 172.20.0.11 | 演習対象ノード |
| node2 | 172.20.0.12 | 演習対象ノード |
| node3 | 172.20.0.13 | 演習対象ノード |
| lb | 172.20.0.14 | 演習対象ノード |

受講者は `ssh -p 2220 root@<ターゲットIP>`（パスワード: `password`）で接続します。
