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

# --- モード判定 ---
# --online / AIRGAP_MODE=false で非airgap（インターネット接続あり）モードになる。
AIRGAP_MODE="${AIRGAP_MODE:-true}"
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --online)  AIRGAP_MODE=false ;;
        --airgap)  AIRGAP_MODE=true ;;
        -h|--help)
            echo "使用方法: $0 [--online|--airgap] [/path/to/rhel-x.y-dvd.iso]"
            echo ""
            echo "  --airgap  (既定) 閉域環境。DVD ISO とオフラインバンドルから構築する。"
            echo "  --online        インターネット接続あり。RHSM/CDN・PyPI・Galaxy から取得する。"
            exit 0
            ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

echo "============================================"
if [[ "$AIRGAP_MODE" == "true" ]]; then
    echo "  Airgap コントローラノード セットアップ"
else
    echo "  コントローラノード セットアップ（非airgap）"
fi
echo "============================================"
echo ""
if [[ "$AIRGAP_MODE" == "true" ]]; then
    echo "このスクリプトは ansible-playbook を実行するマシンを"
    echo "airgap 環境でセットアップします。"
else
    echo "このスクリプトは ansible-playbook を実行するマシンを"
    echo "インターネット接続のある環境でセットアップします。"
    echo "DVD ISO とオフラインバンドルは不要です。"
fi
echo ""

if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    if ! sudo -n true 2>/dev/null; then
        log_warn "sudo のパスワードを求められる場合があります"
    fi
    SUDO="sudo"
fi

# sudo の secure_path に /usr/local/bin を追加
CURRENT_SECURE_PATH=$($SUDO sed -n 's/^[[:space:]]*Defaults[[:space:]]*secure_path[[:space:]]*=[[:space:]]*//p' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | tail -1)
if [[ -n "$CURRENT_SECURE_PATH" ]] && echo "$CURRENT_SECURE_PATH" | grep -q '/usr/local/bin'; then
    : # 既に含まれている
elif [[ -n "$CURRENT_SECURE_PATH" ]]; then
    log_info "sudo の secure_path に /usr/local/bin を追加します"
    echo "Defaults secure_path = /usr/local/bin:$CURRENT_SECURE_PATH" | $SUDO tee /etc/sudoers.d/local-path > /dev/null
    $SUDO chmod 440 /etc/sudoers.d/local-path
else
    log_info "sudo の secure_path に /usr/local/bin を追加します"
    echo 'Defaults secure_path = /usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin' | $SUDO tee /etc/sudoers.d/local-path > /dev/null
    $SUDO chmod 440 /etc/sudoers.d/local-path
fi

# --- Step 1: DVD ISO からローカルリポジトリを設定 ---
if [[ "$AIRGAP_MODE" != "true" ]]; then
    log_info "Step 1: 既存の dnf リポジトリを使用（ISO セットアップをスキップ）"
    if ! dnf repolist --enabled 2>/dev/null | tail -n +2 | grep -q .; then
        log_error "有効な dnf リポジトリがありません。"
        log_error "subscription-manager register などでリポジトリを有効化してください。"
        exit 1
    fi
    log_info "有効なリポジトリ: $(dnf repolist --enabled 2>/dev/null | tail -n +2 | wc -l) 件"
    echo ""
else
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
    $SUDO mkdir -p /mnt/cdrom
    $SUDO mount -o loop,ro "$ISO_PATH" /mnt/cdrom 2>/dev/null || {
        log_error "ISO マウントに失敗しました（sudo 権限が必要です）"
        exit 1
    }
    log_info "ISO をマウントしました"
fi

if [[ ! -d /mnt/cdrom/BaseOS ]]; then
    log_error "ISO に BaseOS ディレクトリがありません。DVD ISO（Boot ISO ではない）を使用してください"
    exit 1
fi

