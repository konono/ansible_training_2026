# 構築ガイド — お客様環境での研修環境セットアップ

airgap 環境に Ansible 研修環境を構築する手順書です。

## 前提条件

### 持ち込み資材

- `airgap/` ディレクトリ一式（USB 等で転送済み）
- `offline-resources/` 内に以下が含まれていること（`./offline-validation.sh` で確認可能）:
  - `iso/rhel-10.2-x86_64-dvd.iso` — リポジトリサーバー配置用 **かつ** コントローラセットアップ用
  - `container-images/`, `binaries/`, `packages/`, `pip-packages/`, `ansible-collections/`, `training-materials/`

> **注意**: `vm-images/` は開発テスト用です。お客様環境では VM を VMware, Hyper-V, 物理マシン等で個別に用意してください。

### マシン要件

| 役割 | OS | CPU | メモリ | ディスク |
|---|---|---|---|---|
| Ansible コントローラ | RHEL 10 | 2+ | 4GB+ | 20GB+（DVD ISO 一時使用） |
| リポジトリサーバー | RHEL 10 | 2+ | 2GB+ | 20GB+（ISO 11GB 含む）|
| RHEL 研修ターゲット | RHEL 10 | 4+ | 4GB+ | 20GB+ |
| Windows 研修ターゲット（オプション）| Windows 11 Pro | 4+ | 8GB+ | 40GB+ |

すべてのマシンが同一ネットワーク上にあり、SSH で接続可能であること。

## Step 0: コントローラノードのセットアップ

Ansible を実行するコントローラノード自体も airgap 環境のため、オフラインでセットアップします。
DVD ISO をコントローラにコピーし、`setup-controller.sh` を実行してください。

```bash
# DVD ISO をコントローラにコピー（USB ドライブ等から）
cp /mnt/usb/airgap/offline-resources/iso/rhel-10.2-x86_64-dvd.iso /opt/rhel10.iso

# セットアップ実行（root 権限が必要）
cd /path/to/airgap/
./setup-controller.sh /opt/rhel10.iso
```

このスクリプトが自動で行うこと:
1. DVD ISO をマウントしてローカルリポジトリを設定
2. `gcc`, `make`, `python3-pip` 等の前提パッケージをインストール
3. `ansible-core` を pip パッケージからオフラインインストール
4. `sshpass` をソースからビルド
5. Ansible コレクション（`ansible.posix`, `ansible.windows` 等）をインストール

## Step 1: インベントリの編集

`inventory/hosts.yml`（統合インベントリ）をお客様環境に合わせて編集します。

```bash
cd airgap/
vi inventory/hosts.yml
```

```yaml
all:
  vars:
    ansible_user: root
    ansible_password: <RHEL の root パスワード>
  children:
    repo_server:
      hosts:
        repo-server:
          ansible_host: <リポジトリサーバーの IP>
    rhel:
      hosts:
        rhel-target:
          ansible_host: <RHEL ターゲットの IP>
    # Windows を使う場合はコメントを外す
    # windows:
    #   hosts:
    #     win-target:
    #       ansible_host: <Windows の IP>
    #       ansible_user: <Windows ユーザー名>
    #       ansible_password: "<Windows パスワード>"
```

## Step 2: リソースの配置

### リポジトリサーバー

DVD ISO をリポジトリサーバーの `/opt/rhel10.iso` に配置します。
Windows パッケージ（7-Zip MSI, Chocolatey nupkg）がある場合は `/opt/airgap-bundle/packages/` に配置します。

```bash
scp offline-resources/iso/rhel-10.2-x86_64-dvd.iso root@<repo-server>:/opt/rhel10.iso
scp -r offline-resources/packages/ root@<repo-server>:/opt/airgap-bundle/packages/
```

### RHEL ターゲット

```bash
ssh root@<rhel-target> 'mkdir -p /opt/airgap-bundle/{container-images,binaries,training-materials}'

scp offline-resources/container-images/training-controller.tar \
    offline-resources/container-images/training-linux-node.tar \
    root@<rhel-target>:/opt/airgap-bundle/container-images/

scp offline-resources/binaries/docker-compose-linux-x86_64 \
    root@<rhel-target>:/opt/airgap-bundle/binaries/

scp offline-resources/training-materials/ansible_training_2026.tar.gz \
    root@<rhel-target>:/opt/airgap-bundle/training-materials/
```

### Windows ターゲット（オプション）

Windows へのファイル転送は Ansible 経由で行います。バイナリは `C:\airgap-bundle\` 直下に配置してください（`binaries/` サブディレクトリではない）。

```bash
for f in wsl.msi podman-setup.exe docker-compose-windows-x86_64.exe podman-machine-wsl.ociarchive; do
  ansible -i inventory/windows-hosts.yml windows -m ansible.windows.win_copy \
    -a "src=offline-resources/binaries/$f dest=C:/airgap-bundle/$f"
