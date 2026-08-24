# 構築ガイド — お客様環境での研修環境セットアップ

Windows クライアント + Linux サーバー構成で、マルチユーザー対応の Ansible 研修環境を構築する手順書です。
1 台の Linux サーバーに複数人分の演習環境を構築し、各受講者が Windows 端末から SSH で接続して演習を行います。

## 構成図

```
[管理者PC]                       [お客様 airgap 環境]
  │                               ├── リポジトリサーバー (RHEL 10)
  │  USB 等で airgap/ を持ち込み   │     └── DVD ISO → nginx HTTP 配信
  └──────────────────────────────>├── Linux 演習サーバー (RHEL 10)
                                  │     ├── podman + コンテナイメージ
                                  │     ├── /opt/airgap/ (Playbook・スクリプト)
                                  │     ├── user1 環境 (port 2201)
                                  │     ├── user2 環境 (port 2202)
                                  │     └── ...
                                  └── Windows クライアント × N 台
                                        └── SSH で Linux に接続して演習
```

## 前提条件

### 持ち込み資材

`airgap/` ディレクトリ一式（USB 等で転送済み）。`./offline-validation.sh` でバンドルの完全性を確認できます。

### マシン要件

| 役割 | OS | CPU | メモリ | ディスク | 台数 |
|---|---|---|---|---|---|
| リポジトリサーバー | RHEL 10 | 2+ | 2GB+ | 20GB+ (ISO 11GB) | 1 |
| Linux 演習サーバー | RHEL 10 | 4+ | 受講者数 × 1GB + 4GB | 40GB+ | 1 |
| Windows クライアント | Windows 10/11 | - | - | - | 受講者数 |

> **メモリ目安**: 1 環境（5 コンテナ）あたり約 100MB。10 人なら約 5GB で十分。

すべてのマシンが同一ネットワーク上にあり、SSH で相互接続可能であること。

---

## 管理者の作業

### Step 1: コントローラのセットアップ

リポジトリサーバーまたは Linux 演習サーバーを Ansible コントローラとして使います。

```bash
# USB から airgap/ を Linux サーバーにコピー
cp -r /mnt/usb/airgap/ /opt/airgap/

# DVD ISO をコピー
cp /mnt/usb/airgap/offline-resources/iso/rhel-10.2-x86_64-dvd.iso /opt/rhel10.iso

# コントローラセットアップ（ansible-core + コレクション + sshpass をオフラインインストール）
cd /opt/airgap
./setup-controller.sh /opt/rhel10.iso
```

### Step 2: インベントリの編集

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
          ansible_host: <リポジトリサーバーの IP>
    rhel:
      hosts:
        rhel-target:
          ansible_host: <Linux 演習サーバーの IP>
```

### Step 3: リソースの配置

```bash
cd /opt/airgap

# DVD ISO → リポジトリサーバー
scp offline-resources/iso/rhel-10.2-x86_64-dvd.iso root@<repo-server>:/opt/rhel10.iso

# Windows パッケージ → リポジトリサーバー
ssh root@<repo-server> 'mkdir -p /opt/airgap-bundle/packages'
scp -r offline-resources/packages/ root@<repo-server>:/opt/airgap-bundle/packages/

# バンドル → Linux 演習サーバー
ssh root@<rhel-target> 'mkdir -p /opt/airgap-bundle/{container-images,binaries,training-materials,pip-packages}'

scp offline-resources/container-images/training-controller.tar \
    offline-resources/container-images/training-linux-node.tar \
    root@<rhel-target>:/opt/airgap-bundle/container-images/

scp offline-resources/binaries/docker-compose-linux-x86_64 \
    root@<rhel-target>:/opt/airgap-bundle/binaries/

scp offline-resources/training-materials/ansible_training_2026.tar.gz \
    root@<rhel-target>:/opt/airgap-bundle/training-materials/

scp -r offline-resources/pip-packages/ \
    root@<rhel-target>:/opt/airgap-bundle/pip-packages/
```

### Step 4: Playbook の実行

```bash
cd /opt/airgap

# 1. リポジトリサーバーの構築
ansible-playbook -i inventory/hosts.yml playbooks/repo-server-setup.yml

