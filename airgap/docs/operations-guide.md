# Airgap Ansible 研修環境 運用手順書

| 項目 | 内容 |
|------|------|
| プロジェクト名 | Airgap 環境対応 Ansible 研修環境 |
| 対象OS | RHEL 10, Windows 11 |
| 最終更新 | 2026-08-18 |

---

## 目次

1. [事前準備チェックリスト](#1-事前準備チェックリスト)
2. [オフラインバンドルの作成手順](#2-オフラインバンドルの作成手順)
3. [KVM テスト環境の構築手順](#3-kvm-テスト環境の構築手順)
4. [RHEL 10 デプロイ手順](#4-rhel-10-デプロイ手順)
5. [Windows 11 デプロイ手順](#5-windows-11-デプロイ手順)
6. [デプロイ後の検証手順](#6-デプロイ後の検証手順)
7. [研修実施時の運用](#7-研修実施時の運用)
8. [メンテナンス手順](#8-メンテナンス手順)
9. [トラブルシューティング](#9-トラブルシューティング)
10. [FAQ](#10-faq)

---

## 1. 事前準備チェックリスト

### 1.1 オンライン環境 (バンドル作成マシン)

- [ ] OS: RHEL 10 / CentOS 10 または互換 OS がインストールされている
- [ ] インターネット接続が利用可能である
- [ ] `podman` がインストールされている (`podman --version` で確認)
- [ ] `python3` がインストールされている (`python3 --version` で確認)
- [ ] `pip` が利用可能である (`python3 -m pip --version` で確認)
- [ ] `git` がインストールされている (`git --version` で確認)
- [ ] `curl` がインストールされている (`curl --version` で確認)
- [ ] `ansible` がインストールされている (`ansible --version` で確認)
- [ ] `dnf` が利用可能である (RPM ダウンロードに必要)
- [ ] ディスク空き容量が 20GB 以上ある
- [ ] 研修資材リポジトリがクローン済みである

```bash
# 全前提条件の一括確認
for cmd in podman python3 git curl dnf ansible; do
    echo -n "$cmd: "
    command -v $cmd && $cmd --version 2>/dev/null | head -1 || echo "NOT FOUND"
done
echo "ディスク空き: $(df -h . | tail -1 | awk '{print $4}')"
```

### 1.2 エアギャップ RHEL 10 ターゲット

- [ ] RHEL 10 が最小インストール以上で導入されている
- [ ] CPU: 4 vCPU 以上
- [ ] メモリ: 4 GB 以上
- [ ] ディスク: 100 GB 以上の空き容量
- [ ] SSH が有効化されている (`systemctl status sshd`)
- [ ] ファイアウォールで SSH が許可されている
- [ ] root アカウントまたは sudo 可能なアカウントが利用可能

### 1.3 エアギャップ Windows 11 ターゲット

- [ ] Windows 11 Pro または Enterprise がインストールされている
- [ ] CPU: 4 vCPU 以上
- [ ] メモリ: 8 GB 以上
- [ ] ディスク: 120 GB 以上の空き容量
- [ ] BIOS/UEFI で仮想化支援 (VT-x / AMD-V) が有効
- [ ] 管理者権限のあるアカウントが利用可能
- [ ] WinRM は Playbook 実行前に有効化する (後述)

### 1.4 KVM ホスト (テスト環境用、オプション)

- [ ] Linux ホスト (bare-metal 推奨)
- [ ] CPU 仮想化支援 (VT-x / AMD-V) が有効
- [ ] ディスク: 250 GB 以上の空き容量 (VM ディスクイメージ用)
- [ ] メモリ: 16 GB 以上 (RHEL VM 4GB + Windows VM 8GB + ホスト分)
- [ ] RHEL 10 インストール ISO が用意されている
- [ ] Windows 11 インストール ISO が用意されている (オプション)

### 1.5 転送メディア

- [ ] USB ドライブ: 32 GB 以上 (バンドルサイズに依存)
- [ ] または: ISO 作成用のディスク空き容量

---

## 2. オフラインバンドルの作成手順

### 2.1 基本的な作成手順

```bash
# 1. リポジトリのディレクトリに移動
cd /path/to/ansible_training_2026/airgap/

# 2. バンドル作成スクリプトを実行
./prepare-offline-bundle.sh
```

スクリプトは以下の 7 フェーズを順次実行する。

| フェーズ | 処理内容 | 所要時間目安 |
|---------|---------|------------|
| Phase 1 | コンテナイメージのビルドと保存 | 5-15 分 |
| Phase 2 | RPM パッケージのダウンロード | 2-5 分 |
| Phase 3 | スタンドアロンバイナリのダウンロード | 1-3 分 |
| Phase 4 | pip パッケージのダウンロード | 1-3 分 |
| Phase 5 | Ansible コレクションのダウンロード | 1-2 分 |
| Phase 6 | 研修資材のアーカイブ | < 1 分 |
| Phase 7 | チェックサム生成 | < 1 分 |

### 2.2 Windows リソースをスキップする場合

Windows ターゲットが不要な場合、環境変数を設定してスキップできる。

```bash
SKIP_WINDOWS=true ./prepare-offline-bundle.sh
```

### 2.3 docker-compose バージョンの変更

```bash
COMPOSE_VERSION=v2.37.0 ./prepare-offline-bundle.sh
```

### 2.4 バンドル作成後の確認

```bash
# バンドルの内容とサイズを確認
du -sh offline-resources/*

# チェックサムファイルの確認
wc -l offline-resources/checksums.sha256

# コンテナイメージの確認
ls -lh offline-resources/container-images/

# RPM パッケージ数の確認
ls offline-resources/rpm-packages/podman/ | wc -l

# pip パッケージ数の確認
ls offline-resources/pip-packages/ | wc -l
```

### 2.5 バンドルの転送

#### USB ドライブ方式

```bash
# USB ドライブがマウントされていることを確認 (例: /mnt/usb)
lsblk

# airgap ディレクトリ全体をコピー
cp -r /path/to/ansible_training_2026/airgap/ /mnt/usb/

# コピー完了後にアンマウント
sync
umount /mnt/usb
```

#### ISO イメージ方式 (KVM VM 向け)

```bash
# offline-resources を ISO イメージ化
genisoimage -o /tmp/airgap-bundle.iso -R -J \
    /path/to/ansible_training_2026/airgap/offline-resources/

# ISO サイズの確認
ls -lh /tmp/airgap-bundle.iso
```

---

## 3. KVM テスト環境の構築手順

### 3.1 KVM ホストの準備

```bash
cd /path/to/ansible_training_2026/airgap/kvm/

# KVM/libvirt のインストールと隔離ネットワークの作成
./prepare-kvm-host.sh
```

このスクリプトが実行する内容:
1. `qemu-kvm`, `libvirt`, `virt-install`, `virt-viewer`, `libguestfs-tools`, `genisoimage` のインストール
2. `libvirtd` サービスの有効化と起動
3. `airgap-training` 隔離ネットワークの作成

### 3.2 隔離ネットワークの確認

```bash
# ネットワーク一覧の確認
sudo virsh net-list --all

# 期待される出力:
# 名前              状態     自動起動   永続
# -------------------------------------------------
# airgap-training   動作中   はい (yes)  はい (yes)

# ネットワーク詳細の確認
sudo virsh net-dumpxml airgap-training
```

### 3.3 RHEL 10 VM の作成

```bash
# 基本的な作成 (デフォルト設定: 4GB RAM, 4 vCPU, 100GB ディスク)
./create-rhel-vm.sh /path/to/rhel-10-x86_64-dvd.iso

# カスタム設定での作成
./create-rhel-vm.sh /path/to/rhel-10-x86_64-dvd.iso rhel10-training 8192 4 200
```

**OS インストール後の設定:**

```bash
# VNC コンソールの確認
sudo virsh vncdisplay rhel10-airgap-target

# VM 内で実行:
# 1. SSH の有効化
systemctl enable --now sshd

# 2. ファイアウォールで SSH を許可
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# 3. IP アドレスの確認
ip addr show
```

### 3.4 Windows 11 VM の作成

```bash
# 基本的な作成 (デフォルト設定: 8GB RAM, 4 vCPU, 120GB ディスク)
./create-windows-vm.sh /path/to/Win11_Japanese_x64.iso

# カスタム設定での作成
./create-windows-vm.sh /path/to/Win11_Japanese_x64.iso win11-training 16384 4 200
```

**OS インストール後の設定:**

VNC コンソール経由で Windows セットアップを完了し、管理者 PowerShell で WinRM を有効化する。

```powershell
# 管理者 PowerShell で実行
Set-ExecutionPolicy RemoteSigned -Force
.\enable-winrm.ps1
```

### 3.5 バンドルの VM への転送 (ISO 方式)

```bash
# ホスト側: ISO イメージを作成
genisoimage -o /tmp/airgap-bundle.iso -R -J \
    /path/to/ansible_training_2026/airgap/offline-resources/

# RHEL VM にアタッチ
sudo virsh attach-disk rhel10-airgap-target /tmp/airgap-bundle.iso sdb --type cdrom

# Windows VM にアタッチ
sudo virsh attach-disk win11-airgap-target /tmp/airgap-bundle.iso sdb --type cdrom
```

**RHEL VM 内での操作:**

```bash
mount /dev/sr0 /mnt
mkdir -p /opt/airgap-bundle
cp -r /mnt/* /opt/airgap-bundle/
umount /mnt
```

**Windows VM 内での操作:**

CD/DVD ドライブ (D: 等) の内容を `C:\airgap-bundle` にコピーする。

---

## 4. RHEL 10 デプロイ手順

### 4.1 インベントリの編集

```bash
cd /path/to/ansible_training_2026/airgap/
vi inventory/rhel-hosts.yml
```

ターゲット VM の IP アドレスに合わせて `ansible_host` を編集する。

```yaml
---
all:
  children:
    rhel:
      hosts:
        rhel-target:
          ansible_host: 192.168.100.10    # 実際の IP に変更
```

### 4.2 接続テスト

```bash
# SSH 接続の確認
ssh root@192.168.100.10

# Ansible 接続テスト
ansible -i inventory/rhel-hosts.yml rhel -m ping
```

### 4.3 バンドルの配置確認

ターゲット VM 上で以下を確認する。

```bash
# バンドルディレクトリの存在確認
ls /opt/airgap-bundle/

# 以下のディレクトリが存在すること:
# container-images/  rpm-packages/  pip-packages/
# binaries/  ansible-collections/  training-materials/
# checksums.sha256
```

### 4.4 Playbook の実行

```bash
# セットアップ Playbook を実行
ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml
```

**期待される出力 (最終メッセージ):**

```
========================================
研修環境のセットアップが完了しました！

コントローラへの接続:
  ssh -p 2220 root@localhost
  パスワード: password

研修コンテナ:
  controller: 172.20.0.10 (SSH port 2220)
  node1:      172.20.0.11
  node2:      172.20.0.12
  node3:      172.20.0.13
  lb:         172.20.0.14
========================================
```

### 4.5 検証 Playbook の実行

```bash
ansible-playbook -i inventory/rhel-hosts.yml playbooks/verify.yml
```

---

## 5. Windows 11 デプロイ手順

### 5.1 WinRM の事前設定

Windows ターゲットの管理者 PowerShell で以下を実行する。

```powershell
Set-ExecutionPolicy RemoteSigned -Force
.\enable-winrm.ps1
```

このスクリプトが実行する内容:
- WinRM サービスの有効化と起動
- WinRM リスナーの設定
- Basic 認証の有効化
- 暗号化なし通信の許可 (隔離ネットワーク内のため)
- ファイアウォールルールの追加 (5985/TCP)
- LocalAccountTokenFilterPolicy の設定

### 5.2 バンドルの配置

Windows ターゲット上で、バンドルの内容を `C:\airgap-bundle` にコピーする。

```
C:\airgap-bundle\
  +-- container-images\
  +-- pip-packages\
  +-- binaries\
  +-- ansible-collections\
  +-- training-materials\
  +-- checksums.sha256
```

### 5.3 インベントリの編集

```bash
vi inventory/windows-hosts.yml
```

```yaml
---
all:
  children:
    windows:
      hosts:
        win-target:
          ansible_host: 192.168.100.20    # 実際の IP に変更
```

### 5.4 接続テスト

```bash
# WinRM 接続テスト
ansible -i inventory/windows-hosts.yml windows -m ansible.windows.win_ping
```

### 5.5 Playbook の実行

```bash
ansible-playbook -i inventory/windows-hosts.yml playbooks/windows-setup.yml
```

**注意**: Windows デプロイでは WSL 機能の有効化や Podman インストール後に自動再起動が発生する場合がある。Playbook はこれを `win_reboot` モジュールで処理するが、再起動のタイムアウトは 600 秒 (10 分) に設定されている。

---

## 6. デプロイ後の検証手順

### 6.1 自動検証 (verify.yml)

```bash
# RHEL ターゲットの検証
ansible-playbook -i inventory/rhel-hosts.yml playbooks/verify.yml

# Windows ターゲットの検証
ansible-playbook -i inventory/windows-hosts.yml playbooks/verify.yml
```

### 6.2 手動検証チェックリスト

#### RHEL ターゲット

```bash
# ターゲット VM に SSH 接続して実行

# 1. podman の動作確認
podman --version
podman ps

# 2. 全コンテナが起動しているか (5台)
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 期待される出力:
# NAMES        STATUS          PORTS
# controller   Up X minutes    0.0.0.0:2220->22/tcp
# node1        Up X minutes
# node2        Up X minutes
# node3        Up X minutes
# lb           Up X minutes

# 3. コントローラへの SSH 接続
ssh -p 2220 root@localhost
# パスワード: password

# 4. コントローラ内で ansible バージョン確認
ansible --version

# 5. コントローラ内からノードへの疎通確認
ansible all -i inventory.ini -m ping
```

#### Windows ターゲット

```powershell
# Windows ターゲットの PowerShell で実行

# 1. Podman の動作確認
podman --version
podman ps

# 2. コンテナの起動確認
podman ps

# 3. SSH ポートの確認
Test-NetConnection -ComputerName localhost -Port 2220
```

### 6.3 研修受講者の接続テスト

外部 PC (または KVM ホスト) から以下で接続できることを確認する。

```bash
# RHEL ターゲットの場合
ssh -p 2220 root@192.168.100.10
# パスワード: password

# Windows ターゲットの場合
ssh -p 2220 root@192.168.100.20
# パスワード: password
```

---

## 7. 研修実施時の運用

### 7.1 研修開始前の確認

```bash
# ターゲット VM が起動しているか確認 (KVM の場合)
sudo virsh list --all

# コンテナが全て稼働しているか確認
ssh root@192.168.100.10 "podman ps"
```

### 7.2 受講者への案内事項

受講者に以下の情報を伝える。

| 項目 | 値 |
|------|-----|
| 接続先 | `ssh -p 2220 root@<ターゲットIP>` |
| ユーザ名 | `root` |
| パスワード | `password` |
| 研修資材の場所 | コンテナ内 `/root/basic-intro`, `/root/basic-roles`, `/root/advanced`, `/root/homework` |

### 7.3 研修中のモニタリング

```bash
# コンテナの状態を監視
watch -n 10 'ssh root@192.168.100.10 "podman ps"'

# コントローラのリソース使用状況
ssh root@192.168.100.10 "podman stats --no-stream"
```

### 7.4 コンテナの再起動 (問題発生時)

```bash
# 特定のコンテナを再起動
ssh root@192.168.100.10 "podman restart node1"

# 全コンテナを再起動
ssh root@192.168.100.10 "cd /opt/training/ansible_training_2026/containers && \
    DOCKER_HOST=unix:///run/podman/podman.sock docker-compose restart"

# 全コンテナを停止・再作成
ssh root@192.168.100.10 "cd /opt/training/ansible_training_2026/containers && \
    DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down && \
    DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d"
```

### 7.5 研修終了後のクリーンアップ

```bash
# コンテナを停止 (データは保持)
ssh root@192.168.100.10 "cd /opt/training/ansible_training_2026/containers && \
    DOCKER_HOST=unix:///run/podman/podman.sock docker-compose stop"

# コンテナとネットワークを完全削除
ssh root@192.168.100.10 "cd /opt/training/ansible_training_2026/containers && \
    DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down"

# コンテナイメージも含めて完全削除
ssh root@192.168.100.10 "podman system prune -af"

# KVM VM の停止 (テスト環境の場合)
sudo virsh shutdown rhel10-airgap-target
sudo virsh shutdown win11-airgap-target
```

---

## 8. メンテナンス手順

### 8.1 コンテナイメージの更新

研修内容の変更やセキュリティアップデートに伴いコンテナイメージを更新する場合の手順。

#### オンライン環境での作業

```bash
# 1. Containerfile を編集 (リポジトリルート)
vi containers/controller/Containerfile
vi containers/linux/Containerfile

# 2. イメージを再ビルド
podman build -t training-controller:latest \
    -f containers/controller/Containerfile containers/controller/
podman build -t training-linux-node:latest \
    -f containers/linux/Containerfile containers/linux/

# 3. 動作確認 (オプション)
podman run --rm -it training-controller:latest ansible --version

# 4. バンドルを再作成
./prepare-offline-bundle.sh
```

#### エアギャップ環境への反映

```bash
# 1. 更新されたバンドルを転送 (USB/ISO)
# 2. ターゲット VM 上で古いイメージを削除
podman rmi training-controller:latest training-linux-node:latest

# 3. 新しいイメージをロード
podman load -i /opt/airgap-bundle/container-images/training-controller.tar
podman load -i /opt/airgap-bundle/container-images/training-linux-node.tar

# 4. コンテナを再作成
cd /opt/training/ansible_training_2026/containers
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d
```

### 8.2 研修資材の更新

```bash
# オンライン環境で:
# 1. 研修資材を編集 (basic-intro/, basic-roles/, advanced/, homework/)
# 2. 変更をコミット
git add -A && git commit -m "研修資材を更新"

# 3. バンドルを再作成 (Phase 6 で git archive が実行される)
./prepare-offline-bundle.sh

# エアギャップ環境で:
# 4. 更新されたバンドルを転送
# 5. Playbook を再実行
ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml
```

### 8.3 RPM パッケージの追加

バンドルに含める RPM パッケージを追加する場合。

```bash
# オンライン環境で:
# 追加パッケージをダウンロード
dnf download --resolve \
    --destdir=offline-resources/rpm-packages/podman/ \
    <追加パッケージ名>

# チェックサムを再生成
cd offline-resources/
find . -type f ! -name 'checksums.sha256' -exec sha256sum {} \; > checksums.sha256
```

### 8.4 pip パッケージの追加

```bash
# オンライン環境で:
python3 -m pip download \
    -d offline-resources/pip-packages/ \
    <追加パッケージ名>

# チェックサムを再生成
cd offline-resources/
find . -type f ! -name 'checksums.sha256' -exec sha256sum {} \; > checksums.sha256
```

### 8.5 Ansible コレクションの追加

```bash
# オンライン環境で:
ansible-galaxy collection download <コレクション名> \
    -p offline-resources/ansible-collections/

# チェックサムを再生成
cd offline-resources/
find . -type f ! -name 'checksums.sha256' -exec sha256sum {} \; > checksums.sha256
```

### 8.6 docker-compose バージョンの更新

```bash
# オンライン環境で:
COMPOSE_VERSION=v2.37.0 ./prepare-offline-bundle.sh
# Phase 3 で指定バージョンがダウンロードされる
```

### 8.7 VM のスナップショット管理 (KVM テスト環境)

```bash
# デプロイ前のスナップショットを作成 (ロールバック用)
sudo virsh snapshot-create-as rhel10-airgap-target "pre-deploy" "デプロイ前の状態"

# スナップショット一覧の確認
sudo virsh snapshot-list rhel10-airgap-target

# スナップショットへのロールバック
sudo virsh snapshot-revert rhel10-airgap-target "pre-deploy"
```

---

## 9. トラブルシューティング

### 9.1 バンドル作成時の問題

#### podman build が失敗する

**症状**: Phase 1 のコンテナイメージビルドでエラーが発生する

**原因と対処**:

```bash
# DNS 解決の問題の場合
podman build --dns=8.8.8.8 -t training-controller:latest \
    -f containers/controller/Containerfile containers/controller/

# ストレージ不足の場合
podman system prune -af
df -h /var/lib/containers
```

#### dnf download が失敗する

**症状**: Phase 2 で RPM ダウンロードが失敗する

**原因と対処**:

```bash
# サブスクリプションの確認 (RHEL)
subscription-manager status

# リポジトリの確認
dnf repolist

# UBI 環境ではリポジトリが制限される場合がある
# その場合、完全な RHEL 10 環境で実行すること
```

#### pip download が失敗する

**症状**: Phase 4 で pip パッケージのダウンロードが失敗する

**原因と対処**:

```bash
# pip を最新に更新
python3 -m pip install --upgrade pip

# プロキシ環境の場合
python3 -m pip download \
    --proxy http://proxy:8080 \
    -d offline-resources/pip-packages/ \
    ansible pywinrm jmespath ansible-lint
```

### 9.2 デプロイ時の問題

#### チェックサム検証が失敗する

**症状**: common ロールでチェックサム検証エラーが表示される

**原因と対処**:

```bash
# ターゲット VM 上で手動確認
cd /opt/airgap-bundle/
sha256sum -c checksums.sha256

# 失敗したファイルを特定
sha256sum -c checksums.sha256 2>&1 | grep FAILED

# 対処: バンドルの転送をやり直す
# ISO 方式の場合、ISO の再作成・再マウント・再コピー
```

#### podman のインストールが失敗する

**症状**: rhel_podman ロールでエラーが発生する

**原因と対処**:

```bash
# RPM パッケージが正しく配置されているか確認
ls -la /opt/airgap-bundle/rpm-packages/podman/
ls -la /opt/airgap-bundle/rpm-packages/createrepo/

# createrepo_c が利用可能か確認
createrepo_c --version

# ローカルリポジトリのメタデータを手動で再生成
createrepo_c /opt/airgap-bundle/rpm-packages/podman/

# dnf キャッシュのクリア
dnf clean all

# ローカルリポジトリからのインストールを手動で試行
dnf install podman --disablerepo='*' --enablerepo=airgap-podman -y

# フォールバック: RPM 直接インストール
rpm -ivh --force --nodeps /opt/airgap-bundle/rpm-packages/podman/*.rpm
```

#### コンテナイメージのロードが失敗する

**症状**: rhel_training ロールでイメージロードエラーが発生する

**原因と対処**:

```bash
# tar ファイルの整合性確認
file /opt/airgap-bundle/container-images/training-controller.tar

# 手動でロードを試行
podman load -i /opt/airgap-bundle/container-images/training-controller.tar

# ストレージ不足の確認
df -h /var/lib/containers
podman system info | grep -A5 store

# ストレージが不足している場合
podman system prune -af
```

#### docker-compose up が失敗する

**症状**: コンテナ起動時にエラーが発生する

**原因と対処**:

```bash
# podman.socket が動作しているか確認
systemctl status podman.socket

# 動作していない場合
systemctl enable --now podman.socket

# docker-compose の実行を手動で試行
cd /opt/training/ansible_training_2026/containers/
DOCKER_HOST=unix:///run/podman/podman.sock /usr/local/bin/docker-compose up -d

# ログの確認
DOCKER_HOST=unix:///run/podman/podman.sock /usr/local/bin/docker-compose logs

# ネットワーク競合の確認
podman network ls
podman network rm ansible_net 2>/dev/null  # 既存ネットワークを削除してリトライ
```

### 9.3 コンテナ動作の問題

#### コンテナが起動しない

```bash
# 全コンテナの状態確認
podman ps -a

# 停止したコンテナのログ確認
podman logs controller
podman logs node1

# コンテナの再作成
cd /opt/training/ansible_training_2026/containers/
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d
```

#### SSH ポート 2220 に接続できない

```bash
# ポートリスニングの確認
ss -tlnp | grep 2220

# コンテナのポートマッピング確認
podman port controller

# コンテナ内の sshd 状態確認
podman exec controller systemctl status sshd

# コンテナ内の sshd を再起動
podman exec controller systemctl restart sshd
```

#### controller から node への ansible ping が失敗する

```bash
# コントローラ内の SSH 接続テスト
podman exec controller sshpass -p password \
    ssh -o StrictHostKeyChecking=no root@172.20.0.11 hostname

# ネットワーク疎通の確認
podman exec controller ping -c 3 172.20.0.11

# ノードの sshd 状態確認
podman exec node1 systemctl status sshd

# ノードの sshd を再起動
podman exec node1 systemctl restart sshd
```

### 9.4 Windows 固有の問題

#### WinRM 接続が失敗する

```bash
# Ansible 側からの確認
ansible -i inventory/windows-hosts.yml windows -m ansible.windows.win_ping -vvv

# Windows 側での確認 (PowerShell)
# WinRM サービスの状態
Get-Service WinRM

# WinRM リスナーの確認
winrm enumerate winrm/config/listener

# ファイアウォールルールの確認
Get-NetFirewallRule -DisplayName "*WinRM*" | Select-Object Enabled, Direction, Action
```

#### WSL/Podman の初期化が失敗する

```powershell
# WSL の状態確認
wsl --status

# WSL の再インストール
wsl --install --no-distribution

# Podman machine の状態確認
podman machine list

# Podman machine のリセット
podman machine rm -f
podman machine init
podman machine start
```

### 9.5 KVM 固有の問題

#### VM が起動しない

```bash
# VM の状態確認
sudo virsh list --all

# VM のログ確認
sudo virsh console rhel10-airgap-target

# VM のエラー詳細
sudo virsh dominfo rhel10-airgap-target

# VM の削除と再作成
sudo virsh destroy rhel10-airgap-target
sudo virsh undefine rhel10-airgap-target --remove-all-storage
./create-rhel-vm.sh /path/to/rhel10.iso
```

#### 隔離ネットワークに問題がある

```bash
# ネットワーク状態の確認
sudo virsh net-info airgap-training

# ネットワークの再起動
sudo virsh net-destroy airgap-training
sudo virsh net-start airgap-training

# ブリッジインターフェースの確認
ip link show virbr-airgap
brctl show virbr-airgap 2>/dev/null || bridge link show dev virbr-airgap

# DHCP リースの確認
sudo virsh net-dhcp-leases airgap-training
```

#### ISO のアタッチが失敗する

```bash
# 既存の CD-ROM デバイスの確認
sudo virsh domblklist rhel10-airgap-target

# 既存ディスクのデタッチ
sudo virsh detach-disk rhel10-airgap-target sdb

# 再アタッチ
sudo virsh attach-disk rhel10-airgap-target /tmp/airgap-bundle.iso sdb --type cdrom
```

---

## 10. FAQ

### Q1: バンドル全体のサイズはどのくらいになりますか?

**A**: 構成により異なるが、概算は以下の通り。

| 構成要素 | 概算サイズ |
|---------|----------|
| コンテナイメージ (controller + node) | 1-3 GB |
| Windows コンテナイメージ (オプション) | 3-6 GB |
| RPM パッケージ (podman + 依存) | 100-500 MB |
| pip パッケージ | 50-200 MB |
| docker-compose バイナリ | 50-100 MB |
| Ansible コレクション | 10-30 MB |
| 研修資材 | 10-50 MB |
| **合計 (Windows なし)** | **約 2-4 GB** |
| **合計 (Windows あり)** | **約 5-10 GB** |

### Q2: 複数の受講者が同時に使えますか?

**A**: 本構成は 1 ターゲット VM = 1 受講者環境を前提としている。複数受講者に対応するには、受講者数分の VM を作成するか、1 台の VM 上で異なるポートでコンテナセットを複数起動する方式をカスタマイズする必要がある。

### Q3: RHEL 10 以外の Linux ディストリビューションで使えますか?

**A**: `prepare-offline-bundle.sh` は `dnf` コマンドに依存するため、バンドル作成は RHEL/CentOS/Fedora 系のディストリビューションで行う必要がある。ターゲットについても RPM パッケージの互換性から RHEL 10 系を推奨する。ただし、ターゲットに既に podman がインストールされている場合は、RPM インストールのステップをスキップして動作する可能性がある。

### Q4: Windows で SKIP_WINDOWS=true にした場合、後から Windows サポートを追加できますか?

**A**: 可能である。`SKIP_WINDOWS=false` (デフォルト) で `prepare-offline-bundle.sh` を再実行すれば、Windows 関連リソースが追加される。既存のリソースは上書きされる。

### Q5: コンテナイメージの Containerfile はどこにありますか?

**A**: リポジトリルートの以下の場所にある。

- コントローラ: `containers/controller/Containerfile`
- Linux ノード: `containers/linux/Containerfile`

これらは `airgap/` ディレクトリの外、リポジトリルートに配置されている。`prepare-offline-bundle.sh` は `REPO_ROOT` 変数 (スクリプトの親ディレクトリ) を参照してビルドする。

### Q6: 既にデプロイ済みの環境を再デプロイできますか?

**A**: 可能である。Playbook は冪等性を考慮して設計されている。

- podman が既にインストールされている場合、インストールステップはスキップされる
- docker-compose.yml は `backup: true` で配置されるため、既存ファイルはバックアップされる
- コンテナイメージは `podman load` で上書きロードされる
- `docker-compose up -d` は既存コンテナがあれば再作成する

ただし、完全にクリーンな状態から再デプロイしたい場合は、事前に以下を実行する。

```bash
cd /opt/training/ansible_training_2026/containers
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down
podman system prune -af
```

### Q7: enable-winrm.ps1 でセキュリティ上の懸念はありますか?

**A**: `enable-winrm.ps1` は Basic 認証と暗号化なし通信を有効化するため、ネットワーク上で認証情報が平文で送信される。これはエアギャップの隔離ネットワーク内でのみ使用する前提であり、以下の条件が全て満たされる場合にのみ許容される。

- ネットワークが完全に隔離されている (forward なし)
- 研修目的の一時的な環境である
- 研修終了後に環境を破棄する

外部ネットワークに接続された環境では、HTTPS (5986) + NTLM/Kerberos 認証の使用を強く推奨する。

### Q8: docker-compose の代わりに podman-compose は使えますか?

**A**: 本システムでは `docker-compose` (Docker 公式のスタンドアロンバイナリ) を使用している。`podman-compose` は pip パッケージとして追加可能だが、以下の理由から `docker-compose` を採用している。

- `docker-compose` はスタンドアロンバイナリとして配布されており、Python 環境への依存がない
- `podman.socket` を `DOCKER_HOST` 環境変数で指定することで、podman をバックエンドとして透過的に使用できる
- docker-compose.yml の構文互換性が高い

### Q9: 研修中に受講者がコンテナを壊してしまった場合は?

**A**: 以下の手順で復旧できる。

```bash
# 特定のコンテナのみ再作成
podman rm -f node1
cd /opt/training/ansible_training_2026/containers
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d node1

# 全環境をリセット
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d
```

controller コンテナの workspace ディレクトリはホスト側にマウントされているため、コンテナを再作成しても受講者の作業ファイルは保持される。

### Q10: verify.yml で「起動中のコンテナが5未満です」と表示される場合は?

**A**: 以下を確認する。

```bash
# 1. 全コンテナの状態を確認 (停止中のものも含む)
podman ps -a

# 2. 停止しているコンテナがあればログを確認
podman logs <コンテナ名>

# 3. 停止しているコンテナを手動で起動
podman start <コンテナ名>

# 4. それでも起動しない場合は再作成
cd /opt/training/ansible_training_2026/containers
DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d

# 5. リソース不足の可能性
free -h          # メモリ
df -h            # ディスク
podman system info
```
