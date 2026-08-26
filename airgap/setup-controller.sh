#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/rhel-version.conf"
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

if [[ $EUID -ne 0 ]]; then
    log_error "root 権限が必要です。sudo ./setup-controller.sh で実行してください"
    exit 1
fi

# --- Step 1: DVD ISO からローカルリポジトリを設定 ---
log_info "Step 1: DVD ISO からローカルリポジトリを設定"

ISO_PATH="${1:-}"
if [[ -z "$ISO_PATH" ]]; then
    ISO_PATH=$(ls "$BUNDLE_DIR"/iso/rhel-${RHEL_VERSION}-*.iso 2>/dev/null | head -1)
    if [[ -z "$ISO_PATH" ]]; then
        ISO_PATH=$(ls "$BUNDLE_DIR"/iso/rhel-*.iso 2>/dev/null | head -1)
    fi
fi
if [[ -z "$ISO_PATH" ]] || [[ ! -f "$ISO_PATH" ]]; then
    log_error "DVD ISO が見つかりません。引数で指定するか offline-resources/iso/ に配置してください"
    log_error "使用方法: $0 [/path/to/rhel-${RHEL_MAJOR}.x-dvd.iso]"
    exit 1
fi
log_info "ISO: $ISO_PATH"

if mountpoint -q /mnt/cdrom 2>/dev/null; then
    log_info "/mnt/cdrom は既にマウント済みです"
else
    mkdir -p /mnt/cdrom
    mount -o loop,ro "$ISO_PATH" /mnt/cdrom 2>/dev/null || {
        log_error "ISO マウントに失敗しました（root 権限が必要です）"
        exit 1
    }
    log_info "ISO をマウントしました"
fi

if [[ ! -d /mnt/cdrom/BaseOS ]]; then
    log_error "ISO に BaseOS ディレクトリがありません。DVD ISO（Boot ISO ではない）を使用してください"
    exit 1
fi

# UBI リポジトリ無効化 + ローカルリポジトリ設定
sed -i 's/enabled *= *1/enabled = 0/g' /etc/yum.repos.d/ubi.repo 2>/dev/null || true
subscription-manager config --rhsm.manage_repos=0 2>/dev/null || true

cat > /etc/yum.repos.d/local-baseos.repo << EOF
[local-baseos]
name=Local BaseOS (DVD ISO)
baseurl=file:///mnt/cdrom/BaseOS
enabled=1
gpgcheck=0
EOF

cat > /etc/yum.repos.d/local-appstream.repo << EOF
[local-appstream]
name=Local AppStream (DVD ISO)
baseurl=file:///mnt/cdrom/AppStream
enabled=1
gpgcheck=0
EOF

dnf clean all >/dev/null 2>&1
log_info "ローカルリポジトリ設定完了"
echo ""

# --- Step 2: 前提パッケージのインストール ---
log_info "Step 2: 前提パッケージのインストール"

# RHEL 9 では python3.12 を使用（pip パッケージの互換性のため）
PYTHON_CMD="python3"
if [[ "$(python3 --version 2>&1)" == *"3.9"* ]] || [[ "$(python3 --version 2>&1)" == *"3.11"* ]]; then
    log_info "Python 3.12 をインストールします（pip パッケージ互換性のため）"
    dnf install -y python3.12 python3.12-pip 2>&1 | tail -3
    if command -v python3.12 >/dev/null 2>&1; then
        PYTHON_CMD="python3.12"
        log_info "Python 3.12 を使用します"
    fi
fi

PKGS_TO_INSTALL=()
command -v gcc       >/dev/null 2>&1 || PKGS_TO_INSTALL+=("gcc")
command -v make      >/dev/null 2>&1 || PKGS_TO_INSTALL+=("make")
command -v ssh       >/dev/null 2>&1 || PKGS_TO_INSTALL+=("openssh-clients")

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
    log_info "インストール: ${PKGS_TO_INSTALL[*]}"
    dnf install -y "${PKGS_TO_INSTALL[@]}" 2>&1 | tail -3
else
    log_info "追加パッケージは全てインストール済みです"
fi

$PYTHON_CMD --version
$PYTHON_CMD -m pip --version
echo ""

# --- Step 3: ansible-core のインストール ---
log_info "Step 3: ansible-core のインストール"
if command -v ansible >/dev/null 2>&1; then
    log_info "ansible は既にインストール済みです"
    ansible --version | head -1
else
    if [[ -d "$BUNDLE_DIR/pip-packages" ]]; then
        log_info "バンドルの pip パッケージからインストールします"
        $PYTHON_CMD -m pip install --no-index --find-links="$BUNDLE_DIR/pip-packages/" \
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
    for col in ansible-posix ansible-windows community-general community-windows; do
        tarball=$(ls "$COLLECTIONS_DIR"/${col}-*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$tarball" ]]; then
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
echo "  ansible-core: $($PYTHON_CMD -c 'import ansible; print(ansible.__version__)' 2>/dev/null)"
echo ""
echo "コレクション:"
ansible-galaxy collection list 2>/dev/null | grep -E 'ansible\.(posix|windows)|community\.(general|windows)' | head -10
echo ""
echo "次のステップ:"
echo "  1. inventory/hosts.yml のホスト情報を環境に合わせて編集"
echo "  2. ansible-playbook -i inventory/hosts.yml playbooks/site.yml"
echo ""
echo "詳細は docs/deployment-guide.md を参照してください。"
