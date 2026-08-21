#!/bin/bash
set -euo pipefail

ISO_PATH="${1:-}"
VM_NAME="${2:-win11-airgap-target}"
MEMORY="${3:-8192}"
VCPUS="${4:-4}"
DISK_SIZE="${5:-120}"

if [[ -z "$ISO_PATH" ]]; then
    echo "使用方法: $0 <Windows 11 ISO パス> [VM名] [メモリMB] [vCPU数] [ディスクGB]"
    echo ""
    echo "例:"
    echo "  $0 /path/to/Win11_Japanese_x64.iso"
    echo "  $0 /path/to/Win11_Japanese_x64.iso win11-training 16384 4 200"
    exit 1
fi

if [[ ! -f "$ISO_PATH" ]]; then
    echo "エラー: ISO ファイルが見つかりません: $ISO_PATH"
    exit 1
fi

echo "=== Windows 11 Airgap VM 作成 ==="
echo "  VM名:     $VM_NAME"
echo "  ISO:      $ISO_PATH"
echo "  メモリ:   ${MEMORY}MB (最小8GB推奨)"
echo "  vCPU:     $VCPUS"
echo "  ディスク: ${DISK_SIZE}GB"
echo "  ネットワーク: airgap-training (隔離)"
echo "  TPM 2.0:  エミュレーション有効"
echo ""

if sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "VM '$VM_NAME' は既に存在します。"
    echo "削除するには: sudo virsh destroy $VM_NAME && sudo virsh undefine $VM_NAME --remove-all-storage --nvram"
    exit 1
fi

# swtpm が必要（TPM 2.0 エミュレーション）
if ! command -v swtpm >/dev/null 2>&1; then
    echo "swtpm をインストールしています（TPM 2.0 エミュレーションに必要）..."
    sudo dnf install -y swtpm swtpm-tools
fi

sudo virt-install \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --vcpus "$VCPUS" \
    --disk size="$DISK_SIZE",bus=sata \
    --cdrom "$ISO_PATH" \
    --os-variant win11 \
    --network network=airgap-training,mac=52:54:00:AA:BB:20 \
    --graphics vnc,listen=0.0.0.0 \
    --features kvm.hidden.state=on \
    --cpu host-passthrough,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time,hv_vpindex,hv_runtime,hv_synic,hv_stimer,hv_reset,hv_frequencies,hv_reenlightenment,hv_tlbflush,hv_ipi \
    --tpm backend.type=emulator,model=tpm-crb \
    --boot uefi \
    --noautoconsole

echo ""
echo "=== VM 作成完了 ==="
echo ""
echo "VNC コンソールで接続してWindowsインストールを完了してください:"
echo "  sudo virsh vncdisplay $VM_NAME"
echo ""
echo "Windowsインストール後の手順:"
echo "  1. 管理者PowerShellで SSH を有効化:"
echo "     Set-ExecutionPolicy RemoteSigned -Force"
echo "     .\\enable-ssh.ps1"
echo ""
echo "  2. バンドルを転送（ISO方式推奨）:"
echo "     mkisofs -o /tmp/airgap-bundle.iso -R -J /path/to/airgap/offline-resources/"
echo "     sudo virsh attach-disk $VM_NAME /tmp/airgap-bundle.iso sdb --type cdrom"
echo "     (VM内) D:\\ドライブから C:\\airgap-bundle にコピー"
echo ""
echo "  3. Ansible Playbook を実行:"
echo "     cd /path/to/airgap/"
echo "     ansible-playbook -i inventory/windows-hosts.yml playbooks/windows-setup.yml"
