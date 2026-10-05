# リリースノート — stateful-trainees-management

## 変更概要

受講者管理のステートフル化、become 設計の整理、管理ツールの追加。

## 変更ファイル一覧

### 新規ファイル

| ファイル | 説明 |
|---|---|
| `manage-training.sh` | 管理者向け環境管理ツール（list / info / health / cleanup 等） |

### 変更ファイル

| ファイル | 変更内容 |
|---|---|
| `ansible.cfg` | `[privilege_escalation]` セクション削除（become は play レベルで制御） |
| `inventory/hosts.yml` | `ansible_become: true` 削除（become_method / become_password は維持） |
| `playbooks/setup-trainees.yml` | 全面リライト: ステートフル管理（追加/削除/パスワード更新）、per-user CSV |
| `playbooks/templates/trainees-updated.yml.j2` | ステートフル管理の説明コメントを追加 |
| `playbooks/destroy-my-env.yml` | テンプレート再帰ループバグ修正 |
| `deploy-training.sh` | --help 対応、status の受講者向け表示、show_usage 定義順修正 |
| `trainees.yml` | ヘッダーコメント更新（ステートフル管理の説明） |
| `update-airgap.sh` | `--create-tar` / `--apply-tar` 追加、`credentials.csv` → `credentials/` 対応 |
| `docs/deployment-guide.md` | インベントリ例から `ansible_become: true` 行を削除 |

## デプロイ済み環境への適用手順

### 方法 A: update-airgap.sh を使う（推奨）

#### A-1: オンライン環境から直接リモート更新（bastion に SSH 到達可能な場合）

> **実行場所**: オンライン環境（KVM ホスト等）の `ansible_training_2026/airgap/` ディレクトリ

```bash
# [KVM ホスト] ~/ansible_training_2026/airgap/
cd /path/to/ansible_training_2026/airgap
./update-airgap.sh 192.168.100.2 password
```

#### A-2: tar を USB 等で持ち込む（airgap 環境）

```bash
# ---- 1. tar 作成 ----
# [KVM ホスト] ~/ansible_training_2026/airgap/
cd /path/to/ansible_training_2026/airgap
./update-airgap.sh --create-tar
# → 親ディレクトリに ansible_training_2026_update.tar.gz が作成される
# → USB 等で bastion に持ち込む

# ---- 2. update-airgap.sh 自体を先に更新 ----
# [KVM ホスト → bastion] ※ bastion の旧スクリプトは --apply-tar を認識しないため
scp update-airgap.sh root@192.168.100.2:/opt/airgap/update-airgap.sh

# ---- 3. tar 適用 ----
# [bastion] /opt/airgap/
ssh root@192.168.100.2
cd /opt/airgap
./update-airgap.sh --apply-tar /path/to/ansible_training_2026_update.tar.gz

# ---- 3. training サーバーへ同期 ----
# [bastion] /opt/airgap/  （続けて実行）
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml --tags sync-code
```

### 方法 B: 手動で個別ファイルを配置

bastion と training サーバーそれぞれに、該当ファイルを手動で配置します。

#### bastion（/opt/airgap/）

> **実行場所**: bastion（192.168.100.2）に root で SSH 接続して実行

```bash
# [bastion] /opt/airgap/
ssh root@192.168.100.2

# 1. ansible.cfg — [privilege_escalation] セクションを削除
vi /opt/airgap/ansible.cfg
# 以下の行を削除:
#   [privilege_escalation]
#   become = True
#   become_method = sudo

# 2. inventory/hosts.yml — ansible_become: true の行を削除
vi /opt/airgap/inventory/hosts.yml
# 以下の行を削除:
#   ansible_become: true

# 3. playbooks/ — 変更のあった playbook・テンプレートを上書き
#    （KVM ホストから bastion に scp する場合）
#    [KVM ホスト] ~/ansible_training_2026/airgap/
scp playbooks/setup-trainees.yml       root@192.168.100.2:/opt/airgap/playbooks/
scp playbooks/destroy-my-env.yml       root@192.168.100.2:/opt/airgap/playbooks/
scp playbooks/templates/trainees-updated.yml.j2 root@192.168.100.2:/opt/airgap/playbooks/templates/

# 4. スクリプト — deploy-training.sh と manage-training.sh を配置
scp deploy-training.sh                 root@192.168.100.2:/opt/airgap/
scp manage-training.sh                 root@192.168.100.2:/opt/airgap/

# 5. update-airgap.sh
scp update-airgap.sh                   root@192.168.100.2:/opt/airgap/

# 6. trainees.yml — ヘッダーコメントのみ変更（既存データがあれば上書き注意）
#    ※ 既に受講者データが入っている場合はヘッダーだけ手動で書き換える

# 7. パーミッション修正
#    [bastion] /opt/airgap/
ssh root@192.168.100.2 'chmod +x /opt/airgap/*.sh'
```

