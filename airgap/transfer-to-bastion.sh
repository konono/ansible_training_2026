#!/bin/bash
# bastion（コントローラ母艦）に airgap 資材を一括転送するスクリプト
#
# 使い方:
#   ./transfer-to-bastion.sh <bastion の IP> [パスワード]
#
# 例:
#   ./transfer-to-bastion.sh 192.168.100.2 password

set -uo pipefail

BASTION_IP="${1:-}"
BASTION_PASS="${2:-password}"

if [[ -z "$BASTION_IP" ]]; then
    echo "使い方: $0 <bastion の IP> [パスワード]"
    echo "例:     $0 192.168.100.2 password"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/offline-resources"

echo "============================================"
echo "  Bastion への資材転送"
echo "============================================"
echo "  転送先: root@$BASTION_IP:/opt/airgap/"
echo "  ソース: $SCRIPT_DIR"
echo ""

# tar で固める（vm-images 除外）
echo "[1/3] アーカイブ作成中..."
tar czf /tmp/airgap-bundle-full.tar.gz \
    -C "$(dirname "$SCRIPT_DIR")" \
    --exclude='airgap/offline-resources/vm-images' \
    --exclude='airgap/.tracecraft' \
    --exclude='airgap/kvm/vms/*.qcow2' \
    --exclude='airgap/kvm/vms/**/*.qcow2' \
    airgap/

SIZE=$(du -sh /tmp/airgap-bundle-full.tar.gz | awk '{print $1}')
echo "  アーカイブサイズ: $SIZE"

# 転送
echo "[2/3] 転送中... ($SIZE)"
sshpass -p "$BASTION_PASS" scp -o StrictHostKeyChecking=no \
    /tmp/airgap-bundle-full.tar.gz \
    "root@${BASTION_IP}:/tmp/airgap-bundle-full.tar.gz"

# 展開
echo "[3/3] 展開中..."
sshpass -p "$BASTION_PASS" ssh -o StrictHostKeyChecking=no "root@${BASTION_IP}" '
    mkdir -p /opt
    cd /opt
    tar xzf /tmp/airgap-bundle-full.tar.gz
    rm -f /tmp/airgap-bundle-full.tar.gz
    echo ""
    echo "=== 配置完了 ==="
    echo "ディレクトリ: /opt/airgap/"
    ls /opt/airgap/
    echo ""
    echo "offline-resources:"
    du -sh /opt/airgap/offline-resources/*/
'

rm -f /tmp/airgap-bundle-full.tar.gz

echo ""
echo "============================================"
echo "  転送完了"
echo "============================================"
echo ""
echo "次のステップ（bastion 上で実行）:"
echo "  ssh root@$BASTION_IP"
echo "  cd /opt/airgap"
echo "  ./setup-controller.sh"
