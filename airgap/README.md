# オフライン環境対応 Ansible トレーニング環境

インターネット接続のないオフライン環境で Ansible トレーニングを実施するためのツールキットです。

## アーキテクチャ

```
┌─────────────────────────┐         ┌──────────────────────────────────────────┐
│ オンライン環境            │  USB等  │ オフライン環境                             │
│                         │ ──────> │                                          │
│ prepare-offline-        │         │  bastion (RHEL 9)                        │
│ bundle.sh を実行         │         │    └─ Ansible コントローラ                │
│                         │         │                                          │
│ offline-resources/      │         │  repo-server (RHEL 9)                    │
│ を生成                   │         │    └─ DVD ISO + UBI 10 → nginx 配信      │
│                         │         │                                          │
│                         │         │  training (RHEL 9)                       │
│                         │         │    ├─ user1: controller/node1-3/lb       │
│                         │         │    ├─ user2: controller/node1-3/lb       │
│                         │         │    └─ ... (コンテナは UBI 10 ベース)       │
│                         │         │                                          │
│                         │         │  Windows クライアント × N 台              │
│                         │         │    └─ SSH で training に接続して演習       │
└─────────────────────────┘         └──────────────────────────────────────────┘
```

> **バージョン構成**: VM は RHEL 9 ベース、演習用コンテナは UBI 10 (Red Hat Universal Base Image) ベースです。
> バージョンは `rhel-version.conf` と `group_vars/all.yml` で管理されています。
> 詳細は [開発者ガイド](docs/development-guide.md) を参照してください。

## ドキュメント

| ドキュメント | 対象者 | 内容 |
|---|---|---|
| [バンドル作成ガイド](docs/bundle-preparation.md) | エンジニア | オンライン環境でバンドルを作成する手順 |
| [構築ガイド](docs/deployment-guide.md) | エンジニア | オフライン環境にトレーニング環境を構築する手順 |
| [アップグレードガイド](docs/upgrade-guide.md) | エンジニア | デプロイ済み環境の資材更新手順 |
| [開発者ガイド](docs/development-guide.md) | 開発者 | テスト環境構築・アーキテクチャ・改修方法 |

## クイックスタート

### 1. バンドル作成（オンライン環境）

```bash
cd airgap/
./prepare-offline-bundle.sh
# DVD ISO を offline-resources/iso/ に配置（詳細は docs/bundle-preparation.md）
```

### 2. 基盤構築（オフライン環境 — bastion で実行）

```bash
# 資材を bastion に配置後:
cd /opt/airgap
./setup-controller.sh                  # ansible-core, sshpass, コレクションをインストール
vi inventory/hosts.yml                 # IP アドレス・ユーザー・パスワードを編集

SSH_ARGS='-e ansible_ssh_common_args="-o StrictHostKeyChecking=no"'
ansible-playbook -i inventory/hosts.yml playbooks/distribute-resources.yml $SSH_ARGS
ansible-playbook -i inventory/hosts.yml playbooks/repo-server-setup.yml $SSH_ARGS
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml $SSH_ARGS
```

### 3. 構築後の検証

基盤構築が正しく完了しているか、テスト環境を1つ作って確認します。

```bash
# training サーバーでテスト環境を作成
ssh <user>@<training の IP>
cd /opt/airgap
./deploy-training.sh --test 1

# テスト環境に SSH 接続して動作確認
ssh -p 2201 root@<training の IP>   # パスワード: password
ansible --version                    # ansible が使えること
dnf install -y nginx                 # パッケージがインストールできること（→ "Complete!"）
exit

# テスト環境を削除
cd /opt/airgap
./destroy-training.sh --test
```

### 3.5. 受講者ユーザーの作成

受講者リストを作成し、training サーバーにログインユーザーを一括作成します。

```bash
# bastion で実行
vi trainees.yml                    # 受講者の username を記入
ansible-playbook -i inventory/hosts.yml playbooks/setup-trainees.yml $SSH_ARGS

# パスワードが自動生成され、credentials.csv に出力される
cat credentials.csv                # 受講者に配布
```

