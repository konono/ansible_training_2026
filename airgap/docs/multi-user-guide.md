# マルチユーザー研修環境ガイド

1 台の Linux サーバーに複数人分の演習環境を構築し、各受講者が自分の Windows 端末から独立して利用するための手順書です。

## アーキテクチャ

```
Windows クライアント                    Linux サーバー (192.168.100.10)
┌──────────────┐                       ┌──────────────────────────────────────┐
│ 受講者A      │ ssh -p 2201 ─────────>│  user1 環境 (172.20.1.0/24)         │
│ 192.168.100.31│                      │    controller (.10) :2201            │
└──────────────┘                       │    node1-3 (.11-.13), lb (.14)       │
┌──────────────┐                       │                                      │
│ 受講者B      │ ssh -p 2202 ─────────>│  user2 環境 (172.20.2.0/24)         │
│ 192.168.100.32│                      │    controller (.10) :2202            │
└──────────────┘                       │    node1-3 (.11-.13), lb (.14)       │
┌──────────────┐                       │                                      │
│ 受講者C      │ ssh -p 2203 ─────────>│  user3 環境 (172.20.3.0/24)         │
│ 192.168.100.33│                      │    controller (.10) :2203            │
└──────────────┘                       └──────────────────────────────────────┘
```

各受講者の環境は完全に隔離されています:
- **サブネット**: `172.20.{user_id}.0/24`（ユーザーごとに独立）
- **コンテナ名**: `user{id}_controller`, `user{id}_node1` ...（名前衝突なし）
- **SSH ポート**: `2200 + user_id`（最大 99 人分）
- **研修資材**: `/opt/training/user{id}/`（workspace が独立）

## 前提条件

### Linux サーバー

- RHEL 10（podman + docker-compose インストール済み）
- リポジトリサーバー構築済み（`repo-server-setup.yml` + `rhel-setup.yml` の `rhel_podman` ロール実行済み）
- コンテナイメージロード済み
- メモリ目安: 受講者 1 人あたり約 2GB（5 人なら 10GB + OS 分）
- `/opt/airgap/` に airgap ディレクトリが配置済み
- `/opt/training/` に十分なディスク空き

### Windows クライアント

- `windows-client-setup.yml` でセットアップ済み（Ansible + SSH + VSCode）
- Linux サーバーに SSH で接続可能

## セットアップ手順（管理者）

### 1. Linux サーバーの準備

リポジトリサーバーと Linux サーバーの基本セットアップは通常の手順で行います。

```bash
# コントローラから実行
./setup-controller.sh /opt/rhel10.iso
ansible-playbook -i inventory/hosts.yml playbooks/repo-server-setup.yml
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml
```

> **注意**: `rhel-setup.yml` はシングルユーザー版の環境を構築します。マルチユーザー版を使う場合、`rhel-setup.yml` の `rhel_podman` ロールで podman/docker-compose のインストールだけが必要です。シングルユーザー版のコンテナは起動しても問題ありませんが、受講者はマルチユーザー版を使います。

### 2. Windows クライアントのセットアップ

```bash
ansible-playbook -i inventory/hosts.yml playbooks/windows-client-setup.yml
```

これにより各 Windows に Ansible、SSH、VSCode がインストールされます。

### 3. 受講者への案内

以下を受講者に伝えてください:

```
■ 演習環境の構築（初回のみ）
  PowerShell を開き、以下を実行:
    cd C:\airgap
    ansible-playbook -i inventory/hosts.yml playbooks/deploy-my-env.yml

  完了すると接続情報が表示されます:
    ssh -p 22XX root@<Linux サーバー IP>
    パスワード: password

■ 演習環境への接続
  表示されたポート番号で SSH 接続:
    ssh -p 22XX root@<Linux サーバー IP>

  VSCode で接続:
    Ctrl+Shift+P → "Remote-SSH: Connect to Host"
    → ホスト名と表示されたポート番号を入力

■ 演習環境のリセット
    ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml
    ansible-playbook -i inventory/hosts.yml playbooks/deploy-my-env.yml
```

## 受講者の操作

