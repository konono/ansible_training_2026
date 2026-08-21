#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_DIR="${1:-$SCRIPT_DIR/offline-resources}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_file() {
    local path="$1"
    local desc="$2"
    local required="${3:-true}"

    if [[ -f "$BUNDLE_DIR/$path" ]]; then
        local size
        size=$(du -sh "$BUNDLE_DIR/$path" 2>/dev/null | awk '{print $1}')
        echo -e "  ${GREEN}[OK]${NC} $desc ($size)"
        ((PASS++))
    elif [[ "$required" == "true" ]]; then
        echo -e "  ${RED}[NG]${NC} $desc — $path が見つかりません"
        ((FAIL++))
    else
        echo -e "  ${YELLOW}[--]${NC} $desc — $path (オプション、なくても動作可)"
        ((WARN++))
    fi
}

check_dir_notempty() {
    local path="$1"
    local desc="$2"
    local required="${3:-true}"

    if [[ -d "$BUNDLE_DIR/$path" ]] && [[ -n "$(ls -A "$BUNDLE_DIR/$path" 2>/dev/null)" ]]; then
        local count
        count=$(find "$BUNDLE_DIR/$path" -maxdepth 1 -type f | wc -l)
        local size
        size=$(du -sh "$BUNDLE_DIR/$path" 2>/dev/null | awk '{print $1}')
        echo -e "  ${GREEN}[OK]${NC} $desc (${count}ファイル, $size)"
        ((PASS++))
    elif [[ "$required" == "true" ]]; then
        echo -e "  ${RED}[NG]${NC} $desc — $path が空または存在しません"
        ((FAIL++))
    else
        echo -e "  ${YELLOW}[--]${NC} $desc — $path (オプション)"
        ((WARN++))
    fi
}

echo "============================================"
echo "  Airgap オフラインバンドル検証"
echo "============================================"
echo ""
echo "検証対象: $BUNDLE_DIR"
echo ""

# --- コンテナイメージ ---
echo "■ コンテナイメージ (container-images/)"
check_file "container-images/training-controller.tar" "controller イメージ"
check_file "container-images/training-linux-node.tar"  "linux-node イメージ"
check_file "container-images/dockurr-windows.tar"      "dockurr/windows イメージ" "false"
echo ""

# --- バイナリ ---
echo "■ バイナリ (binaries/)"
check_file "binaries/docker-compose-linux-x86_64"         "docker-compose (Linux)"
check_file "binaries/sshpass-1.10.tar.gz"                 "sshpass ソース"
check_file "binaries/docker-compose-windows-x86_64.exe"   "docker-compose (Windows)"  "false"
check_file "binaries/podman-setup.exe"                    "Podman インストーラ"        "false"
check_file "binaries/wsl.msi"                             "WSL MSI"                   "false"
check_file "binaries/podman-machine-wsl.ociarchive"       "Podman machine イメージ"   "false"
echo ""

# --- Windows 演習用パッケージ ---
echo "■ Windows 演習用パッケージ (packages/)"
if compgen -G "$BUNDLE_DIR/packages/7z*-x64.msi" > /dev/null 2>&1; then
    local_7z=$(ls "$BUNDLE_DIR/packages"/7z*-x64.msi 2>/dev/null | head -1)
    size=$(du -sh "$local_7z" 2>/dev/null | awk '{print $1}')
    echo -e "  ${GREEN}[OK]${NC} 7-Zip MSI ($size)"
    ((PASS++)) || true
else
    echo -e "  ${YELLOW}[--]${NC} 7-Zip MSI — packages/7z*-x64.msi (オプション、なくても動作可)"
    ((WARN++)) || true
fi
check_file "packages/chocolatey.nupkg" "Chocolatey nupkg"    "false"
echo ""

