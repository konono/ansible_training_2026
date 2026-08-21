#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== KVM ホスト準備スクリプト ==="
echo ""

# KVM/libvirt のインストール
echo "[1/4] KVM/libvirt パッケージをインストール中..."
sudo dnf install -y \
    qemu-kvm \
    libvirt \
    virt-install \
    virt-viewer \
    libguestfs-tools \
    genisoimage

# libvirtd の有効化
echo "[2/4] libvirtd を有効化・起動中..."
sudo systemctl enable --now libvirtd

# 隔離ネットワークの作成
echo "[3/4] airgap 隔離ネットワークを作成中..."
if sudo virsh net-info airgap-training >/dev/null 2>&1; then
    echo "  airgap-training ネットワークは既に存在します"
else
    sudo virsh net-define "$SCRIPT_DIR/create-airgap-network.xml"
    sudo virsh net-start airgap-training
    sudo virsh net-autostart airgap-training
    echo "  airgap-training ネットワークを作成しました"
fi

# ネットワーク確認
echo "[4/4] ネットワーク設定を確認中..."
sudo virsh net-list --all
echo ""
sudo virsh net-dumpxml airgap-training

echo ""
echo "=== KVM ホスト準備完了 ==="
echo ""
echo "次のステップ:"
echo "  1. RHEL 10 ISO を用意"
echo "  2. ./create-rhel-vm.sh /path/to/rhel10.iso を実行"
echo "  3. (オプション) Windows 11 ISO を用意"
echo "  4. ./create-windows-vm.sh /path/to/win11.iso を実行"
