# マルチユーザートレーニング環境ガイド

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
- **トレーニング資材**: `/opt/training/user{id}/`（workspace が独立）

## 前提条件

### Linux サーバー

- RHEL 9（podman + docker-compose インストール済み）
- リポジトリサーバー構築済み（`repo-server-setup.yml` + `rhel-setup.yml` 実行済み）
- コンテナイメージロード済み
- `/opt/airgap/` に airgap ディレクトリが配置済み
- `/opt/training/` に十分なディスク空き

> **実測値**: 1 環境（5 コンテナ）あたりメモリ約 80MB、ディスク約 5MB。
> 20 人（100 コンテナ）で実測メモリ 2.2GB。

### Windows クライアント

- OpenSSH Client が有効
- Linux サーバーに SSH で接続可能

## セットアップ手順（管理者）

[構築ガイド](deployment-guide.md) の Step 1〜4 を実行してください。

## 受講者の操作

### 環境の構築

```powershell
# 1. training サーバーに SSH 接続
ssh root@<training の IP>
```
パスワード: `password`（デフォルト）

```bash
# 2. 演習環境を構築（IP は SSH 接続元から自動取得されます）
cd /opt/airgap
./deploy-training.sh
```

出力例:
```
接続元 IP: 192.168.100.31
========================================
演習環境の構築が完了しました！

接続方法:
  ssh -p 2201 root@192.168.100.10
  パスワード: password

コンテナ:
  user1_controller  Up 10 seconds  0.0.0.0:2201->22/tcp
  user1_node1       Up 10 seconds  22/tcp
  user1_node2       Up 10 seconds  22/tcp
  user1_node3       Up 10 seconds  22/tcp
  user1_lb          Up 10 seconds  22/tcp
========================================
```

### 環境への接続

**新しい PowerShell ウィンドウ**を開いて:

```powershell
ssh -o StrictHostKeyChecking=no -p <表示されたポート番号> root@<training の IP>
# パスワード: password
```

**VSCode で接続する場合:**
1. `Ctrl+Shift+P` → `Remote-SSH: Connect to Host`
2. `root@<training の IP> -p <ポート番号>` と入力
3. パスワード: `password`

### 環境の削除・再構築

```bash
# training サーバーに SSH 接続して実行
ssh root@<training の IP>
cd /opt/airgap
./destroy-training.sh      # 環境削除
./deploy-training.sh       # 再構築（同じ user_id で再利用されます）
```

## 管理者の操作

### 全ユーザーの割当状況を確認

bastion で:
```bash
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/training-status.yml --limit rhel-target
```

または training サーバーで直接:
```bash
python3 /opt/airgap/scripts/allocate.py --action status | python3 -m json.tool
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

### 全環境の一括リセット

```bash
ssh root@<training>
podman stop -a; podman rm -af; podman network prune -f
rm -f /opt/training/allocations.json
rm -rf /opt/training/user*
```

## 仕組みの詳細

### 採番の仕組み

`/opt/airgap/scripts/allocate.py` が内蔵の排他制御（`fcntl.flock`）で安全に user_id を採番します。

- 同じ IP から再実行 → 同じ user_id を返す（冪等性）
- `released` ステータスの ID → 次の採番で再利用（最小 ID 優先）
- スクリプト内蔵の `fcntl.flock` で排他制御（外部ラッパー不要）
- Python 標準ライブラリのみ、追加パッケージ不要
- user_id の上限は 99（ポート 2201〜2299）

### リソース共有

| リソース | 共有方式 |
|---|---|
| コンテナイメージ | 全ユーザー共有（read-only、1 回ロード） |
| リポジトリサーバー | 全ユーザー共有（HTTP 経由） |
| トレーニング資材 tar.gz | 1 ファイル → 各ユーザーに展開 |
| workspace | ユーザーごとに独立ディレクトリ |
| コンテナ | ユーザーごとに 5 台（独立サブネット） |

### 制限事項

| 制限 | 詳細 |
|---|---|
| 最大ユーザー数 | 99 人（ポート 2201〜2299、サブネット 172.20.1〜99） |
| メモリ | 1 環境あたり約 80MB（OS ベースライン 2-3GB 別途） |
| ディスク | 1 環境あたり約 5MB |
| コンテナイメージロード | 初回のみ数分かかる |