### 環境の構築

```powershell
cd C:\airgap
ansible-playbook -i inventory/hosts.yml playbooks/deploy-my-env.yml
```

出力例:
```
========================================
演習環境の構築が完了しました！

接続方法:
  ssh -p 2203 root@192.168.100.10
  パスワード: password

コンテナ:
  user3_controller  Up 10 seconds  0.0.0.0:2203->22/tcp
  user3_node1       Up 10 seconds  22/tcp
  user3_node2       Up 10 seconds  22/tcp
  user3_node3       Up 10 seconds  22/tcp
  user3_lb          Up 10 seconds  22/tcp
========================================
```

### 環境への接続

```powershell
ssh -p 2203 root@192.168.100.10
# パスワード: password
```

controller にログインすると、通常の演習と同じ環境です:
- `ansible --version` で Ansible が利用可能
- `node1` (172.20.3.11), `node2` (172.20.3.12), `node3` (172.20.3.13), `lb` (172.20.3.14) が演習対象ノード

### 環境の削除

```powershell
ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml -e caller_ip=<自分のWindowsのIP>
```

### 環境の再構築

削除後に再度 `deploy-my-env.yml` を実行すれば、同じ user_id で環境が再構築されます。

## 管理者の操作

### 全ユーザーの割当状況を確認

```bash
ansible-playbook -i inventory/hosts.yml playbooks/training-status.yml
```

出力例:
```
user1 | ACTIVE    | 192.168.100.31 (WIN-PC01) | port 2201 | 172.20.1.0/24
user2 | ACTIVE    | 192.168.100.32 (WIN-PC02) | port 2202 | 172.20.2.0/24
user3 | ALLOCATED | 192.168.100.33 (WIN-PC03) | port 2203 | 172.20.3.0/24
user4 | RELEASED  | 192.168.100.34 (WIN-PC04) | port 2204 | 172.20.4.0/24
---
合計: 4 件 (active: 2, allocated: 1, released: 1)
```

| ステータス | 意味 |
|---|---|
| `ALLOCATED` | ID 予約済み、環境構築中（または構築失敗） |
| `ACTIVE` | 環境構築完了、利用中 |
| `RELEASED` | 環境削除済み、ID 再利用可能 |

### 特定ユーザーの環境を削除

```bash
ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml \
  -e caller_ip=192.168.100.33
```

### 割当情報ファイルの直接確認

```bash
cat /opt/training/allocations.json | python3 -m json.tool
```

### 全環境の一括削除

```bash
# 全コンテナを停止・削除
ssh root@<linux-server> 'podman stop -a; podman rm -af; podman network prune -f'

# 割当情報をリセット
ssh root@<linux-server> 'rm -f /opt/training/allocations.json'

# 研修ディレクトリを削除
ssh root@<linux-server> 'rm -rf /opt/training/user*'
```

## 仕組みの詳細

### 採番の仕組み

`/opt/airgap/scripts/allocate.py` が `flock` による排他制御で安全に user_id を採番します。

- 同じ Windows IP から再実行 → 同じ user_id を返す（冪等性）
- `released` ステータスの ID → 次の採番で再利用
- `flock --timeout 30` + Ansible `retries: 3` で二重保護
- Python 標準ライブラリのみ、追加パッケージ不要

### リソース共有

| リソース | 共有方式 |
|---|---|
| コンテナイメージ | 全ユーザー共有（read-only、1 回ロード） |
| リポジトリサーバー | 全ユーザー共有（HTTP 経由） |
| 研修資材 tar.gz | 1 ファイル → 各ユーザーに展開 |
| workspace | ユーザーごとに独立ディレクトリ |
| コンテナ | ユーザーごとに 5 台（独立サブネット） |

### 制限事項

| 制限 | 詳細 |
|---|---|
| 最大ユーザー数 | 99 人（ポート 2201〜2299、サブネット 172.20.1〜99） |
| メモリ | 受講者 1 人あたり約 2GB |
| ディスク | 受講者 1 人あたり約 3GB（資材 + workspace） |
| コンテナイメージロード | 初回のみ数分かかる |
