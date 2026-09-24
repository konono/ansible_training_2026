# 構築ガイド — オフライン環境でのトレーニング環境セットアップ

Windows クライアント + Linux サーバー構成で、マルチユーザー対応の Ansible トレーニング環境を構築する手順書です。
1 台の Linux サーバーに複数人分の演習環境を構築し、各受講者が Windows 端末から SSH で接続して演習を行います。

## 構成図

```
[管理者 PC / USB]                [オフライン環境]
  │                               ├── bastion (RHEL 9) ← Ansible コントローラ
  │  airgap/ を持ち込み            │     └── ansible-playbook を実行
  └──────────────────────────────>├── repository (RHEL 9)
                                  │     └── DVD ISO + UBI 10 ミラー → nginx 配信
                                  ├── training (RHEL 9)
                                  │     ├── podman + コンテナイメージ (UBI 10)
                                  │     ├── /opt/airgap/ (スクリプト)
                                  │     ├── user1 環境 (port 2201)
                                  │     ├── user2 環境 (port 2202)
                                  │     └── ...
                                  └── Windows クライアント × N 台
                                        └── SSH で training に接続して演習
```

> **バージョン構成**: VM (bastion, repository, training) は RHEL 9 ベース。
> 演習用コンテナは UBI 10 ベースのため、演習ドキュメントの出力例はそのまま使えます。
> リポジトリサーバーは VM 用 (RHEL 9 DVD ISO) とコンテナ用 (UBI 10 ミラー) の両方を配信します。

## 前提条件

### 持ち込み資材の準備（オンライン環境で実施）

オフライン環境に持ち込む前に、インターネット接続のある Linux マシンでバンドルを作成します。

```bash
# 1. リポジトリをクローン
git clone https://github.com/konono/ansible_training_2026.git
cd ansible_training_2026/airgap

# 2. バンドル作成（コンテナイメージビルド + パッケージダウンロード）
./prepare-offline-bundle.sh

# 3. RHEL DVD ISO を入手して配置
#    Red Hat カスタマーポータル: https://access.redhat.com/downloads/content/rhel
#    ※ BaseOS + AppStream を含む DVD ISO（Boot ISO は不可）
#    ※ rhel-version.conf に設定したバージョンと一致する ISO を使用
mkdir -p offline-resources/iso/
cp /path/to/rhel-9.4-x86_64-dvd.iso offline-resources/iso/

# 4. バンドルの完全性を確認
./offline-validation.sh

# 5. airgap/ ディレクトリ全体を USB 等にコピー
cp -r ../airgap/ /mnt/usb/
```

> 詳細は [バンドル作成ガイド](bundle-preparation.md) を参照してください。

### 持ち込み資材の確認

`./offline-validation.sh` でバンドルの完全性を確認できます。

### マシン要件

| 役割 | OS | CPU | メモリ | ディスク | 台数 |
|---|---|---|---|---|---|
| bastion（コントローラ） | RHEL 9 | 2 vCPU | 4 GB | 40 GB | 1 |
| repository（リポジトリサーバー） | RHEL 9 | 2 vCPU | 2 GB | 30 GB | 1 |
| training（Linux 演習サーバー） | RHEL 9 | 下表参照 | 下表参照 | 下表参照 | 1 |
| Windows クライアント | Windows 10/11 | — | — | — | 受講者数 |

#### training サーバーのスペック（受講者数別）

| 受講者数 | コンテナ数 | CPU | メモリ | ディスク |
|---|---|---|---|---|
| 5 人 | 25 | 4 vCPU | 8 GB | 40 GB |
| 10 人 | 50 | 4 vCPU | 8 GB | 40 GB |
| 20 人 | 100 | 4 vCPU | 8 GB | 40 GB |
| 30 人 | 150 | 8 vCPU | 16 GB | 60 GB |
| 50 人 | 250 | 8 vCPU | 32 GB | 80 GB |

