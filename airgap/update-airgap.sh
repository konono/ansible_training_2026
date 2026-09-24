#!/bin/bash
# /opt/airgap/ の Ansible・スクリプト・ドキュメントだけを差分アップデートするスクリプト
#
# offline-resources/ (パッケージ, ISO, コンテナイメージ) は転送しない。
# 既存の allocations.json, credentials.csv, ユーザーデータは保持される。
#
# 使い方:
#   ./update-airgap.sh                          # bastion 自身の /opt/airgap/ を更新
#   ./update-airgap.sh <bastion IP> [パスワード] # リモートの bastion に転送して更新
#
# 例:
#   ./update-airgap.sh                     # ローカル更新
#   ./update-airgap.sh 192.168.100.2       # リモート更新（パスワード: password）
#   ./update-airgap.sh 192.168.100.2 mypass

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASTION_IP="${1:-}"
BASTION_PASS="${2:-password}"
DEST_DIR="/opt/airgap"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if [[ -n "$BASTION_IP" ]]; then
    MODE="remote"
    run_cmd() { sshpass -p "$BASTION_PASS" ssh $SSH_OPTS "root@${BASTION_IP}" "$@"; }
    run_scp() { sshpass -p "$BASTION_PASS" scp $SSH_OPTS "$@"; }
else
    MODE="local"
    run_cmd() { eval "$@"; }
fi

echo "============================================"
echo "  Airgap 資材アップデート"
echo "============================================"
echo ""
echo "  モード: ${MODE}"
if [[ "$MODE" == "remote" ]]; then
    echo "  転送先: root@${BASTION_IP}:${DEST_DIR}/"
fi
echo "  ソース: ${SCRIPT_DIR}/"
echo ""

# --- 事前チェック ---
if [[ "$MODE" == "remote" ]] && ! command -v sshpass >/dev/null 2>&1; then
    log_error "sshpass が見つかりません。パスワード無しの SSH 鍵認証を使うか、sshpass をインストールしてください"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/ansible.cfg" ]]; then
    log_error "ソースディレクトリに ansible.cfg がありません。airgap/ ディレクトリから実行してください"
    exit 1
fi

# --- Step 1: 転送先の状態を確認 ---
log_info "Step 1: 転送先の状態を確認"

DEST_EXISTS=$(run_cmd "test -d ${DEST_DIR} && echo yes || echo no")
if [[ "$DEST_EXISTS" != "yes" ]]; then
    log_error "${DEST_DIR} が存在しません。初回デプロイには transfer-to-bastion.sh を使用してください"
    exit 1
fi

OFFLINE_EXISTS=$(run_cmd "test -d ${DEST_DIR}/offline-resources && echo yes || echo no")
if [[ "$OFFLINE_EXISTS" == "yes" ]]; then
    log_info "offline-resources/ を検出 — 保持します"
else
    log_warn "offline-resources/ が見つかりません（初回デプロイが未完了の可能性）"
fi

echo ""

# --- Step 2: アップデート用アーカイブ作成 ---
log_info "Step 2: アップデート用アーカイブ作成（パッケージ・ISO・VM 除外）"

ARCHIVE="/tmp/airgap-update-${TIMESTAMP}.tar.gz"
tar czf "$ARCHIVE" \
    -C "$(dirname "$SCRIPT_DIR")" \
    --exclude='airgap/offline-resources' \
    --exclude='airgap/kvm/vms/*.qcow2' \
    --exclude='airgap/kvm/vms/win11' \
    --exclude='airgap/.tracecraft' \
    airgap/

SIZE=$(du -sh "$ARCHIVE" | awk '{print $1}')
log_info "アーカイブサイズ: ${SIZE}"
echo ""

# --- Step 3: バックアップ ---
log_info "Step 3: 現行ファイルのバックアップ"

BACKUP_DIR="${DEST_DIR}/.backup_${TIMESTAMP}"
run_cmd "
    mkdir -p ${BACKUP_DIR}
    # 設定ファイルのバックアップ
    cp -a ${DEST_DIR}/ansible.cfg          ${BACKUP_DIR}/ 2>/dev/null || true
    cp -a ${DEST_DIR}/inventory/           ${BACKUP_DIR}/inventory/ 2>/dev/null || true
    cp -a ${DEST_DIR}/group_vars/          ${BACKUP_DIR}/group_vars/ 2>/dev/null || true
    cp -a ${DEST_DIR}/trainees.yml         ${BACKUP_DIR}/ 2>/dev/null || true
    cp -a ${DEST_DIR}/rhel-version.conf    ${BACKUP_DIR}/ 2>/dev/null || true
    echo 'done'
"
log_info "バックアップ先: ${BACKUP_DIR}/"
echo ""

# --- Step 4: 転送と展開 ---
log_info "Step 4: 転送と展開"

if [[ "$MODE" == "remote" ]]; then
    run_scp "$ARCHIVE" "root@${BASTION_IP}:/tmp/$(basename "$ARCHIVE")"
