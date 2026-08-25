# 構築ガイド — お客様環境での研修環境セットアップ

Windows クライアント + Linux サーバー構成で、マルチユーザー対応の Ansible 研修環境を構築する手順書です。
1 台の Linux サーバーに複数人分の演習環境を構築し、各受講者が Windows 端末から SSH で接続して演習を行います。

## 構成図

```
[管理者 PC / USB]                [お客様 airgap 環境]
  │                               ├── bastion (RHEL 10) ← Ansible コントローラ
  │  airgap/ を持ち込み            │     └── ansible-playbook を実行
  └──────────────────────────────>├── repository (RHEL 10)
                                  │     └── DVD ISO → nginx HTTP 配信
                                  ├── training (RHEL 10)
                                  │     ├── podman + コンテナイメージ
                                  │     ├── /opt/airgap/ (スクリプト)
                                  │     ├── user1 環境 (port 2201)
                                  │     ├── user2 環境 (port 2202)
                                  │     └── ...
                                  └── Windows クライアント × N 台
                                        └── SSH で training に接続して演習
```

## 前提条件

### 持ち込み資材の準備（オンライン環境で実施）

お客様環境に持ち込む前に、インターネット接続のある RHEL 10 マシンでバンドルを作成します。

```bash
# 1. リポジトリをクローン
git clone https://github.com/konono/ansible_training_2026.git
cd ansible_training_2026/airgap

# 2. バンドル作成（コンテナイメージビルド + パッケージダウンロード）
./prepare-offline-bundle.sh

# 3. RHEL 10 DVD ISO を入手して配置
#    Red Hat カスタマーポータル: https://access.redhat.com/downloads/content/rhel
#    ※ BaseOS + AppStream を含む DVD ISO（Boot ISO は不可）
mkdir -p offline-resources/iso/
cp /path/to/rhel-10.2-x86_64-dvd.iso offline-resources/iso/

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
| bastion（コントローラ） | RHEL 10 | 2 vCPU | 4 GB | 40 GB | 1 |
| repository（リポジトリサーバー） | RHEL 10 | 2 vCPU | 2 GB | 30 GB | 1 |
| training（Linux 演習サーバー） | RHEL 10 | 下表参照 | 下表参照 | 下表参照 | 1 |
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

すべてのマシンが同一ネットワーク上にあること。インターネット接続は不要（airgap）。

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
cp /mnt/usb/rhel-10.2-x86_64-dvd.iso offline-resources/iso/

# 資材の完全性を確認
./offline-validation.sh
```

### Step 2: bastion のセットアップ

bastion に SSH してコントローラをセットアップします。

```bash
ssh root@<bastion の IP>
cd /opt/airgap
./setup-controller.sh
```

> ISO が `offline-resources/iso/` にあれば自動検出します。別の場所にある場合は引数で指定: `./setup-controller.sh /path/to/rhel10.iso`

このスクリプトが自動で行うこと:
1. DVD ISO をマウントしてローカルリポジトリを設定
2. `gcc`, `make`, `python3-pip` 等の前提パッケージをインストール
3. `ansible-core` を pip パッケージからオフラインインストール
4. `sshpass` をソースからビルド
5. Ansible コレクションをインストール

### Step 3: インベントリの編集

お客様環境の IP アドレスとパスワードに合わせて編集します。

```bash
vi /opt/airgap/inventory/hosts.yml
```

```yaml
all:
  vars:
    ansible_user: root
    ansible_password: <Linux の root パスワード>
  children:
    repo_server:
      hosts:
        repo-server:
          ansible_host: <repository の IP>
    rhel:
      hosts:
        rhel-target:
          ansible_host: <training の IP>
```

### Step 4: Playbook の実行

```bash
cd /opt/airgap

# 1. リソース配置（DVD ISO, コンテナイメージ等を各サーバーに配布）
ansible-playbook -i inventory/hosts.yml playbooks/distribute-resources.yml

# 2. リポジトリサーバーの構築
ansible-playbook -i inventory/hosts.yml playbooks/repo-server-setup.yml

# 3. Linux 演習サーバーの構築
#    - podman + docker-compose インストール
#    - ansible-core インストール（deploy-training.sh 用）
#    - コンテナイメージのロード
#    - スクリプト・Playbook の配置
#    - inotify 上限拡張（マルチユーザー対応）
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml
```

### Step 5: 構築後の検証

```bash
# リポジトリサーバーの確認
curl -s -o /dev/null -w '%{http_code}' http://<repository>/repo/BaseOS/repodata/repomd.xml
# → 200

# training サーバーにスクリプトが配置されているか
ssh root@<training> 'ls /opt/airgap/deploy-training.sh'

# テスト環境を 1 つ作ってみる
ssh root@<training> 'cd /opt/airgap && ./deploy-training.sh --test 1'
# → ssh -p 2201 root@<training> で接続確認

# テスト環境を全て削除
ssh root@<training> 'cd /opt/airgap && ./destroy-training.sh --test'
```

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
# 1. training サーバーに SSH 接続
ssh root@<training の IP>
```
パスワード: `<管理者に確認>`

```bash
# 2. 演習環境を構築（IP は SSH 接続元から自動取得されます）
cd /opt/airgap
./deploy-training.sh
```

完了すると以下のように表示されます:
```
接続元 IP: 192.168.1.31
========================================
演習環境の構築が完了しました！

接続方法:
  ssh -p 2201 root@192.168.1.10
  パスワード: password
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

### 演習環境の削除・再構築

```bash
# training サーバーに SSH 接続して実行
ssh root@<training の IP>
cd /opt/airgap
./destroy-training.sh      # 環境削除
./deploy-training.sh       # 再構築（同じ user_id で再利用されます）
```

---

## トラブルシューティング

### `deploy-training.sh` で「接続元 IP を特定できません」

SSH 経由でログインしてから実行してください。直接ログインした場合は `--ip` で手動指定:
```bash
./deploy-training.sh --ip 192.168.1.31 --name 山田太郎
```

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

表示されない場合、リポジトリ設定に問題があります。`./destroy-training.sh` → `./deploy-training.sh` で再構築してください。

### 割当状況の確認（管理者）

bastion で:
```bash
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/training-status.yml --limit rhel-target
```

または training サーバーで直接:
```bash
python3 /opt/airgap/scripts/allocate.py --action status | python3 -m json.tool
```

### 全環境の一括リセット（管理者）

```bash
ssh root@<training>
podman stop -a; podman rm -af; podman network prune -f
rm -f /opt/training/allocations.json
rm -rf /opt/training/user*
```