> **実測値**: 1 環境（5 コンテナ）あたりメモリ約 80MB、ディスク約 5MB。20 人（100 コンテナ）で実測メモリ 2.2GB。上表は OS + podman のベースライン (2-3GB) と演習時の一時的な負荷（nginx インストール等）を含めた推奨値です。
>
> **注意**: bastion と repository は同一マシンで兼用可能です（ディスク 40GB 以上を推奨）。

### ポート要件（セキュリティグループ）

| マシン | IN | OUT |
|---|---|---|
| bastion | 22/tcp（管理者 SSH） | 22/tcp（全マシンへ） |
| repository | 22/tcp（bastion から）, 80/tcp（training から） | — |
| training | 22/tcp（bastion + Windows から）, 2201-2299/tcp（受講者ごとの SSH） | 80/tcp（repository へ） |
| Windows | 22/tcp（bastion から）, 3389/tcp（RDP） | 22, 2201-2299/tcp（training へ） |

すべてのマシンが同一ネットワーク上にあること。インターネット接続は不要。

---

## 管理者の作業

### Step 1: bastion への資材転送

USB 等で持ち込んだ資材を bastion に転送・展開します。

**方法 A: オンライン環境から直接転送する場合**
```bash
# オンライン環境で実行
cd airgap/
./transfer-to-bastion.sh <bastion の IP> <パスワード>
```

**方法 B: USB から手動でコピーする場合**

USB に以下の 2 つが入っている想定です:
- `airgap/` ディレクトリ（Playbook・スクリプト・設定）— git リポジトリから取得
- `airgap-offline-resources.tar.gz`（バイナリ資材）— `prepare-offline-bundle.sh` で生成

```bash
# bastion 上で実行

# Playbook・スクリプトをコピー
cp -r /mnt/usb/airgap/ /opt/airgap/

# バイナリ資材を展開
cd /opt/airgap
tar xzf /mnt/usb/airgap-offline-resources.tar.gz

# DVD ISO が別ファイルの場合
mkdir -p offline-resources/iso
cp /mnt/usb/rhel-9.4-x86_64-dvd.iso offline-resources/iso/

# 資材の完全性を確認
./offline-validation.sh
```

### Step 2: bastion のセットアップ

bastion に SSH してコントローラをセットアップします。

```bash
ssh <user>@<bastion の IP>
cd /opt/airgap
./setup-controller.sh          # root または sudo 可能な一般ユーザーで実行
```

> root でも一般ユーザー（sudo 権限あり）でも実行できます。一般ユーザーの場合、特権操作は自動で `sudo` されます。
>
> ISO が `offline-resources/iso/` にあれば `rhel-version.conf` のバージョンに一致するものを自動検出します。別の場所にある場合は引数で指定: `./setup-controller.sh /path/to/rhel9.iso`

このスクリプトが自動で行うこと:
1. DVD ISO をマウントしてローカルリポジトリを設定
2. Python 3.12 のインストール（RHEL 9 の場合）
3. `gcc`, `make` 等の前提パッケージをインストール
4. `ansible-core` を pip パッケージからオフラインインストール
5. `sshpass` をソースからビルド
6. Ansible コレクションをインストール

### Step 3: インベントリの編集

デプロイ先環境の IP アドレス・ユーザー・パスワードに合わせて編集します。

```bash
vi /opt/airgap/inventory/hosts.yml
```

```yaml
all:
  vars:
    ansible_user: admin              # SSH 接続ユーザー（root または sudo 可能な一般ユーザー）
    ansible_password: password       # SSH パスワード
    ansible_become: true             # 特権昇格を有効化
    ansible_become_method: sudo
    ansible_become_password: "{{ ansible_password }}"  # sudo パスワード（SSH と同じ場合）
  children:
    repo_server:
      hosts:
        repo-server:
          ansible_host: <repository の IP>    # 例: 192.168.100.5
    rhel:
      hosts:
        rhel-target:
          ansible_host: <training の IP>      # 例: 192.168.100.10
```