done

# コンテナイメージ
ansible -i inventory/windows-hosts.yml windows -m ansible.windows.win_file \
  -a "path=C:\\airgap-bundle\\container-images state=directory"
for f in training-controller.tar training-linux-node.tar; do
  ansible -i inventory/windows-hosts.yml windows -m ansible.windows.win_copy \
    -a "src=offline-resources/container-images/$f dest=C:/airgap-bundle/container-images/$f"
done

# 研修資材
ansible -i inventory/windows-hosts.yml windows -m ansible.windows.win_file \
  -a "path=C:\\airgap-bundle\\training-materials state=directory"
ansible -i inventory/windows-hosts.yml windows -m ansible.windows.win_copy \
  -a "src=offline-resources/training-materials/ansible_training_2026.tar.gz dest=C:/airgap-bundle/training-materials/ansible_training_2026.tar.gz"
```

## Step 3: Windows SSH 事前設定（Windows ターゲットのみ）

Windows ターゲット上で PowerShell のデフォルトシェル設定を行います。
OpenSSH Server が起動していない場合は有効化してください。

```powershell
# 管理者 PowerShell で実行
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# SSH デフォルトシェルを PowerShell に変更
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -PropertyType String -Force
```

## Step 4: Playbook の実行

### RHEL 環境

```bash
cd airgap/

# 1. リポジトリサーバーの構築
ansible-playbook -i inventory/rhel-hosts.yml playbooks/repo-server-setup.yml

# 2. 研修環境の構築
ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml
```

### Windows 環境

```bash
ansible-playbook -i inventory/windows-hosts.yml playbooks/windows-setup.yml
```

### 一括実行

```bash
# site.yml は全 Playbook を順番に実行する
ansible-playbook -i inventory/rhel-hosts.yml playbooks/site.yml
```

## Step 5: 構築後の検証

### リポジトリサーバー

```bash
# BaseOS / AppStream が HTTP で配信されているか確認
curl -s -o /dev/null -w '%{http_code}' http://<repo-server>/repo/BaseOS/repodata/repomd.xml
# → 200

# Windows パッケージ
curl -s -o /dev/null -w '%{http_code}' http://<repo-server>/packages/7z2301-x64.msi
# → 200
```

### RHEL 研修環境

```bash
ansible-playbook -i inventory/rhel-hosts.yml playbooks/verify.yml
```

手動確認:

```bash
# ターゲット VM 上
podman ps                              # 5 台のコンテナが Up
ss -tlnp | grep 2220                   # SSH ポートが LISTENING

# controller 内
ssh -p 2220 root@localhost             # パスワード: password
ansible --version                      # ansible [core 2.21.x]
```

### Windows 研修環境

```bash
# コンテナ確認
ansible -i inventory/windows-hosts.yml windows -m raw -a 'podman --remote ps'
```

## Step 6: 研修受講者への案内

| 項目 | 値 |
|---|---|
| 接続コマンド | `ssh -p 2220 root@<ターゲットIP>` |
| ユーザー名 | `root` |
| パスワード | `password` |
| 演習資料の場所 | `/root/basic-intro`, `/root/basic-roles`, `/root/advanced` |

## トラブルシューティング

### コンテナが起動しない

```bash
podman ps -a                             # 全コンテナの状態確認
podman logs controller                   # ログ確認
```

### SSH ポート 2220 に接続できない

```bash
podman port controller                   # ポートマッピング確認
podman exec controller systemctl status sshd
```

### 演習で nginx がインストールできない

研修コンテナ内のリポジトリ設定を確認します。

```bash
podman exec node1 dnf repolist
# airgap-baseos と airgap-appstream が表示されること
# ubi-10-* が表示される場合は UBI リポジトリが無効化されていない
```

### Windows の Playbook が途中で止まる

- `podman machine start` は初回起動に数分かかる場合があります
- コンテナイメージのロードも大容量のため時間がかかります
- タイムアウトが発生した場合は再実行してください（冪等性あり）

### 研修環境のリセット

```bash
# RHEL: コンテナを再作成
ssh root@<rhel-target>
cd /opt/training/ansible_training_2026/containers
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d

# Windows: コンテナを再作成
# Ansible から実行
ansible -i inventory/windows-hosts.yml windows -m raw \
  -a 'podman --remote stop -a; podman --remote rm -af'
ansible-playbook -i inventory/windows-hosts.yml playbooks/windows-setup.yml
```

受講者の作業ファイル（`workspace/` ディレクトリ）はホスト側にマウントされているため、コンテナ再作成後も保持されます。
