#!/bin/bash
# トレーニング環境 管理ツール（管理者向け）
#
# 使い方:
#   ./manage-training.sh list                     全環境の一覧
#   ./manage-training.sh info <username|user_id>  特定ユーザーの環境詳細
#   ./manage-training.sh destroy <username|user_id>  環境の削除
#   ./manage-training.sh health                   ヘルスチェック（孤立コンテナ等）
#   ./manage-training.sh disk                     ディスク使用量
#   ./manage-training.sh cleanup                  孤立リソースの自動削除
#
# 受講者が自分の環境を確認するには:
#   ./deploy-training.sh status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOCATE_SCRIPT="$SCRIPT_DIR/scripts/allocate.py"
TRAINING_BASE="/opt/training"
ALLOCATIONS_FILE="$TRAINING_BASE/allocations.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- ユーティリティ ---

_get_allocations_json() {
    python3 "$ALLOCATE_SCRIPT" --action status 2>/dev/null
}

_container_status() {
    local user_id="$1"
    local prefix="user${user_id}_"
    local running
    running=$(podman ps --format '{{.Names}}' 2>/dev/null | grep "^${prefix}" | wc -l)
    echo "$running"
}

_container_details() {
    local user_id="$1"
    local prefix="user${user_id}_"
    podman ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep "^${prefix}" || true
}

_dir_size() {
    local user_id="$1"
    local dir="$TRAINING_BASE/user${user_id}"
    if [[ -d "$dir" ]]; then
        du -sh "$dir" 2>/dev/null | awk '{print $1}'
    else
        echo "-"
    fi
}

_resolve_target() {
    local target="$1"
    local json
    json=$(_get_allocations_json)

    if [[ "$target" =~ ^[0-9]+$ ]]; then
        echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['user_id'] == $target and a['status'] != 'released':
        print(json.dumps(a))
        sys.exit(0)
print('')
" 2>/dev/null
    else
        echo "$json" | python3 -c "
import json, sys
target = '$target'
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['status'] == 'released':
        continue
    if a.get('username') == target:
        print(json.dumps(a))
        sys.exit(0)
    hostname = a.get('client_hostname', '')
    if hostname == target:
        print(json.dumps(a))
        sys.exit(0)
print('')
" 2>/dev/null
    fi
}

_show_connection_info() {
    local alloc_json="$1"
    local user_id port
    user_id=$(echo "$alloc_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_id'])")
    port=$(echo "$alloc_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['ssh_port'])")
    local training_ip
    training_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    training_ip="${training_ip:-192.168.100.10}"

    echo -e "  ${BOLD}接続方法:${RESET}"
    echo -e "    ssh -p ${CYAN}${port}${RESET} root@${training_ip}"
    echo "    パスワード: password"
}

# --- status: 全体概要 ---

do_status() {
    local json
    json=$(_get_allocations_json)

    local active_count total_containers
    active_count=$(echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len([a for a in data['allocations'] if a['status'] != 'released']))
" 2>/dev/null)
    total_containers=$(podman ps --format '{{.Names}}' 2>/dev/null | wc -l)

    echo -e "${BOLD}=== トレーニング環境 概要 ===${RESET}"
    echo ""
    echo -e "  アクティブ環境: ${CYAN}${active_count}${RESET} 件"
    echo -e "  稼働コンテナ:   ${CYAN}${total_containers}${RESET} 個"
    echo -e "  ディスク使用:   $(du -sh "$TRAINING_BASE" 2>/dev/null | awk '{print $1}' || echo '-')"
    echo ""

    if [[ "$active_count" -gt 0 ]]; then
        echo "  詳細は ./manage-training.sh list を実行してください。"
    fi
    echo ""
}

# --- list: 全環境の一覧 ---