> **注意**: `transfer-to-bastion.sh` で転送した場合、`inventory/hosts.yml` には開発環境のデフォルト値が入っています。環境に合わせて IP アドレスとパスワードを変更してください。
>
> **root で直接接続する場合**: `ansible_user: root` に変更すれば従来通り動作します。`ansible_become` の設定はそのままで問題ありません（root では become は自動的にスキップされます）。

### Step 4: Playbook の実行

各 Playbook を順番に実行します。初回は SSH ホストキーが未登録のため `-e` でホストキーチェックを無効化しています。

```bash
cd /opt/airgap
SSH_ARGS='-e ansible_ssh_common_args="-o StrictHostKeyChecking=no"'

# 1. リソース配置（DVD ISO, UBI 10 ミラー, コンテナイメージ等を各サーバーに配布）
ansible-playbook -i inventory/hosts.yml playbooks/distribute-resources.yml $SSH_ARGS

# 2. リポジトリサーバーの構築（RHEL 9 DVD ISO + UBI 10 ミラーの HTTP 配信）
ansible-playbook -i inventory/hosts.yml playbooks/repo-server-setup.yml $SSH_ARGS

# 3. Linux 演習サーバーの構築
#    - podman + docker-compose インストール
#    - Python 3.12 + ansible-core インストール（deploy-training.sh 用）
#    - コンテナイメージのロード
#    - スクリプト・Playbook の配置
#    - inotify 上限拡張（マルチユーザー対応）
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml $SSH_ARGS
```

> 各 Playbook は冪等なので、エラーが発生した場合は修正後に再実行できます。

### Step 5: 構築後の検証

bastion 上で以下を実行して、構築結果を検証します。

```bash
# リポジトリサーバーの確認（RHEL 9 + UBI 10）
echo -n "RHEL9 BaseOS: "; curl -s -o /dev/null -w '%{http_code}\n' http://<repository>/repo/BaseOS/repodata/repomd.xml
echo -n "RHEL9 AppStream: "; curl -s -o /dev/null -w '%{http_code}\n' http://<repository>/repo/AppStream/repodata/repomd.xml
echo -n "UBI10 BaseOS: "; curl -s -o /dev/null -w '%{http_code}\n' http://<repository>/ubi10/BaseOS/repodata/repomd.xml
echo -n "UBI10 AppStream: "; curl -s -o /dev/null -w '%{http_code}\n' http://<repository>/ubi10/AppStream/repodata/repomd.xml
# → 全て 200

# training サーバーにスクリプトが配置されているか
sshpass -p password ssh -o StrictHostKeyChecking=no root@<training> 'ls /opt/airgap/deploy-training.sh'

# テスト環境を 1 つ作ってみる
sshpass -p password ssh -o StrictHostKeyChecking=no root@<training> 'cd /opt/airgap && ./deploy-training.sh --test 1'

# テスト環境に接続して ansible と nginx インストールを確認
sshpass -p password ssh -o StrictHostKeyChecking=no -p 2201 root@<training> 'ansible --version | head -1'
sshpass -p password ssh -o StrictHostKeyChecking=no -p 2201 root@<training> 'dnf install -y nginx 2>&1 | tail -1'
# → "Complete!"

# テスト環境を全て削除
sshpass -p password ssh -o StrictHostKeyChecking=no root@<training> 'cd /opt/airgap && ./destroy-training.sh --test'
```

> bastion と各サーバー間に SSH 鍵を配置していない場合、`sshpass` を使ってパスワード認証で接続します。`setup-controller.sh` で `sshpass` は自動的にインストールされます。

### Step 5.5: 受講者ユーザーの作成

受講者ごとの Linux ユーザーを training サーバーに一括作成します。

```bash
# trainees.yml に受講者情報を記入
vi /opt/airgap/trainees.yml

# ユーザー作成を実行
ansible-playbook -i inventory/hosts.yml playbooks/setup-trainees.yml $SSH_ARGS

# credentials.csv を確認して受講者に配布
cat credentials.csv
```

`trainees.yml` の記入例:
```yaml
trainees:
  - username: yamada.taro@example.com
    display_name: 山田太郎
  - username: suzuki.hanako@example.com
  - username: tanaka
```