### 4. 受講者の環境払い出し

受講者が training サーバーに自分のユーザーで SSH ログインし、環境を作成します。

```bash
# 受講者が実行（ログインユーザーで自動識別される）
ssh <username>@<training の IP>
cd /opt/airgap
./deploy-training.sh

# 完了すると接続情報が表示される:
#   ssh -p 2201 root@<training の IP>
#   パスワード: password
```

受講者は表示されたポート番号で controller コンテナに接続し、演習を開始します。

```bash
# 環境の一覧表示（管理者）
./deploy-training.sh status

# 環境の削除（受講者が自分で実行）
./deploy-training.sh destroy

# 管理者が特定の環境を削除
./deploy-training.sh destroy --user 3
./deploy-training.sh destroy --username tanaka

# 再構築（同じ user_id が再利用される）
./deploy-training.sh
```

> 詳細は [構築ガイド](docs/deployment-guide.md) を参照してください。

## ディレクトリ構成

```
airgap/
├── README.md                          このファイル
├── Makefile                           開発用 VM 管理コマンド
├── prepare-offline-bundle.sh          バンドル作成スクリプト
├── setup-controller.sh                bastion セットアップ
├── transfer-to-bastion.sh             資材転送ワンコマンド（初回デプロイ）
├── update-airgap.sh                   デプロイ済み環境の資材更新
├── deploy-training.sh                 環境の作成・一覧・削除
├── destroy-training.sh                環境削除（deploy-training.sh destroy のラッパー）
├── trainees.yml                       受講者リスト（setup-trainees.yml の入力）
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
│   ├── setup-trainees.yml              受講者ユーザー一括作成
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
│   ├── iso/                           RHEL DVD ISO
│   ├── ubi10-repos/                   UBI 10 ミラーリポジトリ（コンテナ内 dnf 用）
│   ├── container-images/              コンテナイメージ (.tar)
│   ├── binaries/                      docker-compose, sshpass 等
│   ├── packages/                      7-Zip MSI, Chocolatey nupkg 等
│   ├── pip-packages/                  Python パッケージ (.whl)
│   ├── ansible-collections/           Ansible コレクション
│   ├── training-materials/            トレーニング資材アーカイブ
│   └── checksums.sha256
├── kvm/                               テスト用 KVM スクリプト
└── docs/                              ドキュメント
```

## トレーニング環境構成（マルチユーザー）

各受講者に独立した環境がデプロイされます。

| 受講者 | サブネット | コンテナ | SSH ポート |
|---|---|---|---|
| user1 | 172.20.1.0/24 | user1_controller, user1_node1-3, user1_lb | 2201 |
| user2 | 172.20.2.0/24 | user2_controller, user2_node1-3, user2_lb | 2202 |
| ... | ... | ... | ... |

受講者は `ssh -p 220X root@<training IP>`（パスワード: `password`）で接続します。

### スクリプト一覧

| コマンド | 実行者 | 用途 |
|---|---|---|
| `setup-controller.sh` | 管理者 | bastion に ansible-core 等をインストール |
| `ansible-playbook playbooks/setup-trainees.yml` | 管理者 | 受講者ユーザーを一括作成 |
| `deploy-training.sh` | 受講者 | 自分の演習環境を作成（ログインユーザーで識別） |
| `deploy-training.sh --label 山田太郎` | 受講者 | 受講者名を指定して作成 |
| `deploy-training.sh status` | 誰でも | 全環境の一覧表示 |
| `deploy-training.sh destroy` | 受講者 | 自分の環境を削除（ログインユーザーで識別） |
| `deploy-training.sh destroy --user 3` | 管理者 | user_id 指定で削除 |
| `deploy-training.sh destroy --username tanaka` | 管理者 | ユーザー名指定で削除 |
| `deploy-training.sh --test N` | 管理者 | テスト環境を N 人分作成 |
| `deploy-training.sh destroy --test` | 管理者 | テスト環境を全て削除 |