#### training サーバーへの同期

> **実行場所**: bastion（192.168.100.2）の `/opt/airgap/` から実行

```bash
# [bastion] /opt/airgap/
# 方法 1: playbook で一括同期（推奨）
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml --tags sync-code

# 方法 2: 手動で個別 scp
for f in \
    playbooks/setup-trainees.yml \
    playbooks/destroy-my-env.yml \
    playbooks/templates/trainees-updated.yml.j2 \
    deploy-training.sh \
    manage-training.sh; do
  scp /opt/airgap/$f root@192.168.100.10:/opt/airgap/$f
done
ssh root@192.168.100.10 'chmod +x /opt/airgap/*.sh'
```

### 方法 C: ファイル差分の一括適用（最もシンプル）

```bash
# ---- 1. tar 作成 ----
# [KVM ホスト] ~/ansible_training_2026/
cd /path/to/ansible_training_2026
tar czf airgap-patch.tar.gz \
    airgap/ansible.cfg \
    airgap/deploy-training.sh \
    airgap/manage-training.sh \
    airgap/update-airgap.sh \
    airgap/playbooks/setup-trainees.yml \
    airgap/playbooks/destroy-my-env.yml \
    airgap/playbooks/templates/trainees-updated.yml.j2 \
    airgap/docs/deployment-guide.md
# → USB 等で bastion に持ち込む
# ※ inventory/hosts.yml と trainees.yml は環境固有データを含むため tar に入れない

# ---- 2. bastion で展開 ----
# [bastion] /opt/
ssh root@192.168.100.2
cd /opt
tar xzf /path/to/airgap-patch.tar.gz
chmod +x /opt/airgap/*.sh

# inventory/hosts.yml は手動で編集（ansible_become: true の行を削除）
vi /opt/airgap/inventory/hosts.yml

# ---- 3. training サーバーへ反映 ----
# [bastion] /opt/airgap/
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml --tags sync-code
```

## 適用後の確認

> **実行場所**: bastion（192.168.100.2）の `/opt/airgap/` で実行

```bash
# [bastion] /opt/airgap/
cd /opt/airgap

# 1. ansible.cfg に [privilege_escalation] がないこと
grep -c 'privilege_escalation' ansible.cfg
# → 0

# 2. inventory に ansible_become: true がないこと
grep -c 'ansible_become: true' inventory/hosts.yml
# → 0

# 3. 全 playbook が admin ユーザーで動作すること
ansible -i inventory/hosts.yml all -m ping

# 4. manage-training.sh が動作すること（training サーバー上で実行）
ssh root@192.168.100.10 'cd /opt/airgap && ./manage-training.sh health'

# 5. setup-trainees.yml が動作すること（冪等性確認）
ansible-playbook -i inventory/hosts.yml playbooks/setup-trainees.yml
```

## 破壊的変更

- **`credentials.csv`（統合版）は廃止**: `setup-trainees.yml` 実行時に既存の `credentials.csv` は自動削除されます。代わりに `credentials/<ユーザー名>.csv` が個別生成されます。
- **`ansible.cfg` の `[privilege_escalation]` セクション削除**: become は各 playbook の play レベルで `become: true` を明示する方針に変更。既にデプロイ済みの環境では `ansible.cfg` を手動で編集する必要があります。
- **`inventory/hosts.yml` の `ansible_become: true` 削除**: 同上。become の有効化は play レベルの `become: true` が担当します。