- `username` がメールアドレス形式の場合、`@` より前がログインユーザー名になります（例: `yamada.taro`）
- メールアドレス形式でない場合、そのままユーザー名として使用されます
- `display_name` は任意です（status 表示やラベルに使用）

Playbook 実行後、`trainees.yml` にパスワードが追記され、`credentials.csv` が生成されます。
`credentials.csv` を受講者に配布してください。

### Step 6: Windows クライアントの事前設定

各 Windows クライアント上で以下を実施してください（管理者 or 受講者が実施）。

#### OpenSSH Client の確認

PowerShell を管理者で開き:
```powershell
Get-WindowsCapability -Online -Name OpenSSH.Client* | Select-Object State
# "Installed" でなければ:
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

#### VSCode + Remote-SSH のインストール（オプション）

バンドル内のインストーラを使用:
```powershell
& "\\<bastion>\share\packages\VSCodeSetup-x64.exe" /VERYSILENT /NORESTART /MERGETASKS=addtopath
code --install-extension "\\<bastion>\share\packages\ms-vscode-remote.remote-ssh.vsix"
```

---

## 受講者の作業

### 演習環境の構築

**PowerShell を開いて以下を実行:**

```powershell
# 1. training サーバーに SSH 接続（credentials.csv に記載のユーザー名・パスワードを使用）
ssh <username>@<training の IP>
```
パスワード: credentials.csv で配布されたパスワード

```bash
# 2. 演習環境を構築（ログインユーザーで自動識別されます）
cd /opt/airgap
./deploy-training.sh
```

完了すると以下のように表示されます:
```
ユーザー: yamada.taro
受講者名: 山田太郎

========================================
演習環境の構築が完了しました！

接続方法:
  ssh -p 2201 root@192.168.1.10
  パスワード: password

コンテナ:
  user1_controller  Up 10 seconds  0.0.0.0:2201->22/tcp
  user1_node1       Up 10 seconds
  user1_node2       Up 10 seconds
  user1_node3       Up 10 seconds
  user1_lb          Up 10 seconds

演習用ネットワーク:
  controller: 172.20.1.10
  node1:      172.20.1.11
  node2:      172.20.1.12
  node3:      172.20.1.13
  lb:         172.20.1.14
========================================
```

### 演習環境への接続

**新しい PowerShell ウィンドウ**を開いて:

```powershell
ssh -o StrictHostKeyChecking=no -p <表示されたポート番号> root@<training の IP>
```
パスワード: `password`

**VSCode で接続する場合:**
1. `Ctrl+Shift+P` → `Remote-SSH: Connect to Host`
2. `root@<training の IP> -p <ポート番号>` と入力
3. パスワード: `password`

### 演習の開始

controller にログインしたら演習開始です:

```bash
# Ansible の確認
ansible --version

# 演習 1 の作業ディレクトリ
cd ~/basic-intro

# ansible.cfg を作成
cat > ansible.cfg << 'EOF'
[defaults]
inventory = inventory.yml
host_key_checking = False
EOF

# inventory.yml を作成（IP はデプロイ時の表示を参照）
cat > inventory.yml << 'EOF'
all:
  children:
    web:
      hosts:
        node1: {ansible_host: 172.20.<user_id>.11}
        node2: {ansible_host: 172.20.<user_id>.12}
    db:
      hosts:
        node3: {ansible_host: 172.20.<user_id>.13}
    lb:
      hosts:
        lb: {ansible_host: 172.20.<user_id>.14}
  vars:
    ansible_user: root
    ansible_password: password
EOF

# 接続テスト
ansible all -m ping
```

> `<user_id>` は `deploy-training.sh` の出力で確認できます。例: user_id=1 なら `172.20.1.11`

### 演習環境の管理

```bash
# training サーバーに SSH 接続して実行（受講者ユーザーでログイン）
ssh <username>@<training の IP>
cd /opt/airgap

# 環境の一覧表示
./deploy-training.sh status

# 自分の環境を削除（ログインユーザーで自動識別）
./deploy-training.sh destroy

