#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/offline-resources"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

echo "============================================"
echo "  Airgap コントローラノード セットアップ"
echo "============================================"
echo ""
echo "このスクリプトは ansible-playbook を実行するマシンを"
echo "airgap 環境でセットアップします。"
echo ""

# --- Step 1: Python3 確認 ---
log_info "Step 1: Python3 の確認"
if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 が見つかりません。RHEL 10 の場合: dnf install python3 python3-pip"
    exit 1
fi
python3 --version
echo ""

# --- Step 2: pip の確認 ---
log_info "Step 2: pip の確認"
if ! python3 -m pip --version >/dev/null 2>&1; then
    log_warn "pip が見つかりません。ensurepip を試行します"
    python3 -m ensurepip --user 2>/dev/null || {
        log_error "pip のセットアップに失敗しました。dnf install python3-pip を実行してください"
        exit 1
    }
fi
python3 -m pip --version
echo ""

# --- Step 3: ansible-core のインストール ---
log_info "Step 3: ansible-core のインストール"
if command -v ansible >/dev/null 2>&1; then
    log_info "ansible は既にインストール済みです"
    ansible --version | head -1
else
    if [[ -d "$BUNDLE_DIR/pip-packages" ]]; then
        log_info "バンドルの pip パッケージからインストールします"
        python3 -m pip install --no-index --find-links="$BUNDLE_DIR/pip-packages/" \
            ansible-core 2>&1 | tail -3
    else
        log_error "pip-packages/ が見つかりません。バンドルを確認してください"
        exit 1
    fi
fi
echo ""

# --- Step 4: sshpass のインストール ---
log_info "Step 4: sshpass のインストール"
if command -v sshpass >/dev/null 2>&1; then
    log_info "sshpass は既にインストール済みです"
    sshpass -V 2>&1 | head -1
else
    SSHPASS_TAR="$BUNDLE_DIR/binaries/sshpass-1.10.tar.gz"
    if [[ -f "$SSHPASS_TAR" ]]; then
        log_info "ソースからビルドします（gcc, make が必要）"
        if ! command -v gcc >/dev/null 2>&1; then
            log_error "gcc が見つかりません。dnf install gcc make を実行してください"
            exit 1
        fi
        TMPDIR=$(mktemp -d)
        tar xzf "$SSHPASS_TAR" -C "$TMPDIR"
        cd "$TMPDIR/sshpass-1.10"
        ./configure --prefix=/usr/local 2>&1 | tail -1
        make 2>&1 | tail -1
        sudo make install 2>&1 | tail -1
        cd "$SCRIPT_DIR"
        rm -rf "$TMPDIR"
        log_info "sshpass インストール完了"
    else
        log_warn "sshpass-1.10.tar.gz が見つかりません。パスワード認証を使う場合は手動でインストールしてください"
    fi
fi
echo ""

# --- Step 5: Ansible コレクションのインストール ---
log_info "Step 5: Ansible コレクションのインストール"
COLLECTIONS_DIR="$BUNDLE_DIR/ansible-collections"
if [[ -d "$COLLECTIONS_DIR" ]]; then
    for col in ansible-posix ansible-windows community-general community-windows community-library_inventory_filtering_v1; do
        tarball=$(ls "$COLLECTIONS_DIR"/${col}-*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$tarball" ]]; then
            name=$(echo "$col" | sed 's/-/./g' | sed 's/_/./g' | sed 's/v1/v1/')
            if ansible-galaxy collection list 2>/dev/null | grep -q "${col//-/.}"; then
                log_info "$col: インストール済み"
            else
                ansible-galaxy collection install "$tarball" --force 2>&1 | tail -1
                log_info "$col: インストール完了"
            fi
        fi
    done
else
    log_error "ansible-collections/ が見つかりません"
    exit 1
fi
echo ""

# --- Step 6: SSH 接続の確認 ---
log_info "Step 6: SSH 接続環境の確認"
echo -n "  ssh: "; command -v ssh && echo "" || echo "NOT FOUND"
echo -n "  sshpass: "; command -v sshpass && echo "" || echo "NOT FOUND (パスワード認証不可)"
echo ""

# --- 検証 ---
log_info "=== セットアップ完了 ==="
echo ""
echo "  ansible:     $(ansible --version 2>/dev/null | head -1)"
echo "  ansible-core: $(python3 -c 'import ansible; print(ansible.__version__)' 2>/dev/null)"
echo ""
echo "コレクション:"
ansible-galaxy collection list 2>/dev/null | grep -E 'ansible\.(posix|windows)|community\.(general|windows)' | head -10
echo ""
echo "次のステップ:"
echo "  1. inventory/ のホスト情報を環境に合わせて編集"
echo "  2. ansible-playbook -i inventory/rhel-hosts.yml playbooks/repo-server-setup.yml"
echo "  3. ansible-playbook -i inventory/rhel-hosts.yml playbooks/rhel-setup.yml"
echo "  4. (Windows) ansible-playbook -i inventory/windows-hosts.yml playbooks/windows-setup.yml"
echo ""
echo "詳細は docs/deployment-guide.md を参照してください。"
