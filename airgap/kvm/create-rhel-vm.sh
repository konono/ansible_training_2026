#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../rhel-version.conf"

ISO_PATH="${1:-}"
VM_NAME="${2:-rhel${RHEL_MAJOR}-airgap-target}"
MEMORY="${3:-4096}"
VCPUS="${4:-4}"
DISK_SIZE="${5:-100}"

if [[ -z "$ISO_PATH" ]]; then
    echo "使用方法: $0 <RHEL${RHEL_MAJOR} ISO パス> [VM名] [メモリMB] [vCPU数] [ディスクGB]"
    echo ""
    echo "例:"
    echo "  $0 /path/to/rhel-${RHEL_VERSION}-x86_64-dvd.iso"
    echo "  $0 /path/to/rhel-${RHEL_VERSION}-x86_64-dvd.iso rhel${RHEL_MAJOR}-training 8192 4 200"
    exit 1
fi

if [[ ! -f "$ISO_PATH" ]]; then
    echo "エラー: ISO ファイルが見つかりません: $ISO_PATH"
    exit 1
fi

echo "=== RHEL ${RHEL_MAJOR} Airgap VM 作成 ==="
echo "  VM名:     $VM_NAME"
echo "  ISO:      $ISO_PATH"
echo "  メモリ:   ${MEMORY}MB"
echo "  vCPU:     $VCPUS"
echo "  ディスク: ${DISK_SIZE}GB"
echo "  ネットワーク: airgap-training (隔離)"
echo ""

# VM が既に存在する場合はスキップ
if sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "VM '$VM_NAME' は既に存在します。"
    echo "削除するには: sudo virsh destroy $VM_NAME && sudo virsh undefine $VM_NAME --remove-all-storage"
    exit 1
fi

sudo virt-install \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --vcpus "$VCPUS" \
    --disk size="$DISK_SIZE" \
    --cdrom "$ISO_PATH" \
    --os-variant "rhel${RHEL_MAJOR}-unknown" \
    --network network=airgap-training,mac=52:54:00:AA:BB:10 \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole

echo ""
echo "=== VM 作成完了 ==="
echo ""
echo "VNC コンソールで接続してOSインストールを完了してください:"
echo "  sudo virsh vncdisplay $VM_NAME"
echo ""
echo "OSインストール後の手順:"
echo "  1. SSH を有効化: systemctl enable --now sshd"
echo "  2. ファイアウォール設定: firewall-cmd --permanent --add-service=ssh && firewall-cmd --reload"
echo "  3. バンドルを転送（ISO方式推奨）:"
echo "     mkisofs -o /tmp/airgap-bundle.iso -R -J /path/to/airgap/offline-resources/"
echo "     sudo virsh attach-disk $VM_NAME /tmp/airgap-bundle.iso sdb --type cdrom"
echo "     (VM内) mount /dev/sr0 /mnt && cp -r /mnt/* /opt/airgap-bundle/"
echo ""
echo "  4. Ansible Playbook を実行:"
echo "     cd /path/to/airgap/"
echo "     ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml"