# UBI リポジトリ無効化 + ローカルリポジトリ設定
$SUDO sed -i 's/enabled *= *1/enabled = 0/g' /etc/yum.repos.d/ubi.repo 2>/dev/null || true
$SUDO subscription-manager config --rhsm.manage_repos=0 2>/dev/null || true

$SUDO tee /etc/yum.repos.d/local-baseos.repo > /dev/null << EOF
[local-baseos]
name=Local BaseOS (DVD ISO)
baseurl=file:///mnt/cdrom/BaseOS
enabled=1
gpgcheck=0
EOF

$SUDO tee /etc/yum.repos.d/local-appstream.repo > /dev/null << EOF
[local-appstream]
name=Local AppStream (DVD ISO)
baseurl=file:///mnt/cdrom/AppStream
enabled=1
gpgcheck=0
EOF

$SUDO dnf clean all >/dev/null 2>&1
log_info "ローカルリポジトリ設定完了"
echo ""
fi

# --- Step 2: 前提パッケージのインストール ---
log_info "Step 2: 前提パッケージのインストール"

# RHEL 9 では python3.12 を使用（pip パッケージの互換性のため）
PYTHON_CMD="python3"
if [[ "$(python3 --version 2>&1)" == *"3.9"* ]] || [[ "$(python3 --version 2>&1)" == *"3.11"* ]]; then
    log_info "Python 3.12 をインストールします（pip パッケージ互換性のため）"
    $SUDO dnf install -y python3.12 python3.12-pip 2>&1 | tail -3
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
    $SUDO dnf install -y "${PKGS_TO_INSTALL[@]}" 2>&1 | tail -3
else
    log_info "追加パッケージは全てインストール済みです"
fi

$PYTHON_CMD --version
$PYTHON_CMD -m pip --version
echo ""

# --- Step 3: ansible-core のインストール ---
log_info "Step 3: ansible-core のインストール"

# pip がインストールするスクリプトの場所を PATH に追加
PIP_SCRIPT_DIR=$($PYTHON_CMD -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>/dev/null || echo "/usr/local/bin")
if [[ ":$PATH:" != *":$PIP_SCRIPT_DIR:"* ]]; then
    export PATH="$PIP_SCRIPT_DIR:$PATH"
    log_info "PATH に $PIP_SCRIPT_DIR を追加しました"
fi

if command -v ansible >/dev/null 2>&1; then
    log_info "ansible は既にインストール済みです"
    ansible --version | head -1
else
    if [[ "$AIRGAP_MODE" != "true" ]]; then
        log_info "PyPI からインストールします"
        if ! $SUDO $PYTHON_CMD -m pip install ansible-core 2>&1 | tail -3; then
            log_error "ansible-core のインストールに失敗しました"
            exit 1
        fi
    elif [[ -d "$BUNDLE_DIR/pip-packages" ]]; then
        log_info "バンドルの pip パッケージからインストールします"
        if ! $SUDO $PYTHON_CMD -m pip install --no-index --find-links="$BUNDLE_DIR/pip-packages/" \
            ansible-core 2>&1; then
            log_error "ansible-core のインストールに失敗しました"
            log_error "pip パッケージが不足している可能性があります。prepare-offline-bundle.sh を再実行してください"
            exit 1
        fi
    else
        log_error "pip-packages/ が見つかりません。バンドルを確認してください"
        exit 1
    fi

    hash -r
    if ! command -v ansible >/dev/null 2>&1; then
        log_error "ansible コマンドが見つかりません"
        log_error "pip のインストール先: $PIP_SCRIPT_DIR"
        log_error "現在の PATH: $PATH"
        log_error "ansible 関連ファイル:"
        find /usr/local/bin /usr/bin "$PIP_SCRIPT_DIR" -name "ansible*" 2>/dev/null || true
        exit 1
    fi
    log_info "ansible インストール完了: $(ansible --version | head -1)"
fi
echo ""

