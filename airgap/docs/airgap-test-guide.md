# Airgap 環境テストガイド

本番のエアギャップ環境を正確に再現してテストするための手順書。
VM はインターネットに一切到達できない隔離ネットワーク上に構築し、オンラインフォールバックが発生しないことを保証する。

## 前提条件

- KVM 対応の Linux ホスト（bare-metal、`/dev/kvm` 有り）
- `offline-resources/` バンドル一式（以下を含む）:
  - `iso/rhel-10.2-x86_64-dvd.iso` — RHEL 10 DVD ISO
  - `vm-images/rhel-10.2-x86_64-kvm.qcow2` — RHEL 10 KVM ゲストイメージ
  - `vm-images/windows-11-25h2.qcow2` — Windows 11 qcow2（Windows テスト時のみ）
  - `container-images/`, `binaries/`, `pip-packages/`, `ansible-collections/`, `training-materials/`

## ネットワーク設計

```
airgap-training (192.168.100.0/24, <forward>なし = 完全隔離)
├── 192.168.100.1   KVM ホスト（DHCP, Ansible コントローラ）
├── 192.168.100.5   リポジトリサーバー VM
├── 192.168.100.10  RHEL ターゲット VM
└── 192.168.100.20  Windows ターゲット VM（オプション）
```

KVM ホストは隔離ネットワークのゲートウェイ（192.168.100.1）だが、`<forward>` 要素がないため VM からインターネットへのルーティングは存在しない。

## Step 1: KVM ホストの準備

```bash
cd airgap/kvm/
./prepare-kvm-host.sh
```

隔離ネットワークが作成されたことを確認:

```bash
sudo virsh net-info airgap-training
# Forward mode: なし（隔離）
```

## Step 2: VM イメージの準備

KVM ゲストイメージから 2 台の VM を作成する。

```bash
VM_DIR=airgap/kvm/vms

# リポジトリサーバー用
BUNDLE=airgap/offline-resources

cp $BUNDLE/vm-images/rhel-10.2-x86_64-kvm.qcow2 /tmp/repo-server.qcow2
sudo virt-customize -a /tmp/repo-server.qcow2 \
  --root-password password:password \
  --hostname repo-server \
  --run-command 'sed -i "s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --selinux-relabel
qemu-img resize /tmp/repo-server.qcow2 20G
mv /tmp/repo-server.qcow2 $VM_DIR/repo-server.qcow2

# RHEL ターゲット用（podman を事前削除して未インストール状態にする）
cp $BUNDLE/vm-images/rhel-10.2-x86_64-kvm.qcow2 /tmp/rhel-target.qcow2
sudo virt-customize -a /tmp/rhel-target.qcow2 \
  --root-password password:password \
  --hostname rhel-target \
  --run-command 'sed -i "s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --run-command 'dnf remove -y podman 2>/dev/null; true' \
  --selinux-relabel
qemu-img resize /tmp/rhel-target.qcow2 20G
mv /tmp/rhel-target.qcow2 $VM_DIR/rhel-target.qcow2
```

## Step 3: VM を隔離ネットワーク上で起動

libvirt の `airgap-training` ネットワークを使って VM を起動する。
**`-netdev user` は使わない**（ユーザーモードネットワークは QEMU 内蔵の NAT ゲートウェイを持ち、ホスト経由で外部通信できてしまう）。

### リポジトリサーバー

```bash
sudo virt-install \
  --name repo-server \
  --import \
  --disk path=$VM_DIR/repo-server.qcow2,format=qcow2 \
  --memory 2048 --vcpus 2 \
  --os-variant rhel10.0 \
  --network network=airgap-training,mac=52:54:00:AA:BB:05 \
  --graphics none --console pty,target.type=serial \
  --noautoconsole
```

### RHEL ターゲット

```bash
sudo virt-install \
  --name rhel-target \
  --import \
  --disk path=$VM_DIR/rhel-target.qcow2,format=qcow2 \
  --memory 4096 --vcpus 2 \
  --os-variant rhel10.0 \
  --network network=airgap-training,mac=52:54:00:AA:BB:10 \
  --graphics none --console pty,target.type=serial \
  --noautoconsole
```

### IP アドレスの確認

`create-airgap-network.xml` の DHCP 予約により固定 IP が割り当てられる。
予約にない MAC アドレスを使った場合は以下で確認:

```bash
sudo virsh domifaddr repo-server
sudo virsh domifaddr rhel-target
```

### airgap 状態の検証（必須）

**テスト前に必ず実施する。** これを省略すると、オンラインフォールバックが気づかず成功してしまう。

```bash
# repo-server
ssh root@192.168.100.5 'ping -c 1 -W 3 8.8.8.8 2>&1 || echo "AIRGAP OK: no internet"'

# rhel-target
ssh root@192.168.100.10 'ping -c 1 -W 3 8.8.8.8 2>&1 || echo "AIRGAP OK: no internet"'
```

期待する出力: `Network is unreachable` または `AIRGAP OK: no internet`

## Step 4: DVD ISO とバンドルの転送

VM にインターネット接続がないため、ファイルは KVM ホストから転送する。

### DVD ISO → リポジトリサーバー

KVM ホストはゲートウェイ (192.168.100.1) として VM と通信できる。

```bash
# リポジトリサーバーのパーティション拡張（KVM ゲストイメージは元が小さい）
ssh root@192.168.100.5 'TMPDIR=/dev/shm growpart /dev/vda 3 && xfs_growfs /'

# DVD ISO を転送
scp $BUNDLE/iso/rhel-10.2-x86_64-dvd.iso root@192.168.100.5:/opt/rhel10.iso
```