fi

run_cmd "
    set -e
    cd /opt

    # offline-resources を退避するシンボリックリンク等は不要
    # tar は offline-resources を含んでいないので上書きされない

    # 既存の Ansible ファイルを削除（offline-resources, .backup*, /opt/training は保持）
    find ${DEST_DIR} -maxdepth 1 \
        -not -name 'airgap' \
        -not -name '$(basename "$DEST_DIR")' \
        -not -name 'offline-resources' \
        -not -name '.backup_*' \
        -not -name 'credentials.csv' \
        -mindepth 1 \
        -exec rm -rf {} + 2>/dev/null || true

    # 展開（offline-resources は含まれていないので安全）
    tar xzf /tmp/$(basename "$ARCHIVE") --strip-components=0
    rm -f /tmp/$(basename "$ARCHIVE")
"

rm -f "$ARCHIVE"
log_info "展開完了"
echo ""

# --- Step 5: inventory のカスタマイズ復元 ---
log_info "Step 5: inventory のカスタマイズを確認"

# inventory/hosts.yml は環境固有の IP が入っているので、バックアップから復元するか確認
INVENTORY_CHANGED=$(run_cmd "
    if [[ -f ${BACKUP_DIR}/inventory/hosts.yml ]]; then
        if ! diff -q ${BACKUP_DIR}/inventory/hosts.yml ${DEST_DIR}/inventory/hosts.yml >/dev/null 2>&1; then
            echo 'changed'
        else
            echo 'same'
        fi
    else
        echo 'no_backup'
    fi
")

if [[ "$INVENTORY_CHANGED" == "changed" ]]; then
    log_warn "inventory/hosts.yml がアップデートで変更されました"
    log_warn "環境固有の設定はバックアップから復元してください:"
    log_warn "  cp ${BACKUP_DIR}/inventory/hosts.yml ${DEST_DIR}/inventory/hosts.yml"
    log_warn "  または差分を確認: diff ${BACKUP_DIR}/inventory/hosts.yml ${DEST_DIR}/inventory/hosts.yml"
fi

# trainees.yml は既存データを保持
TRAINEES_EXISTS=$(run_cmd "test -f ${BACKUP_DIR}/trainees.yml && echo yes || echo no")
if [[ "$TRAINEES_EXISTS" == "yes" ]]; then
    run_cmd "cp -a ${BACKUP_DIR}/trainees.yml ${DEST_DIR}/trainees.yml"
    log_info "trainees.yml をバックアップから復元しました（受講者データ保持）"
fi

# rhel-version.conf は環境固有なのでバックアップを優先
RHEL_CONF_EXISTS=$(run_cmd "test -f ${BACKUP_DIR}/rhel-version.conf && echo yes || echo no")
if [[ "$RHEL_CONF_EXISTS" == "yes" ]]; then
    run_cmd "cp -a ${BACKUP_DIR}/rhel-version.conf ${DEST_DIR}/rhel-version.conf"
    log_info "rhel-version.conf をバックアップから復元しました"
fi

echo ""

# --- Step 6: パーミッション修正 ---
log_info "Step 6: パーミッション修正"

run_cmd "
    chmod +x ${DEST_DIR}/*.sh 2>/dev/null || true
    chmod +x ${DEST_DIR}/scripts/*.py 2>/dev/null || true
    chmod +x ${DEST_DIR}/kvm/*.sh 2>/dev/null || true
    # allocations.json は一般ユーザーが読み取れるようにする
    chmod 644 /opt/training/allocations.json 2>/dev/null || true
    chmod 644 /opt/training/.lock 2>/dev/null || true
"
log_info "パーミッション設定完了"
echo ""

# --- Step 7: 検証 ---
log_info "Step 7: アップデート結果を検証"

VERIFY_RESULT=$(run_cmd "
    ERRORS=0
    WARNINGS=0

    # 必須ファイルの存在チェック
    for f in \
        ${DEST_DIR}/rhel-version.conf \
        ${DEST_DIR}/ansible.cfg \
        ${DEST_DIR}/setup-controller.sh \
        ${DEST_DIR}/deploy-training.sh \
        ${DEST_DIR}/destroy-training.sh \
        ${DEST_DIR}/inventory/hosts.yml \
        ${DEST_DIR}/group_vars/all.yml \
        ${DEST_DIR}/group_vars/rhel.yml \
        ${DEST_DIR}/scripts/allocate.py \
        ${DEST_DIR}/playbooks/site.yml \
        ${DEST_DIR}/playbooks/repo-server-setup.yml \
        ${DEST_DIR}/playbooks/rhel-setup.yml \
        ${DEST_DIR}/playbooks/deploy-my-env.yml \
        ${DEST_DIR}/playbooks/destroy-my-env.yml \
        ${DEST_DIR}/playbooks/setup-trainees.yml; do
        if [[ ! -f \"\$f\" ]]; then
            echo \"MISSING: \$f\"
            ERRORS=\$((ERRORS + 1))
        fi
    done

    # ロール数の確認
    ROLE_COUNT=\$(find ${DEST_DIR}/playbooks/roles -name 'main.yml' -path '*/tasks/*' 2>/dev/null | wc -l)
    if [[ \"\$ROLE_COUNT\" -lt 7 ]]; then
        echo \"WARN: roles tasks count=\$ROLE_COUNT (expected >=7)\"
        WARNINGS=\$((WARNINGS + 1))
    fi

    # offline-resources の確認
    if [[ ! -d ${DEST_DIR}/offline-resources ]]; then
        echo 'WARN: offline-resources/ が見つかりません'
        WARNINGS=\$((WARNINGS + 1))
    fi

    # スクリプトの実行権限チェック
    for f in ${DEST_DIR}/deploy-training.sh ${DEST_DIR}/destroy-training.sh ${DEST_DIR}/setup-controller.sh; do
        if [[ -f \"\$f\" ]] && [[ ! -x \"\$f\" ]]; then
            echo \"WARN: \$f に実行権限がありません\"
            WARNINGS=\$((WARNINGS + 1))
        fi
    done

    if [[ \$ERRORS -eq 0 ]]; then
        echo \"OK (warnings: \$WARNINGS)\"
    else
        echo \"ERRORS: \$ERRORS, WARNINGS: \$WARNINGS\"
    fi
")

if [[ "$VERIFY_RESULT" == *"OK"* ]]; then
    log_info "検証OK: 全ファイルが正しく配置されています"
    if [[ "$VERIFY_RESULT" == *"warnings: 0"* ]]; then
        : # 警告なし
    else
        log_warn "$VERIFY_RESULT"
    fi
else
    log_error "検証NG:"
    echo "$VERIFY_RESULT"
fi

echo ""

# --- Step 8: training サーバーへの同期 ---
log_info "Step 8: training サーバーへのコード同期"

SYNC_TRAINING=$(run_cmd "
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        echo 'no_ansible'
    elif [[ ! -f ${DEST_DIR}/inventory/hosts.yml ]]; then
        echo 'no_inventory'
    else
        echo 'ready'
    fi
")

if [[ "$SYNC_TRAINING" == "ready" ]]; then
    echo ""
    echo "  training サーバーにスクリプト・Playbook を同期します。"
    echo "  （コンテナイメージ等の重い処理はスキップ — コード同期のみ）"
    echo ""

    SYNC_RESULT=$(run_cmd "
        cd ${DEST_DIR}
        SSH_ARGS='-e ansible_ssh_common_args=\"-o StrictHostKeyChecking=no\"'
        ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml \
            --tags sync-code \
            -e ansible_ssh_common_args='-o StrictHostKeyChecking=no' \
            2>&1
        echo \"EXIT_CODE=\$?\"
    ")

    if echo "$SYNC_RESULT" | grep -q 'EXIT_CODE=0'; then
        log_info "training サーバーへの同期が完了しました"
        echo "$SYNC_RESULT" | grep -E 'ok=|changed=|failed=' | tail -3
    else
        log_warn "training サーバーへの同期でエラーが発生しました"
        log_warn "手動で再実行してください:"
        log_warn "  cd ${DEST_DIR}"
        log_warn "  ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml --tags sync-code"
        echo ""
        echo "$SYNC_RESULT" | tail -15
    fi
elif [[ "$SYNC_TRAINING" == "no_ansible" ]]; then
    log_warn "ansible-playbook が見つかりません — training サーバーへの同期はスキップ"
    log_warn "bastion で setup-controller.sh を実行後、手動で同期してください:"
    log_warn "  ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml --tags sync-code"
else
    log_warn "inventory/hosts.yml が見つかりません — training サーバーへの同期はスキップ"
fi

echo ""

# --- 結果表示 ---
run_cmd "
    echo '=== アップデート完了 ==='
    echo ''
    echo 'ディレクトリ: ${DEST_DIR}/'
    echo ''
    echo '更新されたファイル:'
    ls ${DEST_DIR}/*.sh ${DEST_DIR}/ansible.cfg ${DEST_DIR}/Makefile 2>/dev/null | sed 's|^|  |'
    echo ''
    echo 'playbooks/roles:'
    find ${DEST_DIR}/playbooks/roles -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's|^|  |'
    echo ''
    echo 'バックアップ: ${BACKUP_DIR}/'
"

echo ""
echo "============================================"
echo "  アップデート完了"
echo "============================================"
echo ""
if [[ "$INVENTORY_CHANGED" == "changed" ]]; then
    echo "!! inventory/hosts.yml の差分を確認してください:"
    echo "   diff ${BACKUP_DIR}/inventory/hosts.yml ${DEST_DIR}/inventory/hosts.yml"
    echo ""
fi
echo "ロールバック（問題があった場合）:"
echo "  cp -a ${BACKUP_DIR}/* ${DEST_DIR}/"
