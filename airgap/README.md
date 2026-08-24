# Airgap 環境対応 Ansible 研修環境

インターネット接続のないエアギャップ環境で Ansible 研修を実施するためのツールキットです。

## アーキテクチャ

```
┌─────────────────────────┐         ┌──────────────────────────────────────────┐
│ オンライン環境            │  USB等  │ エアギャップ環境                          │
│                         │ ──────> │                                          │
│ prepare-offline-        │         │  bastion (RHEL 10)                       │
│ bundle.sh を実行         │         │    └─ Ansible コントローラ                │
│                         │         │                                          │
│ offline-resources/      │         │  repo-server (RHEL 10)                   │
│ を生成                   │         │    └─ DVD ISO → nginx HTTP 配信           │
│                         │         │                                          │
│                         │         │  training (RHEL 10)                      │
│                         │         │    ├─ user1: controller/node1-3/lb       │
│                         │         │    ├─ user2: controller/node1-3/lb       │
│                         │         │    └─ ...                                │
│                         │         │                                          │
│                         │         │  Windows クライアント × N 台              │
│                         │         │    └─ SSH で training に接続して演習       │
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

# 2. DVD ISO を offline-resources/iso/ に配置
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
├── setup-controller.sh                bastion セットアップ
├── transfer-to-bastion.sh             資材転送ワンコマンド
├── deploy-training.sh                 受講者向け環境デプロイ
├── destroy-training.sh                環境削除
├── ansible.cfg                        Ansible 設定
├── inventory/                         インベントリテンプレート
│   ├── hosts.yml                      統合インベントリ
│   ├── rhel-hosts.yml                 RHEL 単体
│   └── windows-hosts.yml              Windows 単体
├── group_vars/                        変数定義
│   ├── all.yml                        共通変数
│   ├── rhel.yml                       RHEL 固有
│   └── windows_clients.yml            Windows クライアント固有
├── scripts/
│   └── allocate.py                    ユーザー ID 自動採番
├── playbooks/
│   ├── site.yml                       マスター Playbook
│   ├── distribute-resources.yml       資材配布
│   ├── repo-server-setup.yml          リポジトリサーバー構築
│   ├── rhel-setup.yml                 Linux 演習サーバー構築
│   ├── windows-client-setup.yml       Windows クライアント設定
│   ├── deploy-my-env.yml              セルフサービスデプロイ
│   ├── destroy-my-env.yml             環境削除
│   ├── training-status.yml            割当状況確認
│   ├── verify.yml                     検証
│   └── roles/
│       ├── common/                    チェックサム検証
│       ├── setup_rhel_image_repository/ ISO マウント + yum repo
│       ├── create_local_repository/   nginx HTTP 配信
│       ├── repository_management/     クライアント側 repo 設定
│       ├── rhel_podman/               podman + docker-compose
│       ├── rhel_training/             演習サーバー基盤セットアップ
│       ├── rhel_training_multi/       マルチユーザー環境デプロイ
│       ├── win_client_ssh/            Windows OpenSSH 設定
│       └── win_client_vscode/         Windows VSCode + Remote-SSH
├── offline-resources/                 オフラインリソース（git 管理外）
│   ├── iso/                           RHEL 10 DVD ISO
│   ├── container-images/              コンテナイメージ (.tar)
│   ├── binaries/                      docker-compose, sshpass 等
│   ├── packages/                      7-Zip MSI, Chocolatey nupkg 等
│   ├── pip-packages/                  Python パッケージ (.whl)
│   ├── ansible-collections/           Ansible コレクション
│   ├── training-materials/            研修資材アーカイブ
│   └── checksums.sha256
├── kvm/                               テスト用 KVM スクリプト
└── docs/                              ドキュメント
```

## 研修環境構成（マルチユーザー）

各受講者に独立した環境がデプロイされます。

| 受講者 | サブネット | コンテナ | SSH ポート |
|---|---|---|---|
| user1 | 172.20.1.0/24 | user1_controller, user1_node1-3, user1_lb | 2201 |
| user2 | 172.20.2.0/24 | user2_controller, user2_node1-3, user2_lb | 2202 |
| ... | ... | ... | ... |

受講者は `ssh -p 220X root@<training IP>`（パスワード: `password`）で接続します。