# 再構築（同じ user_id で再利用される）
./deploy-training.sh
```

---

## トラブルシューティング

### `deploy-training.sh` で「root ユーザーでのセルフサービスデプロイはできません」

受講者ユーザーでログインしてから実行してください。root では演習環境のセルフサービスデプロイはできません。

```bash
# 正しい使い方: 受講者ユーザーでログインしてから実行
ssh yamada.taro@<training の IP>
cd /opt/airgap
./deploy-training.sh
```

> 管理者がテスト環境を作成する場合は `./deploy-training.sh --test N` を使用してください。

### SSH ポートに接続できない

```bash
# training サーバー上で確認
ss -tlnp | grep 22XX              # ポートが LISTENING か
podman ps | grep userXX            # コンテナが Up か
podman start userXX_controller     # 停止していたら起動
```

### コンテナが Exited (255) で起動しない

`inotify` の上限に達している可能性:
```bash
cat /proc/sys/fs/inotify/max_user_instances
# 128 以下なら不足:
echo 1024 > /proc/sys/fs/inotify/max_user_instances
# rhel-setup.yml を再実行すれば永続化される
```

### 演習で nginx がインストールできない

```bash
# controller 内で確認
dnf repolist
# airgap-baseos と airgap-appstream が表示されること
```

表示されない場合、リポジトリ設定に問題があります。`./deploy-training.sh destroy` → `./deploy-training.sh` で再構築してください。

### 割当状況の確認（管理者）

training サーバーで:
```bash
cd /opt/airgap
./deploy-training.sh status
```

### 全環境の一括リセット（管理者）

```bash
ssh root@<training>
podman stop -a; podman rm -af; podman network prune -f
rm -f /opt/training/allocations.json
rm -rf /opt/training/user*
```

---

## アップデート手順（既にデプロイ済みの環境）

IP ベースのユーザー識別からユーザーベースの識別にアップグレードする手順です。
既に稼働中の環境（IP ベースで作成済み）は影響を受けず、新規の払い出しからユーザーベースになります。

### 前提条件

- training サーバーに root で SSH 接続可能
- bastion（または作業端末）に改修版ファイルがある

### 持ち込むファイル

```
airgap-update/
├── deploy-training.sh                          # 改修版
├── destroy-training.sh                         # 念のため同梱
├── trainees.yml                                # 受講者リストテンプレート
├── scripts/
│   └── allocate.py                             # 改修版
└── playbooks/
    ├── setup-trainees.yml                      # 新規: ユーザー一括作成
    ├── deploy-my-env.yml                       # 改修版
    ├── destroy-my-env.yml                      # 改修版
    ├── templates/
    │   └── trainees-updated.yml.j2             # 新規: YAML 書き戻しテンプレート
    └── roles/
        ├── rhel_training/tasks/main.yml        # 改修版
        └── rhel_training_multi/tasks/main.yml  # 改修版
```

### Step 1: ファイルを training サーバーに転送

bastion で実行:

```bash
SSH_OPTS="-o StrictHostKeyChecking=no"

# スクリプト
scp $SSH_OPTS deploy-training.sh root@<training>:/opt/airgap/
scp $SSH_OPTS destroy-training.sh root@<training>:/opt/airgap/
scp $SSH_OPTS scripts/allocate.py root@<training>:/opt/airgap/scripts/

# Playbook・テンプレート
scp $SSH_OPTS playbooks/setup-trainees.yml root@<training>:/opt/airgap/playbooks/
scp $SSH_OPTS playbooks/deploy-my-env.yml root@<training>:/opt/airgap/playbooks/
scp $SSH_OPTS playbooks/destroy-my-env.yml root@<training>:/opt/airgap/playbooks/
ssh $SSH_OPTS root@<training> 'mkdir -p /opt/airgap/playbooks/templates'
scp $SSH_OPTS playbooks/templates/trainees-updated.yml.j2 root@<training>:/opt/airgap/playbooks/templates/