# --- Step 4: sshpass のインストール ---
log_info "Step 4: sshpass のインストール"
if command -v sshpass >/dev/null 2>&1; then
    log_info "sshpass は既にインストール済みです"
    sshpass -V 2>&1 | head -1
elif [[ "$AIRGAP_MODE" != "true" ]]; then
    log_info "dnf でインストールします"
    if $SUDO dnf install -y sshpass 2>&1 | tail -3; then
        log_info "sshpass インストール完了"
    else
        log_warn "sshpass の dnf インストールに失敗しました（EPEL が必要な場合があります）"
        log_warn "パスワード認証を使う場合は手動でインストールしてください"
    fi
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
        $SUDO make install 2>&1 | tail -1
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
if [[ "$AIRGAP_MODE" != "true" ]]; then
    log_info "Ansible Galaxy からインストールします"
    if ! ansible-galaxy collection install -r "$SCRIPT_DIR/requirements.yml" 2>&1 | tail -5; then
        log_error "コレクションのインストールに失敗しました"
        exit 1
    fi
    log_info "コレクションのインストール完了"
elif [[ -d "$COLLECTIONS_DIR" ]]; then
    for col in ansible-posix ansible-windows community-general community-windows; do
        tarball=$(ls "$COLLECTIONS_DIR"/${col}-*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$tarball" ]]; then
            if ansible-galaxy collection list 2>/dev/null | grep -q "${col//-/.}"; then
                log_info "$col: インストール済み"
            else
                if ! ansible-galaxy collection install "$tarball" --force 2>&1; then
                    log_error "$col: インストール失敗"
                    exit 1
                fi
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
SETUP_OK=true

echo ""
log_info "=== セットアップ結果 ==="
echo ""

if command -v ansible >/dev/null 2>&1; then
    echo "  ansible:      $(ansible --version | head -1)"
    echo "  ansible-core: $($PYTHON_CMD -c 'import ansible; print(ansible.__version__)' 2>/dev/null)"
    echo "  パス:         $(command -v ansible)"
else
    log_error "  ansible: NOT FOUND"
    SETUP_OK=false
fi

echo ""
echo "コレクション:"
ansible-galaxy collection list 2>/dev/null | grep -E 'ansible\.(posix|windows)|community\.(general|windows)' | head -10
echo ""

if [[ "$SETUP_OK" == "true" ]]; then
    log_info "=== セットアップ完了 ==="
    echo ""
    echo "次のステップ:"
    echo "  1. inventory/hosts.yml を環境に合わせて編集（IP アドレス・ユーザー・パスワード）"
    echo "     vi inventory/hosts.yml"
    echo ""
    echo "  2. Playbook を順番に実行:"
    echo "     cd $(pwd)"
    echo '     SSH_ARGS='"'"'-e ansible_ssh_common_args="-o StrictHostKeyChecking=no"'"'"''
    if [[ "$AIRGAP_MODE" == "true" ]]; then
        echo '     ansible-playbook -i inventory/hosts.yml playbooks/distribute-resources.yml $SSH_ARGS'
        echo '     ansible-playbook -i inventory/hosts.yml playbooks/repo-server-setup.yml $SSH_ARGS'
        echo '     ansible-playbook -i inventory/hosts.yml playbooks/rhel-setup.yml $SSH_ARGS'
        echo ""
        echo "詳細は docs/deployment-guide.md を参照してください。"
    else
        echo '     ansible-playbook -i inventory/hosts-online.yml playbooks/distribute-resources.yml $SSH_ARGS'
        echo '     ansible-playbook -i inventory/hosts-online.yml playbooks/rhel-setup.yml $SSH_ARGS'
        echo ""
        echo "  （非airgap では repo-server-setup.yml は不要です）"
        echo ""
        echo "詳細は docs/online-deployment-guide.md を参照してください。"
    fi
else
    log_error "=== セットアップに問題があります ==="
    echo ""
    echo "上記のエラーを確認してください。"
    echo "PATH: $PATH"
    exit 1
fi
