# アップグレードガイド — デプロイ済み環境の資材更新

デプロイ済みの airgap トレーニング環境に対して、Ansible playbook・スクリプト・ドキュメントを更新する手順です。
パッケージ、コンテナイメージ、ISO 等のバイナリ資材は対象外です（変更がある場合は [構築ガイド](deployment-guide.md) を参照）。

## 概要

```
[オンライン環境]                  [オフライン環境]
                                  bastion (/opt/airgap/)
  git pull                         │  update-airgap.sh
  tar で .tar 作成                  │    ├── bastion 自身を更新
  ──────── USB 等で持ち込み ──────> │    └── ansible-playbook --tags sync-code
                                   │         └── training サーバーも自動更新
                                   │
                                   training (/opt/airgap/)
                                     └── スクリプト・playbook が同期される
```

## 更新されるもの / されないもの

| 対象 | 更新される | 備考 |
|---|---|---|
| playbooks/ (roles 含む) | o | |
| scripts/allocate.py | o | |
| deploy-training.sh, destroy-training.sh | o | |
| ansible.cfg | o | |
| docs/ | o | |
| group_vars/ | o | |
| inventory/hosts.yml | x | 環境固有の IP・パスワードを含むため上書きしない |
| trainees.yml | x | 受講者データを含むため上書きしない |
| rhel-version.conf | x | バックアップから自動復元 |
| credentials.csv | x | 保持 |
| allocations.json | x | 保持（/opt/training/ 配下） |
| offline-resources/ | x | 対象外 |
| コンテナイメージ | x | 対象外 |

## 手順

### Step 1: アップデート用 .tar を作成（オンライン環境）

最新のリポジトリから、バイナリ資材を除いた軽量アーカイブを作成します。

```bash
cd ansible_training_2026/

tar cf ansible_training_2026_update.tar \
  --exclude='.git' \
  --exclude='.tracecraft' \
  --exclude='.claude' \
  --exclude='.ansible' \
  --exclude='*.tar.gz' \
  --exclude='*.tar' \
  --exclude='airgap/offline-resources' \
  --exclude='airgap/kvm/vms/*.qcow2' \
  --exclude='airgap/kvm/vms/win11' \
  .

ls -lh ansible_training_2026_update.tar
# → 約 1MB 以下（バイナリ資材を含まないため軽量）
```

### Step 2: bastion に持ち込む

USB メモリ等で bastion にファイルを持ち込み、展開します。

```bash
# bastion で実行
mkdir -p /tmp/airgap-update && cd /tmp/airgap-update
tar xf /path/to/ansible_training_2026_update.tar
```

### Step 3: update-airgap.sh を実行

```bash
cd /tmp/airgap-update/airgap
./update-airgap.sh
```

スクリプトは以下を自動で行います:

1. `/opt/airgap/` の存在を確認（なければ初回デプロイを案内）
2. 現行の設定ファイルをバックアップ (`/opt/airgap/.backup_<timestamp>/`)
3. 新しいファイルを展開して置き換え（`inventory/`, `trainees.yml`, `credentials.csv` は上書きしない）
4. `rhel-version.conf` をバックアップから復元
5. パーミッションを修正
6. 必須ファイルの存在を検証
7. **training サーバーへ `--tags sync-code` で自動同期**

### 実行例

```
============================================
  Airgap 資材アップデート
============================================
  モード: local
  ソース: /tmp/airgap-update/airgap/

[INFO] Step 1: 転送先の状態を確認
[INFO] offline-resources/ を検出 — 保持します

[INFO] Step 2: アップデート用アーカイブ作成（パッケージ・ISO・VM 除外）
[INFO] アーカイブサイズ: 68K

[INFO] Step 3: 現行ファイルのバックアップ
[INFO] バックアップ先: /opt/airgap/.backup_20260924_103000/

[INFO] Step 4: 転送と展開
[INFO] 展開完了

[INFO] Step 5: 環境固有ファイルの保持を確認
  保持: inventory/hosts.yml
  保持: trainees.yml
[INFO] rhel-version.conf をバックアップから復元しました

[INFO] Step 6: パーミッション修正
[INFO] パーミッション設定完了

[INFO] Step 7: アップデート結果を検証
[INFO] 検証OK: 全ファイルが正しく配置されています

[INFO] Step 8: training サーバーへのコード同期
[INFO] training サーバーへの同期が完了しました
============================================
  アップデート完了
============================================
```

### Step 4: inventory/hosts.yml の差分確認（警告が出た場合のみ）

`inventory/hosts.yml` がアップデートで変更された場合、スクリプトが警告を出します。
新しいテンプレートに追加された設定項目と、環境固有の IP アドレス等をマージしてください。

```bash
# bastion で実行
diff /opt/airgap/.backup_<timestamp>/inventory/hosts.yml /opt/airgap/inventory/hosts.yml

# 環境固有の設定を復元する場合:
cp /opt/airgap/.backup_<timestamp>/inventory/hosts.yml /opt/airgap/inventory/hosts.yml
```

### Step 5: 動作確認

```bash
# bastion で実行
cd /opt/airgap
./deploy-training.sh status
# → 既存の受講者環境が表示されること

# training サーバーでも確認
ssh <user>@<training の IP>
cd /opt/airgap
./deploy-training.sh status
```

## リモートから bastion を更新する場合

bastion に SSH 接続可能な環境（例: 持ち込み PC）からリモートで実行することもできます。

```bash
cd /tmp/airgap-update/airgap
./update-airgap.sh <bastion の IP> [パスワード]

# 例:
./update-airgap.sh 192.168.100.2 password
```

> `sshpass` が必要です。パスワード省略時のデフォルトは `password`。

## ロールバック

問題があった場合はバックアップから復元できます。

```bash
# bastion で実行
BACKUP_DIR=$(ls -td /opt/airgap/.backup_* | head -1)
cp -a "$BACKUP_DIR"/* /opt/airgap/

# training サーバーにも反映
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml --tags sync-code
```

## training サーバーへの手動同期

`update-airgap.sh` の Step 8 が失敗した場合（ansible-playbook 未インストール等）は、
bastion で以下を手動実行してください。

```bash
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml \
    --tags sync-code \
    -e 'ansible_ssh_common_args="-o StrictHostKeyChecking=no"'
```

`--tags sync-code` はスクリプト・playbook・設定ファイルの同期のみを行います。
コンテナイメージのロードや ansible-core のインストール等の重い処理は実行されません。

## 注意事項

- **受講者の環境は影響を受けません** — 稼働中のコンテナ環境、allocations.json、credentials.csv はアップデートの対象外です
- **offline-resources/ は上書きされません** — パッケージやコンテナイメージの更新が必要な場合は、手動で差し替えてください
- **バックアップは自動削除されません** — ディスク容量が気になる場合は古い `.backup_*` を手動で削除してください
- **inventory/hosts.yml に新しい設定項目が追加された場合** — 既存の hosts.yml を復元するだけでは新機能が有効にならないことがあります。diff を確認して必要な設定を追記してください
