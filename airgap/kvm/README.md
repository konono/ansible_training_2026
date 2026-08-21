# KVM テスト環境構築ガイド

エアギャップ環境でのデプロイをテストするための KVM VM 構築手順です。

## 前提条件

- KVM 対応の Linux ホスト（bare-metal推奨）
- CPU仮想化支援（VT-x / AMD-V）が有効
- RHEL 10 インストール ISO
- Windows 11 インストール ISO（オプション）

## 手順

### 1. KVM ホストの準備

```bash
./prepare-kvm-host.sh
```

このスクリプトは以下を実行します:
- qemu-kvm, libvirt, virt-install のインストール
- libvirtd の有効化
- `airgap-training` 隔離ネットワークの作成

### 2. 隔離ネットワークについて

`create-airgap-network.xml` で定義されるネットワークには `<forward>` 要素がありません。
これにより、VM はインターネットに一切アクセスできない完全隔離環境となります。

```
192.168.100.0/24（隔離ネットワーク）
├── 192.168.100.1   - KVM ホスト（DHCP サーバ）
├── 192.168.100.10  - RHEL 10 ターゲット VM
└── 192.168.100.20  - Windows 11 ターゲット VM
```

### 3. RHEL 10 VM の作成

```bash
./create-rhel-vm.sh /path/to/rhel-10-x86_64-dvd.iso
```

VNC コンソールで OS インストールを完了後:
1. SSH を有効化
2. ファイアウォールで SSH を許可
3. バンドルを転送

### 4. Windows 11 VM の作成

```bash
./create-windows-vm.sh /path/to/Win11_Japanese_x64.iso
```

Windows 11 は TPM 2.0 が必要なため、`swtpm` によるエミュレーションを使用します。

### 5. バンドルの転送方法

VM にインターネット接続がないため、以下の方法でバンドルを転送します:

#### ISO 方式（推奨）

```bash
# ホスト側でバンドルを ISO イメージ化
genisoimage -o /tmp/airgap-bundle.iso -R -J /path/to/airgap/offline-resources/

# VM にアタッチ
sudo virsh attach-disk rhel10-airgap-target /tmp/airgap-bundle.iso sdb --type cdrom

# VM 内でマウント・コピー
mount /dev/sr0 /mnt
mkdir -p /opt/airgap-bundle
cp -r /mnt/* /opt/airgap-bundle/
umount /mnt
```

#### virtio-fs / 9p 共有（KVM ホストとの直接共有）

```bash
# VM 作成時に共有ディレクトリを追加
virt-install ... --filesystem source=/path/to/offline-resources,target=bundle,driver.type=virtiofs
```

### 6. Ansible Playbook の実行

KVM ホストから（またはAnsibleコントローラから）:

```bash
cd /path/to/airgap/
ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml
ansible-playbook -i inventory/rhel-hosts.yml playbooks/verify.yml
```