### バンドルリソース → RHEL ターゲット

```bash
BUNDLE=airgap/offline-resources

# パーティション拡張
ssh root@192.168.100.10 'TMPDIR=/dev/shm growpart /dev/vda 3 && xfs_growfs /'

# ステージングディレクトリ作成
ssh root@192.168.100.10 'mkdir -p /opt/airgap-bundle/{container-images,binaries,training-materials}'

# 転送
scp $BUNDLE/container-images/training-controller.tar \
    $BUNDLE/container-images/training-linux-node.tar \
    root@192.168.100.10:/opt/airgap-bundle/container-images/

scp $BUNDLE/binaries/docker-compose-linux-x86_64 \
    root@192.168.100.10:/opt/airgap-bundle/binaries/

scp $BUNDLE/training-materials/ansible_training_2026.tar.gz \
    root@192.168.100.10:/opt/airgap-bundle/training-materials/
```

### バンドルリソース → Windows ターゲット

Windows VM へは Ansible (WinRM) 経由で転送する。
`group_vars/windows.yml` の変数が `C:\airgap-bundle\` 直下を期待するため、
`binaries/` サブディレクトリではなく **直下に配置** する。

```bash
# Windows インベントリを作成（inventory/windows-hosts.yml に合わせる）
# ansible を使って転送
cd airgap/

# バイナリ（win_bundle_dir 直下に配置）
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

## Step 5: create-airgap-network.xml の更新

リポジトリサーバー用の DHCP 予約を追加する（まだない場合）。

```xml
<host mac="52:54:00:AA:BB:05" name="repo-server" ip="192.168.100.5"/>
```

## Step 6: インベントリの設定

```yaml
# inventory/rhel-hosts.yml
---
all:
  children:
    repo_server:
      hosts:
        repo-server:
          ansible_host: 192.168.100.5
    rhel:
      hosts:
        rhel-target:
          ansible_host: 192.168.100.10
```

## Step 7: Ansible Playbook の実行

KVM ホストから実行する（ホストは 192.168.100.1 として隔離ネットワークにいる）。

```bash
cd airgap/

# Phase 1: リポジトリサーバー構築
ansible-playbook -i inventory/rhel-hosts.yml playbooks/repo-server-setup.yml

# Phase 2: 研修環境構築
ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml
```

## Step 8: 検証

### リポジトリサーバーの確認

```bash
# KVM ホストから
curl -s -o /dev/null -w '%{http_code}' http://192.168.100.5/repo/BaseOS/repodata/repomd.xml
# 期待: 200

# RHEL ターゲットから（airgap 内通信の確認）
ssh root@192.168.100.10 \
  'curl -s -o /dev/null -w "%{http_code}" http://192.168.100.5/repo/BaseOS/repodata/repomd.xml'
# 期待: 200
```

### 研修環境の確認

```bash
ansible-playbook -i inventory/rhel-hosts.yml playbooks/verify.yml
```

確認項目:
- podman がインストールされている
- docker-compose が配置されている
- コンテナ 5 台 (controller, node1-3, lb) が起動している
- controller から各ノードに SSH 接続できる
- controller 内で ansible --version が動作する

### airgap 違反の検出

RHEL ターゲットのリポジトリ設定がローカルサーバーのみを指していることを確認:

```bash
ssh root@192.168.100.10 'dnf repolist'
```

期待する出力:
```
repo id       repo name
BaseOS        RHEL BaseOS via local nginx
AppStream     RHEL AppStream via local nginx
```

CDN リポジトリ（`rhel-10-for-x86_64-*`）が表示されてはならない。

## テスト完了後のクリーンアップ

```bash
sudo virsh destroy repo-server
sudo virsh destroy rhel-target
sudo virsh undefine repo-server --remove-all-storage
sudo virsh undefine rhel-target --remove-all-storage
```

---

## 既知の問題と対策

### 1. `podman machine init` のオンラインフォールバック（Windows）

**問題**: `win_podman` ロールには、バンドル済み machine イメージがない場合に `podman machine init`（引数なし）を実行するオンラインフォールバックがある。airgap 環境ではこのフォールバックは必ず失敗する。

**対策**: `prepare-offline-bundle.sh` で `podman-machine-wsl.ociarchive` を確実にダウンロードする。`skopeo copy` には `--override-arch x86_64 --override-os linux` が必要（OCI マニフェストのアーキテクチャ名不一致対策）。

### 2. KVM ゲストイメージのディスクサイズ

**問題**: Red Hat 提供の KVM ゲストイメージはデフォルトで 10GB 未満のパーティションを持つ。DVD ISO (11GB) の転送でディスクフルになる。

**対策**: `qemu-img resize` でイメージを拡張した後、VM 内で `growpart` + `xfs_growfs` を実行する。`growpart` 自体がテンポラリ領域を必要とするため、ディスクフル状態では `TMPDIR=/dev/shm growpart ...` とする。

### 3. `-netdev user` の使用禁止

**問題**: QEMU の `-netdev user` はホスト経由でインターネットに到達可能な NAT ゲートウェイ (10.0.2.2) を提供する。この環境でテストすると、airgap 環境では失敗するはずのオンラインフォールバックが成功してしまう。

**対策**: VM は必ず libvirt の `airgap-training` ネットワーク（`<forward>` なし）上で起動する。`virt-install --network network=airgap-training` を使用し、`-netdev user` は使わない。