do_list() {
    local json
    json=$(_get_allocations_json)

    local count
    count=$(echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len([a for a in data['allocations'] if a['status'] != 'released']))
" 2>/dev/null)

    if [[ "$count" == "0" ]]; then
        echo "デプロイ済みの環境はありません。"
        return
    fi

    echo -e "${BOLD}=== デプロイ済み環境一覧 ===${RESET}"
    echo ""
    printf "  ${BOLD}%-4s  %-18s %-14s %-6s  %-5s  %-8s  %s${RESET}\n" \
        "ID" "ユーザー" "表示名" "PORT" "CTR" "DISK" "ステータス"
    printf "  %-4s  %-18s %-14s %-6s  %-5s  %-8s  %s\n" \
        "----" "------------------" "--------------" "------" "-----" "--------" "----------"

    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in sorted(data['allocations'], key=lambda x: x['user_id']):
    if a['status'] == 'released':
        continue
    uid = a['user_id']
    username = a.get('username', '') or a.get('client_ip', '-')
    hostname = a.get('client_hostname', '-')
    port = a.get('ssh_port', '-')
    status = a.get('status', '-')
    is_test = ' (test)' if a.get('client_ip','').startswith('198.51.100.') else ''
    print(f'{uid}|{username}|{hostname}|{port}|{status}{is_test}')
" 2>/dev/null | while IFS='|' read -r uid username hostname port status; do
        local containers disk
        containers=$(_container_status "$uid")
        disk=$(_dir_size "$uid")
        local status_display
        case "$status" in
            active*)   status_display="${GREEN}${status}${RESET}" ;;
            allocated) status_display="${YELLOW}${status}${RESET}" ;;
            *)         status_display="${RED}${status}${RESET}" ;;
        esac
        # コンテナ数が 0 でステータスが active なら警告
        if [[ "$containers" == "0" && "$status" == active* ]]; then
            containers="${RED}0${RESET}"
        else
            containers="${GREEN}${containers}${RESET}"
        fi
        printf "  %-4s  %-18s %-14s %-6s  " "$uid" "$username" "$hostname" "$port"
        echo -ne "$containers"
        printf "      %-8s  " "$disk"
        echo -e "$status_display"
    done
    echo ""
}

# --- info: 特定環境の詳細 ---

do_info() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        echo "使い方: ./manage-training.sh info <username|user_id>"
        exit 1
    fi

    local alloc
    alloc=$(_resolve_target "$target")

    if [[ -z "$alloc" ]]; then
        echo "エラー: '$target' に対応するアクティブな環境が見つかりません。"
        exit 1
    fi

    local user_id
    user_id=$(echo "$alloc" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_id'])")

    echo -e "${BOLD}=== 環境詳細: user${user_id} ===${RESET}"
    echo ""

    echo "$alloc" | python3 -c "
import json, sys
a = json.load(sys.stdin)
print(f'  User ID:       {a[\"user_id\"]}')
print(f'  ユーザー:      {a.get(\"username\", \"-\") or \"-\"}')
print(f'  表示名:        {a.get(\"client_hostname\", \"-\")}')
print(f'  ステータス:    {a[\"status\"]}')
print(f'  SSH ポート:    {a[\"ssh_port\"]}')
print(f'  サブネット:    {a[\"subnet\"]}')
print(f'  割当日時:      {a.get(\"allocated_at\", \"-\")}')
if a.get('activated_at'):
    print(f'  開始日時:      {a[\"activated_at\"]}')
print(f'  クライアント:  {a.get(\"client_ip\", \"-\")}')
print()
c = a.get('containers', {})
print('  コンテナ IP:')
for name, ip in c.items():
    print(f'    {name:12s}  {ip}')
" 2>/dev/null

    echo ""
    _show_connection_info "$alloc"

    echo ""
    echo -e "  ${BOLD}コンテナ状態:${RESET}"
    local containers
    containers=$(_container_details "$user_id")
    if [[ -n "$containers" ]]; then
        echo "$containers" | while IFS=$'\t' read -r name st; do
            local short_name="${name#user${user_id}_}"
            if [[ "$st" == Up* ]]; then
                echo -e "    ${GREEN}●${RESET} ${short_name}  ${st}"
            else
                echo -e "    ${RED}●${RESET} ${short_name}  ${st}"
            fi
        done
    else
        echo -e "    ${RED}コンテナが見つかりません${RESET}"
    fi

    echo ""
    local disk
    disk=$(_dir_size "$user_id")
    echo "  ディスク使用:  $disk"
    echo ""
}

# --- destroy: 環境の削除 ---