# 2. Linux 演習サーバーの構築
#    - podman + docker-compose のインストール
#    - コンテナイメージのロード
#    - deploy-training.sh 等のスクリプト配置
#    - inotify 上限拡張（マルチユーザー対応）
ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml
```

### Step 5: 構築後の検証

```bash
# リポジトリサーバー
curl -s -o /dev/null -w '%{http_code}' http://<repo-server>/repo/BaseOS/repodata/repomd.xml
# → 200

# Linux 演習サーバーにスクリプトが配置されているか
ssh root@<rhel-target> 'ls /opt/airgap/deploy-training.sh'

# 割当状況の確認
ansible-playbook -i inventory/hosts.yml playbooks/training-status.yml --limit rhel-target
```

### Step 6: Windows クライアントの事前設定

各 Windows クライアント上で以下を実施してください（管理者 or 受講者が実施）。

#### OpenSSH Client の確認

PowerShell を管理者で開き:
```powershell
# OpenSSH Client が有効か確認
Get-WindowsCapability -Online -Name OpenSSH.Client* | Select-Object State
# "Installed" でなければ:
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

#### VSCode + Remote-SSH のインストール（オプション）

バンドル内のインストーラを使用:
```powershell
# VSCode
& "C:\airgap-bundle\VSCodeSetup-x64.exe" /VERYSILENT /NORESTART /MERGETASKS=addtopath

# Remote-SSH 拡張
code --install-extension "C:\airgap-bundle\ms-vscode-remote.remote-ssh.vsix"
```

---

## 受講者の作業

### 演習環境の構築

**PowerShell を開いて以下を実行:**

```powershell
# 1. Linux 演習サーバーに SSH 接続
ssh root@<Linux 演習サーバーの IP>
```
パスワード: `<管理者に確認>`

```bash
# 2. 演習環境を構築（IP は自動取得されます）
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
ssh -o StrictHostKeyChecking=no -p 2201 root@<Linux 演習サーバーの IP>
```
パスワード: `password`

（ポート番号は `deploy-training.sh` の出力に表示された番号を使用）

**VSCode で接続する場合:**
1. `Ctrl+Shift+P` → `Remote-SSH: Connect to Host`
2. `root@<IP> -p 2201` と入力
3. パスワード: `password`

### 演習の開始

controller にログインしたら演習開始です:

```bash
# Ansible の確認
ansible --version

# 作業ディレクトリへ移動
cd ~/basic-intro

# インベントリ作成（演習 1 の内容）
# ※ ノードの IP アドレスは各自の環境に合わせて設定
#    deploy-training.sh の出力で表示された subnet を確認
```

### 演習環境の削除・再構築

```bash
# Linux 演習サーバーに SSH 接続して実行
ssh root@<Linux 演習サーバーの IP>
cd /opt/airgap
./destroy-training.sh      # 環境削除
./deploy-training.sh       # 再構築（同じ user_id が再利用されます）
```

---

## トラブルシューティング

### `deploy-training.sh` でエラーが出る

```
エラー: 接続元 IP を特定できません。
```
→ SSH 経由でログインしてから実行してください。または `--ip` で手動指定:
```bash
./deploy-training.sh --ip 192.168.1.31
```

### SSH ポートに接続できない

```bash
# Linux 演習サーバー上で確認
ss -tlnp | grep 22XX              # ポートが LISTENING か
podman ps | grep userXX            # コンテナが Up か
podman start userXX_controller     # 停止していたら起動
```

### コンテナが Exited (255) で起動しない

`inotify` の上限に達している可能性:
```bash
cat /proc/sys/fs/inotify/max_user_instances
# 128 以下なら不足。以下で拡張:
echo 1024 > /proc/sys/fs/inotify/max_user_instances
# rhel-setup.yml を再実行すれば永続化される
```

### 演習で nginx がインストールできない

```bash
# controller 内で確認
podman exec userXX_node1 dnf repolist
# airgap-baseos と airgap-appstream が表示されること
```

### 割当状況の確認（管理者）

```bash
cd /opt/airgap
ansible-playbook -i inventory/hosts.yml playbooks/training-status.yml --limit rhel-target
```

### 全環境の一括リセット（管理者）

```bash
ssh root@<rhel-target>
podman stop -a; podman rm -af; podman network prune -f
rm -f /opt/training/allocations.json
rm -rf /opt/training/user*
```
