#!/bin/bash
# bastion（コントローラ母艦）に airgap 資材を一括転送するスクリプト
#
# 使い方:
#   ./transfer-to-bastion.sh <bastion の IP> [パスワード]
#
# 例:
#   ./transfer-to-bastion.sh 192.168.100.2 password

set -euo pipefail

BASTION_IP="${1:-}"
BASTION_PASS="${2:-password}"

if [[ -z "$BASTION_IP" ]]; then
    echo "使い方: $0 <bastion の IP> [パスワード]"
    echo "例:     $0 192.168.100.2 password"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/offline-resources"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

run_ssh() { sshpass -p "$BASTION_PASS" ssh $SSH_OPTS "root@${BASTION_IP}" "$@"; }
run_scp() { sshpass -p "$BASTION_PASS" scp $SSH_OPTS "$@"; }

echo "============================================"
echo "  Bastion への資材転送"
echo "============================================"
echo "  転送先: root@$BASTION_IP:/opt/airgap/"
echo "  ソース: $SCRIPT_DIR"
echo ""

# --- Step 1: 小〜中ファイルを tar で転送（ISO を除外してディスク節約） ---
echo "[1/4] アーカイブ作成中（ISO 除外）..."
tar czf /tmp/airgap-bundle-full.tar.gz \
    -C "$(dirname "$SCRIPT_DIR")" \
    --exclude='airgap/offline-resources/vm-images' \
    --exclude='airgap/offline-resources/iso' \
    --exclude='airgap/.tracecraft' \
    --exclude='airgap/kvm/vms/*.qcow2' \
    airgap/

SIZE=$(du -sh /tmp/airgap-bundle-full.tar.gz | awk '{print $1}')
echo "  アーカイブサイズ: $SIZE（ISO 除外）"

echo "[2/4] 転送・展開中..."
run_ssh '
    set -e
    mkdir -p /opt
    if [[ -d /opt/airgap ]]; then
        find /opt/airgap -maxdepth 1 -not -name airgap -not -name offline-resources | xargs rm -rf 2>/dev/null || true
    fi
'

run_scp /tmp/airgap-bundle-full.tar.gz "root@${BASTION_IP}:/tmp/airgap-bundle-full.tar.gz"
run_ssh '
    set -e
    cd /opt
    tar xzf /tmp/airgap-bundle-full.tar.gz
    rm -f /tmp/airgap-bundle-full.tar.gz
'
rm -f /tmp/airgap-bundle-full.tar.gz
echo "  展開完了"

# --- Step 2: ISO ファイルを個別転送（大容量のため tar を経由しない） ---
echo "[3/4] ISO ファイルを個別転送中..."
run_ssh 'mkdir -p /opt/airgap/offline-resources/iso'

if [[ -d "$BUNDLE_DIR/iso" ]]; then
    for iso in "$BUNDLE_DIR"/iso/*.iso; do
        [[ -f "$iso" ]] || continue
        iso_name=$(basename "$iso")
        iso_size=$(du -sh "$iso" | awk '{print $1}')

        # 転送先に同名・同サイズのファイルがあればスキップ
        local_bytes=$(stat --format=%s "$iso")
        remote_bytes=$(run_ssh "stat --format=%s /opt/airgap/offline-resources/iso/$iso_name 2>/dev/null || echo 0")
        if [[ "$local_bytes" == "$remote_bytes" ]]; then
            echo "  $iso_name ($iso_size): スキップ（転送済み）"
            continue
        fi

        echo "  $iso_name ($iso_size): 転送中..."
        run_scp "$iso" "root@${BASTION_IP}:/opt/airgap/offline-resources/iso/$iso_name"
    done
else
    echo "  ISO ディレクトリなし — スキップ"
fi

# --- Step 3: 検証 ---
echo "[4/4] 展開結果を検証中..."
VERIFY_RESULT=$(run_ssh '
    ERRORS=0
    for f in \
        /opt/airgap/rhel-version.conf \
        /opt/airgap/setup-controller.sh \
        /opt/airgap/inventory/hosts.yml \
        /opt/airgap/group_vars/all.yml \
        /opt/airgap/group_vars/rhel.yml \
        /opt/airgap/playbooks/repo-server-setup.yml \
        /opt/airgap/playbooks/rhel-setup.yml \
        /opt/airgap/playbooks/distribute-resources.yml; do
        if [[ ! -f "$f" ]]; then
            echo "MISSING: $f"
            ERRORS=$((ERRORS + 1))
        fi
    done

    ROLE_COUNT=$(find /opt/airgap/playbooks/roles -name "main.yml" -path "*/tasks/*" 2>/dev/null | wc -l)
    if [[ "$ROLE_COUNT" -lt 7 ]]; then
        echo "WARN: roles tasks count=$ROLE_COUNT (expected >=7)"
        ERRORS=$((ERRORS + 1))
    fi

    if [[ $ERRORS -eq 0 ]]; then
        echo "OK"
    else
        echo "ERRORS: $ERRORS"
    fi
')

if [[ "$VERIFY_RESULT" == *"OK"* ]]; then
    echo "  検証OK: 全ファイルが正しく配置されています"
else
    echo "  検証NG:"
    echo "$VERIFY_RESULT"
    echo ""
    echo "  手動で確認してください: ssh root@$BASTION_IP ls /opt/airgap/"
    exit 1
fi

echo ""
run_ssh '
    echo "=== 配置完了 ==="
    echo "ディレクトリ: /opt/airgap/"
    ls /opt/airgap/
    echo ""
    echo "offline-resources:"
    du -sh /opt/airgap/offline-resources/*/ 2>/dev/null || echo "  (なし)"
'

echo ""
echo "============================================"
echo "  転送完了"
echo "============================================"
echo ""
echo "次のステップ（bastion 上で実行）:"
echo "  ssh root@$BASTION_IP"
echo "  cd /opt/airgap"
echo "  ./setup-controller.sh"