# --- DVD ISO ---
echo "■ RHEL 10 DVD ISO (iso/)"
if compgen -G "$BUNDLE_DIR/iso/rhel-*.iso" > /dev/null 2>&1; then
    local_iso=$(ls "$BUNDLE_DIR/iso/rhel-"*.iso 2>/dev/null | head -1)
    size=$(du -sh "$local_iso" 2>/dev/null | awk '{print $1}')
    echo -e "  ${GREEN}[OK]${NC} DVD ISO ($size)"
    ((PASS++))

    # BaseOS/AppStream の存在を簡易チェック（ISO マウント不要、サイズで判断）
    iso_size=$(stat --format=%s "$local_iso" 2>/dev/null || echo 0)
    if (( iso_size < 5000000000 )); then
        echo -e "  ${YELLOW}[注意]${NC} ISO サイズが 5GB 未満です。Boot ISO ではなく DVD ISO が必要です"
        ((WARN++))
    fi
else
    echo -e "  ${RED}[NG]${NC} DVD ISO — iso/rhel-*.iso が見つかりません"
    ((FAIL++))
fi
echo ""

# --- pip パッケージ ---
echo "■ pip パッケージ (pip-packages/)"
check_dir_notempty "pip-packages" "pip パッケージ群"
# 主要パッケージの個別チェック
for pkg in ansible ansible_core pywinrm jmespath ansible_lint; do
    if compgen -G "$BUNDLE_DIR/pip-packages/${pkg}-"* > /dev/null 2>&1 || \
       compgen -G "$BUNDLE_DIR/pip-packages/${pkg}_"* > /dev/null 2>&1; then
        :
    else
        echo -e "  ${YELLOW}[注意]${NC} $pkg が pip-packages/ に見つかりません"
        ((WARN++))
    fi
done
echo ""

# --- Ansible コレクション ---
echo "■ Ansible コレクション (ansible-collections/)"
check_dir_notempty "ansible-collections" "Ansible コレクション群"
for col in ansible-windows ansible-posix community-general community-windows; do
    if compgen -G "$BUNDLE_DIR/ansible-collections/${col}-"* > /dev/null 2>&1; then
        :
    else
        echo -e "  ${YELLOW}[注意]${NC} $col が ansible-collections/ に見つかりません"
        ((WARN++))
    fi
done
echo ""

# --- 研修資材 ---
echo "■ 研修資材 (training-materials/)"
check_file "training-materials/ansible_training_2026.tar.gz" "研修資材アーカイブ"
echo ""

# --- チェックサム ---
echo "■ チェックサム"
check_file "checksums.sha256" "チェックサムファイル"
if [[ -f "$BUNDLE_DIR/checksums.sha256" ]]; then
    echo -n "  検証中... "
    cd "$BUNDLE_DIR"
    if sha256sum -c checksums.sha256 > /dev/null 2>&1; then
        echo -e "${GREEN}全ファイル一致${NC}"
    else
        failed=$(sha256sum -c checksums.sha256 2>&1 | grep FAILED | wc -l)
        echo -e "${RED}${failed}ファイルが不一致${NC}"
        sha256sum -c checksums.sha256 2>&1 | grep FAILED | head -5
        ((FAIL++))
    fi
fi
echo ""

# --- VM イメージ（開発テスト用、オプション）---
echo "■ VM イメージ (vm-images/) — 開発テスト用"
check_file "vm-images/rhel-10.2-x86_64-kvm.qcow2" "RHEL KVM ゲストイメージ"    "false"
check_file "vm-images/windows-11-25h2.qcow2"       "Windows 11 qcow2"           "false"
echo ""

# --- サマリ ---
echo "============================================"
echo "  検証結果"
echo "============================================"
echo ""
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}OK${NC}:    $PASS / $TOTAL"
echo -e "  ${RED}NG${NC}:    $FAIL / $TOTAL"
echo -e "  ${YELLOW}SKIP${NC}:  $WARN / $TOTAL (オプション項目)"
echo ""

if (( FAIL > 0 )); then
    echo -e "  ${RED}バンドルに不足があります。上記の [NG] 項目を確認してください。${NC}"
    exit 1
else
    echo -e "  ${GREEN}必須項目は全て揃っています。${NC}"
    if (( WARN > 0 )); then
        echo -e "  ${YELLOW}オプション項目に不足があります（Windows 不要なら問題ありません）。${NC}"
    fi
    exit 0
fi