do_destroy() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        echo "使い方: ./manage-training.sh destroy <username|user_id>"
        exit 1
    fi

    local alloc
    alloc=$(_resolve_target "$target")

    if [[ -z "$alloc" ]]; then
        echo "エラー: '$target' に対応するアクティブな環境が見つかりません。"
        echo ""
        echo "現在の環境一覧:"
        do_list
        exit 1
    fi

    local user_id username hostname
    user_id=$(echo "$alloc" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_id'])")
    username=$(echo "$alloc" | python3 -c "import json,sys; print(json.load(sys.stdin).get('username',''))")
    hostname=$(echo "$alloc" | python3 -c "import json,sys; print(json.load(sys.stdin).get('client_hostname',''))")

    echo -e "${BOLD}削除対象:${RESET}"
    echo "  User ID:   $user_id"
    echo "  ユーザー:  ${username:-'-'}"
    echo "  表示名:    ${hostname:-'-'}"
    echo ""

    read -rp "削除しますか？ [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "キャンセルしました。"
        exit 0
    fi

    echo ""

    if [[ -n "$username" ]]; then
        cd "$SCRIPT_DIR"
        "$SCRIPT_DIR/deploy-training.sh" destroy --username "$username"
    else
        local client_ip
        client_ip=$(echo "$alloc" | python3 -c "import json,sys; print(json.load(sys.stdin).get('client_ip',''))")
        if [[ -n "$client_ip" ]]; then
            cd "$SCRIPT_DIR"
            export ALLOW_TEST_IP=1
            "$SCRIPT_DIR/deploy-training.sh" destroy --ip "$client_ip"
        else
            cd "$SCRIPT_DIR"
            "$SCRIPT_DIR/deploy-training.sh" destroy --user "$user_id"
        fi
    fi
}

# --- health: ヘルスチェック ---