# ロール
scp $SSH_OPTS playbooks/roles/rhel_training/tasks/main.yml root@<training>:/opt/airgap/playbooks/roles/rhel_training/tasks/main.yml
scp $SSH_OPTS playbooks/roles/rhel_training_multi/tasks/main.yml root@<training>:/opt/airgap/playbooks/roles/rhel_training_multi/tasks/main.yml

# 受講者リストテンプレート
scp $SSH_OPTS trainees.yml root@<training>:/opt/airgap/
```

### Step 2: training サーバーで基盤更新

training サーバーに root で SSH 接続して実行:

```bash
ssh root@<training>
cd /opt/airgap

# training グループを作成
groupadd -f training

# allocations.json と .lock のパーミッションを修正
# （一般ユーザーが status コマンドで読み取れるようにする）
chmod 644 /opt/training/allocations.json 2>/dev/null || true
chmod 644 /opt/training/.lock 2>/dev/null || true

# MOTD を配置（受講者ログイン時のガイダンス）
cat > /etc/motd << 'EOF'
=== Ansible トレーニング環境 ===

演習環境の操作:
  cd /opt/airgap
  ./deploy-training.sh           環境を作成
  ./deploy-training.sh status    環境の状態を確認
  ./deploy-training.sh destroy   環境を削除（再作成可能）

問題が発生した場合は管理者にお問い合わせください。
EOF
```

### Step 3: 既存環境の互換性を確認

```bash
# training サーバーで実行
cd /opt/airgap
./deploy-training.sh status
# → 既存の IP ベース環境が USERNAME 列に IP アドレスとして表示されればOK
```

### Step 4: 受講者ユーザーを作成

```bash
# training サーバーで trainees.yml を編集
vi /opt/airgap/trainees.yml
```

記入例:
```yaml
trainees:
  - username: yamada.taro@example.com
    display_name: 山田太郎
  - username: suzuki.hanako@example.com
    display_name: 鈴木花子
  - username: tanaka
```

```bash
# ユーザー作成 Playbook を実行
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/setup-trainees.yml --connection local
```

> `--connection local` を指定すると、training サーバー上でローカル実行されます。

### Step 5: credentials.csv を確認して配布

```bash
# training サーバーで確認
cat /opt/airgap/credentials.csv

# bastion に取得する場合:
# bastion$ scp root@<training>:/opt/airgap/credentials.csv .
```

出力例:
```
username,password,display_name
yamada.taro,xK9mP2qR,山田太郎
suzuki.hanako,bN4wL7vT,鈴木花子
tanaka,mQ8jR3wZ,
```

受講者に以下を伝えてください:
- training サーバーの IP アドレス
- ログインユーザー名（credentials.csv の username 列）
- ログインパスワード（credentials.csv の password 列）

### Step 6: 動作確認

```bash
# 受講者ユーザーでログインできるか確認
ssh yamada.taro@<training>
# → MOTD が表示され、パスワードでログインできること

# 演習環境を作成
cd /opt/airgap
./deploy-training.sh
# → 「ユーザー: yamada.taro」と表示され、環境が構築されること

# status で確認
./deploy-training.sh status
# → USERNAME 列にユーザー名が表示されること

# 演習環境に接続
ssh -p <ポート番号> root@<training>
# → ansible --version が動作すること

# クリーンアップ（確認完了後）
cd /opt/airgap
./deploy-training.sh destroy
```

### 注意事項

- **既存環境との互換性**: IP ベースで作成済みの環境はそのまま稼働し続けます。status コマンドでは USERNAME 列に IP アドレスが表示されます
- **allocate.py のロック**: 書き込み操作（allocate/release/activate）は root で排他ロック、読み取り操作（status/lookup）は一般ユーザーで共有ロックを使用します
- **冪等性**: setup-trainees.yml は複数回実行しても安全です。既存ユーザーはスキップされ、パスワードが trainees.yml に記録済みの場合は再生成されません
- **受講者の追加**: trainees.yml にエントリを追加して setup-trainees.yml を再実行すれば、新しいユーザーだけが追加されます
