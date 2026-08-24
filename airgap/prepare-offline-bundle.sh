#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/offline-resources"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

COMPOSE_VERSION="${COMPOSE_VERSION:-v2.36.1}"
PODMAN_WIN_VERSION="${PODMAN_WIN_VERSION:-5.5.0}"
WSL_VERSION="${WSL_VERSION:-2.4.13}"
PODMAN_MACHINE_TAG="${PODMAN_MACHINE_TAG:-5.5}"
SKIP_WINDOWS="${SKIP_WINDOWS:-false}"
SEVENZIP_VERSION="${SEVENZIP_VERSION:-2301}"

check_prerequisites() {
    log_info "前提条件を確認中..."
    local missing=()

    command -v podman  >/dev/null 2>&1 || missing+=("podman")
    command -v skopeo  >/dev/null 2>&1 || missing+=("skopeo")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v git     >/dev/null 2>&1 || missing+=("git")
    command -v curl    >/dev/null 2>&1 || missing+=("curl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "以下のコマンドが見つかりません: ${missing[*]}"
        exit 1
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        log_warn "pip が見つかりません。python3 -m ensurepip を実行します"
        python3 -m ensurepip --user 2>/dev/null || true
    fi

    log_info "前提条件OK"
}

create_directories() {
    log_info "ディレクトリ構造を作成中..."
    mkdir -p \
        "$BUNDLE_DIR/container-images" \
        "$BUNDLE_DIR/pip-packages" \
        "$BUNDLE_DIR/binaries" \
        "$BUNDLE_DIR/ansible-collections" \
        "$BUNDLE_DIR/training-materials"
}

build_and_save_images() {
    log_info "=== Phase 1: コンテナイメージのビルドと保存 ==="

    log_info "コントローライメージをビルド中..."
    podman build -t training-controller:latest \
        -f "$REPO_ROOT/containers/controller/Containerfile" \
        "$REPO_ROOT/containers/controller/"

    log_info "Linuxノードイメージをビルド中..."
    podman build -t training-linux-node:latest \
        -f "$REPO_ROOT/containers/linux/Containerfile" \
        "$REPO_ROOT/containers/linux/"

    log_info "コントローライメージを保存中..."
    rm -f "$BUNDLE_DIR/container-images/training-controller.tar"
    podman save -o "$BUNDLE_DIR/container-images/training-controller.tar" \
        training-controller:latest

    log_info "Linuxノードイメージを保存中..."
    rm -f "$BUNDLE_DIR/container-images/training-linux-node.tar"
    podman save -o "$BUNDLE_DIR/container-images/training-linux-node.tar" \
        training-linux-node:latest

    if [[ "$SKIP_WINDOWS" != "true" ]]; then
        log_info "Windows コンテナイメージ (dockurr/windows) をpull中..."
        if podman pull docker.io/dockurr/windows:latest 2>/dev/null; then
            log_info "Windows イメージを保存中..."
            rm -f "$BUNDLE_DIR/container-images/dockurr-windows.tar"
            podman save -o "$BUNDLE_DIR/container-images/dockurr-windows.tar" \
                docker.io/dockurr/windows:latest
        else
            log_warn "dockurr/windows のpullに失敗。Windows演習用イメージはスキップします"
        fi
    else
        log_info "SKIP_WINDOWS=true: Windows イメージをスキップ"
    fi

    log_info "Phase 1 完了: コンテナイメージ保存済み"
}

verify_dvd_iso() {
    log_info "=== Phase 2: RHEL 10 DVD ISO の確認 ==="
    log_info "RPMパッケージはリポジトリサーバーの RHEL 10 DVD ISO から提供されます"
    log_info "リポジトリサーバーに DVD ISO を配置し、repo-server-setup.yml を実行してください"
    log_info "Phase 2 完了"
}

download_binaries() {
    log_info "=== Phase 3: スタンドアロンバイナリのダウンロード ==="

    log_info "docker-compose (Linux x86_64) をダウンロード中..."
    curl -fsSL \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o "$BUNDLE_DIR/binaries/docker-compose-linux-x86_64" && \
        chmod +x "$BUNDLE_DIR/binaries/docker-compose-linux-x86_64" || {
        log_error "docker-compose Linux版ダウンロード失敗（必須）"
        exit 1
    }

    log_info "docker-compose (Windows x86_64) をダウンロード中..."
    curl -fsSL \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-windows-x86_64.exe" \
        -o "$BUNDLE_DIR/binaries/docker-compose-windows-x86_64.exe" || \
        log_warn "docker-compose Windows版ダウンロード失敗"

    log_info "sshpass 1.10 ソースをダウンロード中..."
    curl -fsSL \
        "https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz/download" \
        -o "$BUNDLE_DIR/binaries/sshpass-1.10.tar.gz" || {
        log_error "sshpass ダウンロード失敗（必須）"
        exit 1
    }

    if [[ "$SKIP_WINDOWS" != "true" ]]; then
        log_info "Podman Windows インストーラをダウンロード中..."
        curl -fsSL \
            "https://github.com/containers/podman/releases/download/v${PODMAN_WIN_VERSION}/podman-${PODMAN_WIN_VERSION}-setup.exe" \
            -o "$BUNDLE_DIR/binaries/podman-setup.exe" || \
            log_warn "Podman Windows インストーラのダウンロード失敗"

        log_info "WSL MSI インストーラをダウンロード中..."
        curl -fsSL \
            "https://github.com/microsoft/WSL/releases/download/${WSL_VERSION}/wsl.${WSL_VERSION}.0.x64.msi" \
            -o "$BUNDLE_DIR/binaries/wsl.msi" || \
            log_warn "WSL MSI ダウンロード失敗"

        log_info "Podman machine WSL イメージをダウンロード中..."
        skopeo copy --override-arch x86_64 --override-os linux \
            "docker://quay.io/podman/machine-os-wsl:${PODMAN_MACHINE_TAG}" \
            "oci-archive:${BUNDLE_DIR}/binaries/podman-machine-wsl.ociarchive" || \
            log_warn "Podman machine WSL イメージのダウンロード失敗"
    fi

    log_info "Phase 3 完了"
}

download_windows_packages() {
    log_info "=== Phase 3.5: Windows 演習用パッケージのダウンロード ==="

    if [[ "$SKIP_WINDOWS" == "true" ]]; then
        log_info "SKIP_WINDOWS=true: Windows パッケージをスキップ"
        return
    fi

    mkdir -p "$BUNDLE_DIR/packages"

    log_info "7-Zip MSI をダウンロード中..."
    curl -fsSL \
        "https://www.7-zip.org/a/7z${SEVENZIP_VERSION}-x64.msi" \
        -o "$BUNDLE_DIR/packages/7z${SEVENZIP_VERSION}-x64.msi" || \
        log_warn "7-Zip ダウンロード失敗"

    log_info "Chocolatey nupkg をダウンロード中..."
    curl -fsSL \
        "https://community.chocolatey.org/api/v2/package/chocolatey" \
        -o "$BUNDLE_DIR/packages/chocolatey.nupkg" || \
        log_warn "Chocolatey ダウンロード失敗"

    log_info "VSCode System Installer をダウンロード中..."
    curl -fsSL -L \
        "https://update.code.visualstudio.com/latest/win32-x64/stable" \
        -o "$BUNDLE_DIR/packages/VSCodeSetup-x64.exe" || \
        log_warn "VSCode ダウンロード失敗"

    log_info "VSCode Remote-SSH 拡張 (vsix) をダウンロード中..."
    curl -fsSL \
        "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-ssh/latest/vspackage" \
        -o "$BUNDLE_DIR/packages/ms-vscode-remote.remote-ssh.vsix" || \
        log_warn "Remote-SSH vsix ダウンロード失敗"

    log_info "Phase 3.5 完了"
}

download_pip_packages() {
    log_info "=== Phase 4: pip パッケージのダウンロード ==="

    log_info "pip パッケージ（ansible, pywinrm, jmespath, ansible-lint）をダウンロード中..."
    python3 -m pip download \
        -d "$BUNDLE_DIR/pip-packages/" \
        ansible pywinrm jmespath ansible-lint 2>/dev/null || \
        log_warn "一部pipパッケージのダウンロードに失敗"

    log_info "Phase 4 完了"
}

download_ansible_collections() {
    log_info "=== Phase 5: Ansible コレクションのダウンロード ==="

    local collections=(
        "ansible.windows"
        "community.windows"
        "ansible.posix"
        "community.general"
    )

    for col in "${collections[@]}"; do
        log_info "コレクション $col をダウンロード中..."
        ansible-galaxy collection download "$col" \
            -p "$BUNDLE_DIR/ansible-collections/" 2>/dev/null || \
            log_warn "コレクション $col のダウンロード失敗"
    done

    log_info "Phase 5 完了"
}

archive_training_materials() {
    log_info "=== Phase 6: 研修資材のアーカイブ ==="

    cd "$REPO_ROOT"
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git archive --format=tar.gz --prefix=ansible_training_2026/ HEAD \
            -o "$BUNDLE_DIR/training-materials/ansible_training_2026.tar.gz"
        log_info "git archive で研修資材をアーカイブしました"
    else
        tar czf "$BUNDLE_DIR/training-materials/ansible_training_2026.tar.gz" \
            --exclude='.tracecraft' \
            --exclude='airgap/offline-resources' \
            --transform='s,^,ansible_training_2026/,' \
            -C "$REPO_ROOT" .
        log_info "tar で研修資材をアーカイブしました"
    fi

    log_info "Phase 6 完了"
}

generate_checksums() {
    log_info "=== Phase 7: チェックサム生成 ==="

    cd "$BUNDLE_DIR"
    find . -type f ! -name 'checksums.sha256' -exec sha256sum {} \; > checksums.sha256
    log_info "checksums.sha256 を生成しました"

    log_info "Phase 7 完了"
}

print_summary() {
    echo ""
    log_info "=========================================="
    log_info "  オフラインバンドル作成完了"
    log_info "=========================================="
    echo ""

    log_info "バンドルの内容:"
    if command -v du >/dev/null 2>&1; then
        du -sh "$BUNDLE_DIR"/* 2>/dev/null || true
    fi
    echo ""

    log_info "次のステップ:"
    echo "  1. RHEL 10 DVD ISO を offline-resources/iso/ に配置"
    echo "  2. RHEL 10 KVM ゲストイメージを offline-resources/vm-images/ に配置"
    echo "  3. (Windows用) Windows 11 qcow2 を offline-resources/vm-images/ に配置"
    echo "  4. airgap/ ディレクトリ全体をUSBドライブ等にコピー"
    echo "  5. airgap環境のAnsibleコントローラに転送"
    echo "  6. inventory/ のホスト情報を編集"
    echo "  7. ansible-playbook playbooks/site.yml を実行"
    echo ""
}

main() {
    echo "============================================"
    echo "  Airgap オフラインバンドル作成スクリプト"
    echo "============================================"
    echo ""

    check_prerequisites
    create_directories
    build_and_save_images
    verify_dvd_iso
    download_binaries
    download_windows_packages
    download_pip_packages
    download_ansible_collections
    archive_training_materials
    generate_checksums

    if [[ -x "$SCRIPT_DIR/offline-validation.sh" ]]; then
        log_info "=== Phase 8: バンドル検証 ==="
        "$SCRIPT_DIR/offline-validation.sh" "$BUNDLE_DIR" || {
            log_error "バンドル検証に失敗しました。上記の [NG] 項目を確認してください"
            exit 1
        }
    fi

    print_summary
}

main "$@"