do_health() {
    echo -e "${BOLD}=== ヘルスチェック ===${RESET}"
    echo ""
    local issues=0

    # 1. 孤立コンテナの検出（allocation が released だがコンテナが残っている）
    echo -e "${BOLD}[1] 孤立コンテナの検出${RESET}"
    local json
    json=$(_get_allocations_json)

    local released_ids
    released_ids=$(echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['status'] == 'released':
        print(a['user_id'])
" 2>/dev/null)

    local orphan_found=false
    for uid in $released_ids; do
        local running
        running=$(_container_status "$uid")
        if [[ "$running" -gt 0 ]]; then
            echo -e "  ${RED}!${RESET} user${uid}: 割当解除済みだがコンテナが ${running} 個稼働中"
            orphan_found=true
            issues=$((issues + 1))
        fi
    done

    # allocation にないがコンテナが存在するケース
    local all_container_ids
    all_container_ids=$(podman ps --format '{{.Names}}' 2>/dev/null \
        | grep -oP '^user\K[0-9]+' | sort -un || true)
    local known_ids
    known_ids=$(echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    print(a['user_id'])
" 2>/dev/null)

    for cid in $all_container_ids; do
        if ! echo "$known_ids" | grep -qx "$cid"; then
            local running
            running=$(_container_status "$cid")
            echo -e "  ${RED}!${RESET} user${cid}: allocation に記録がないコンテナが ${running} 個存在"
            orphan_found=true
            issues=$((issues + 1))
        fi
    done

    if [[ "$orphan_found" == false ]]; then
        echo -e "  ${GREEN}✓${RESET} 孤立コンテナなし"
    fi
    echo ""

    # 2. コンテナ停止の検出（active だがコンテナが動いていない）
    echo -e "${BOLD}[2] 停止コンテナの検出${RESET}"
    local stopped_found=false
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['status'] in ('active', 'allocated'):
        print(a['user_id'])
" 2>/dev/null | while read -r uid; do
        local running
        running=$(_container_status "$uid")
        if [[ "$running" -lt 5 ]]; then
            echo -e "  ${YELLOW}!${RESET} user${uid}: 期待 5 コンテナだが ${running} 個のみ稼働"
            stopped_found=true
            issues=$((issues + 1))
        fi
    done

    if [[ "$stopped_found" == false ]]; then
        local active_count
        active_count=$(echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len([a for a in data['allocations'] if a['status'] in ('active', 'allocated')]))
" 2>/dev/null)
        if [[ "$active_count" == "0" ]]; then
            echo -e "  ${GREEN}✓${RESET} アクティブ環境なし"
        else
            echo -e "  ${GREEN}✓${RESET} 全コンテナ正常稼働"
        fi
    fi
    echo ""

    # 3. 孤立ディレクトリの検出
    echo -e "${BOLD}[3] 孤立ディレクトリの検出${RESET}"
    local orphan_dir_found=false
    if [[ -d "$TRAINING_BASE" ]]; then
        for dir in "$TRAINING_BASE"/user*/; do
            [[ -d "$dir" ]] || continue
            local dirname
            dirname=$(basename "$dir")
            local uid="${dirname#user}"
            if ! echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['user_id'] == $uid and a['status'] != 'released':
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
                local size
                size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
                echo -e "  ${YELLOW}!${RESET} ${dir}: 割当なしだがディレクトリ存在 ($size)"
                orphan_dir_found=true
                issues=$((issues + 1))
            fi
        done
    fi

    if [[ "$orphan_dir_found" == false ]]; then
        echo -e "  ${GREEN}✓${RESET} 孤立ディレクトリなし"
    fi
    echo ""

    # 4. ディスク残量
    echo -e "${BOLD}[4] ディスク残量${RESET}"
    local avail_pct
    avail_pct=$(df --output=pcent / 2>/dev/null | tail -1 | tr -d ' %')
    local avail_human
    avail_human=$(df -h --output=avail / 2>/dev/null | tail -1 | tr -d ' ')
    if [[ "$avail_pct" -gt 90 ]]; then
        echo -e "  ${RED}!${RESET} ディスク使用率 ${avail_pct}%（残り ${avail_human}）— 危険"
        issues=$((issues + 1))
    elif [[ "$avail_pct" -gt 80 ]]; then
        echo -e "  ${YELLOW}!${RESET} ディスク使用率 ${avail_pct}%（残り ${avail_human}）— 注意"
        issues=$((issues + 1))
    else
        echo -e "  ${GREEN}✓${RESET} ディスク使用率 ${avail_pct}%（残り ${avail_human}）"
    fi
    echo ""

    if [[ "$issues" -gt 0 ]]; then
        echo -e "${YELLOW}問題が ${issues} 件見つかりました。${RESET}"
        echo "孤立コンテナの削除: ./manage-training.sh cleanup"
    else
        echo -e "${GREEN}問題は見つかりませんでした。${RESET}"
    fi
    echo ""
}

# --- disk: ディスク使用量 ---

do_disk() {
    echo -e "${BOLD}=== ディスク使用量 ===${RESET}"
    echo ""

    echo -e "  ${BOLD}全体:${RESET}"
    df -h / 2>/dev/null | awk 'NR==2{printf "    使用: %s / %s （%s 空き）\n", $3, $2, $4}'
    echo ""

    echo -e "  ${BOLD}トレーニング環境:${RESET}"
    if [[ -d "$TRAINING_BASE" ]]; then
        echo "    $(du -sh "$TRAINING_BASE" 2>/dev/null | awk '{print $1}')  $TRAINING_BASE（合計）"
        echo ""
        local has_dirs=false
        for dir in "$TRAINING_BASE"/user*/; do
            [[ -d "$dir" ]] || continue
            has_dirs=true
            local dirname size
            dirname=$(basename "$dir")
            size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
            printf "    %-8s  %s\n" "$size" "$dirname"
        done
        if [[ "$has_dirs" == false ]]; then
            echo "    ユーザーディレクトリなし"
        fi
    else
        echo "    $TRAINING_BASE は存在しません"
    fi

    echo ""
    echo -e "  ${BOLD}コンテナイメージ:${RESET}"
    podman images --format '    {{.Size}}  {{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep -E 'training|ansible' || echo "    トレーニング用イメージなし"

    echo ""
}

# --- cleanup: 孤立リソースの削除 ---

do_cleanup() {
    echo -e "${BOLD}=== クリーンアップ ===${RESET}"
    echo ""

    local json
    json=$(_get_allocations_json)
    local cleaned=0

    # 孤立コンテナの停止・削除
    local released_ids
    released_ids=$(echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['status'] == 'released':
        print(a['user_id'])
" 2>/dev/null)

    for uid in $released_ids; do
        local running
        running=$(_container_status "$uid")
        if [[ "$running" -gt 0 ]]; then
            echo -e "  user${uid}: 孤立コンテナを停止・削除中..."
            local compose_file="$TRAINING_BASE/user${uid}/ansible_training_2026/containers/docker-compose.yml"
            if [[ -f "$compose_file" ]]; then
                DOCKER_HOST="unix:///run/podman/podman.sock" \
                    /usr/local/bin/docker-compose -p "user${uid}" down --remove-orphans 2>/dev/null || true
            fi
            for c in "user${uid}_controller" "user${uid}_node1" "user${uid}_node2" "user${uid}_node3" "user${uid}_lb"; do
                podman stop "$c" 2>/dev/null || true
                podman rm -f "$c" 2>/dev/null || true
            done
            podman network rm "user${uid}_ansible_net" 2>/dev/null || true
            echo -e "  ${GREEN}✓${RESET} user${uid}: コンテナ削除完了"
            cleaned=$((cleaned + 1))
        fi
    done

    # allocation にないコンテナの削除
    local all_container_ids
    all_container_ids=$(podman ps --format '{{.Names}}' 2>/dev/null \
        | grep -oP '^user\K[0-9]+' | sort -un || true)
    local known_ids
    known_ids=$(echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    print(a['user_id'])
" 2>/dev/null)

    for cid in $all_container_ids; do
        if ! echo "$known_ids" | grep -qx "$cid"; then
            echo -e "  user${cid}: 記録のないコンテナを削除中..."
            for c in "user${cid}_controller" "user${cid}_node1" "user${cid}_node2" "user${cid}_node3" "user${cid}_lb"; do
                podman stop "$c" 2>/dev/null || true
                podman rm -f "$c" 2>/dev/null || true
            done
            podman network rm "user${cid}_ansible_net" 2>/dev/null || true
            echo -e "  ${GREEN}✓${RESET} user${cid}: コンテナ削除完了"
            cleaned=$((cleaned + 1))
        fi
    done

    # 孤立ディレクトリの削除
    if [[ -d "$TRAINING_BASE" ]]; then
        for dir in "$TRAINING_BASE"/user*/; do
            [[ -d "$dir" ]] || continue
            local dirname uid
            dirname=$(basename "$dir")
            uid="${dirname#user}"
            if ! echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['user_id'] == $uid and a['status'] != 'released':
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
                echo -e "  ${dirname}: 孤立ディレクトリを削除中..."
                rm -rf "$dir"
                echo -e "  ${GREEN}✓${RESET} ${dirname}: 削除完了"
                cleaned=$((cleaned + 1))
            fi
        done
    fi

    echo ""
    if [[ "$cleaned" -gt 0 ]]; then
        echo -e "${GREEN}${cleaned} 件のリソースをクリーンアップしました。${RESET}"
    else
        echo "クリーンアップ対象はありませんでした。"
    fi
    echo ""
}

# --- ヘルプ ---

show_usage() {
    cat << 'USAGE'
トレーニング環境 管理ツール

使い方:
  ./manage-training.sh <サブコマンド> [引数]

サブコマンド:
  status                        環境の状態を確認（受講者: 自分の環境、root: 概要）
  list                          全環境の一覧（ユーザー・ポート・コンテナ数・ディスク）
  info <username|user_id>       特定環境の詳細情報
  destroy <username|user_id>    環境を削除（確認あり）
  health                        ヘルスチェック（孤立コンテナ・停止検出・ディスク）
  disk                          ディスク使用量の一覧
  cleanup                       孤立コンテナ・ディレクトリを自動削除
  help                          このヘルプを表示

例:
  ./manage-training.sh list                    全ユーザーの環境を一覧
  ./manage-training.sh info tanaka             tanaka の環境詳細
  ./manage-training.sh destroy 3               user_id=3 の環境を削除
  ./manage-training.sh health                  問題がないかチェック
USAGE
}

# --- メイン ---

SUBCOMMAND="${1:-list}"
shift 2>/dev/null || true

case "$SUBCOMMAND" in
    status)  do_status ;;
    list)    do_list ;;
    info)    do_info "$@" ;;
    destroy) do_destroy "$@" ;;
    health)  do_health ;;
    disk)    do_disk ;;
    cleanup) do_cleanup ;;
    help|--help|-h) show_usage ;;
    *)
        echo "不明なサブコマンド: $SUBCOMMAND"
        echo ""
        show_usage
        exit 1
        ;;
esac
