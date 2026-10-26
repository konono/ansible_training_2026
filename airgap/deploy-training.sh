#!/bin/bash
# 演習環境の管理スクリプト
# 環境の作成・一覧表示・削除を行う
#
# 使い方:
#   ./deploy-training.sh                        # 自分の環境を作成（ログインユーザーで自動識別）
#   ./deploy-training.sh --label 山田太郎       # 受講者名を指定して作成
#   ./deploy-training.sh status                 # 環境の一覧を表示
#   ./deploy-training.sh destroy                # 自分の環境を削除
#   ./deploy-training.sh destroy --user 3       # user_id=3 の環境を削除
#   ./deploy-training.sh destroy --username tanaka  # username 指定で削除
#   ./deploy-training.sh --test 3               # テスト環境を 3 人分作成
#   ./deploy-training.sh destroy --test         # テスト環境を全て削除

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOCATE_SCRIPT="$SCRIPT_DIR/scripts/allocate.py"

# rhel-setup.yml が生成するデプロイモード設定を読み込む。
# 無い場合は airgap（従来の挙動）とみなす。
AIRGAP_MODE=true
CONTAINER_IMAGE_MODE=build
CONTAINER_IMAGE_REGISTRY=""
TRAINING_SOURCE_MODE=archive
TRAINING_GIT_REPO=""
TRAINING_GIT_VERSION=main
if [[ -f "$SCRIPT_DIR/deploy-mode.conf" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/deploy-mode.conf"
fi

MODE_ARGS=(
    -e "airgap_mode=$AIRGAP_MODE"
    -e "container_image_mode=$CONTAINER_IMAGE_MODE"
    -e "training_source_mode=$TRAINING_SOURCE_MODE"
)
[[ -n "$CONTAINER_IMAGE_REGISTRY" ]] && MODE_ARGS+=(-e "container_image_registry=$CONTAINER_IMAGE_REGISTRY")
[[ -n "$TRAINING_GIT_REPO" ]]       && MODE_ARGS+=(-e "training_git_repo=$TRAINING_GIT_REPO")
[[ -n "$TRAINING_GIT_VERSION" && "$TRAINING_GIT_VERSION" != "main" ]] && MODE_ARGS+=(-e "training_git_version=$TRAINING_GIT_VERSION")

# 非airgap では inventory/hosts-online.yml を使う
if [[ "$AIRGAP_MODE" == "true" ]]; then
    INVENTORY="${INVENTORY:-inventory/hosts.yml}"
else
    INVENTORY="${INVENTORY:-inventory/hosts-online.yml}"
fi

# --- ヘルプ ---
show_usage() {
    cat << 'USAGE'

使い方:
  ./deploy-training.sh                             環境を作成（ログインユーザーで自動識別）
  ./deploy-training.sh --label 山田太郎            受講者名を指定して作成
  ./deploy-training.sh status                      自分の環境を表示（root: 全環境の一覧）
  ./deploy-training.sh destroy                     自分の環境を削除（ログインユーザー）
  ./deploy-training.sh destroy --user 3            user_id を指定して削除
  ./deploy-training.sh destroy --username tanaka   ユーザー名を指定して削除
  ./deploy-training.sh destroy --ip 10.0.0.5       IP アドレスを指定して削除（後方互換）
  ./deploy-training.sh --test 3                    テスト環境を 3 人分作成
  ./deploy-training.sh destroy --test              テスト環境を全て削除
USAGE
}

# --- サブコマンドの判定 ---
SUBCOMMAND="deploy"
if [[ ${1:-} == "status" ]] || [[ ${1:-} == "destroy" ]]; then
    SUBCOMMAND="$1"
    shift
elif [[ ${1:-} == "help" ]] || [[ ${1:-} == "--help" ]] || [[ ${1:-} == "-h" ]]; then
    show_usage
    exit 0
fi

# --- 引数の解析 ---
TEST_COUNT=0
TEST_MODE=false
CLIENT_LABEL=""
DESTROY_USER_ID=""
DESTROY_IP=""
DESTROY_USERNAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            if [[ "$SUBCOMMAND" == "destroy" ]]; then
                TEST_MODE=true
                shift
            else
                TEST_COUNT="${2:-1}"; shift 2
            fi
            ;;
        --label)    CLIENT_LABEL="$2"; shift 2 ;;
        --name)     CLIENT_LABEL="$2"; shift 2 ;;
        --user)     DESTROY_USER_ID="$2"; shift 2 ;;
        --ip)       DESTROY_IP="$2"; shift 2 ;;
        --username) DESTROY_USERNAME="$2"; shift 2 ;;
        --help|-h)  show_usage; exit 0 ;;
        *)
            echo "不明なオプション: $1"
            show_usage
            exit 1
            ;;
    esac
done

# --- status サブコマンド ---
do_status() {
    local current_user
    current_user="$(whoami)"

    if [[ "$current_user" != "root" ]]; then
        do_status_user "$current_user"
        return
    fi

    do_status_all
}

do_status_user() {
    local username="$1"
    local status_json
    status_json=$(python3 "$ALLOCATE_SCRIPT" --action status 2>/dev/null)

    local alloc
    alloc=$(echo "$status_json" | python3 -c "
import json, sys
username = '$username'
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['status'] == 'released':
        continue
    if a.get('username') == username:
        print(json.dumps(a))
        sys.exit(0)
print('')
" 2>/dev/null)

    if [[ -z "$alloc" ]]; then
        echo "デプロイ済みの環境はありません。"
        echo ""
        echo "環境を作成するには:"
        echo "  ./deploy-training.sh"
        return
    fi

    local training_ip
    training_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    training_ip="${training_ip:-192.168.100.10}"

    echo "$alloc" | python3 -c "
import json, sys
a = json.load(sys.stdin)
ip = '$training_ip'
print('=== あなたの演習環境 ===')
print()
print(f'  ユーザー:    {a.get(\"username\", \"-\")}')
hostname = a.get('client_hostname', '')
if hostname:
    print(f'  表示名:      {hostname}')
status = a['status']
status_label = {'active': '稼働中', 'allocated': '割当済み（起動待ち）'}.get(status, status)
print(f'  ステータス:  {status_label}')
print()
print(f'  接続方法:')
print(f'    ssh -p {a[\"ssh_port\"]} root@{ip}')
print(f'    パスワード: password')
print()
c = a.get('containers', {})
print('  演習用ネットワーク:')
for name, addr in c.items():
    print(f'    {name:12s}  {addr}')
print()
print(f'  環境の削除: ./deploy-training.sh destroy')
print()
" 2>/dev/null
}

do_status_all() {
    local status_json
    status_json=$(python3 "$ALLOCATE_SCRIPT" --action status 2>/dev/null)

    local count
    count=$(echo "$status_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
active = [a for a in data['allocations'] if a['status'] != 'released']
print(len(active))
" 2>/dev/null || echo "0")

    if [[ "$count" == "0" ]]; then
        echo "デプロイ済みの環境はありません。"
        return
    fi

    echo "デプロイ済み環境: $count 件"
    echo ""
    printf "%-8s %-18s %-20s %-8s %-10s %s\n" "USER_ID" "USERNAME" "受講者名" "PORT" "STATUS" "作成日時"
    printf "%-8s %-18s %-20s %-8s %-10s %s\n" "-------" "------------------" "--------------------" "--------" "----------" "-------------------"

    echo "$status_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in sorted(data['allocations'], key=lambda x: x['user_id']):
    if a['status'] == 'released':
        continue
    uid = a['user_id']
    username = a.get('username', '') or a.get('client_ip', '-')
    name = a.get('client_hostname', '-')
    port = a.get('ssh_port', '-')
    status = a.get('status', '-')
    created = a.get('allocated_at', '-')[:19]
    is_test = '(test)' if a.get('client_ip', '').startswith('198.51.100.') else ''
    print(f'{uid:<8} {username:<18} {name:<20} {port:<8} {status:<10} {created} {is_test}')
"
}

# --- destroy サブコマンド ---
do_destroy_by_ip() {
    local ip="$1"
    echo "IP: $ip の環境を削除します。"
    echo ""
    ansible-playbook -i "$INVENTORY" "${MODE_ARGS[@]}" playbooks/destroy-my-env.yml \
        -e "client_ip=$ip" \
        --limit rhel-target
}

do_destroy_by_username() {
    local username="$1"
    echo "ユーザー: $username の環境を削除します。"
    echo ""
    ansible-playbook -i "$INVENTORY" "${MODE_ARGS[@]}" playbooks/destroy-my-env.yml \
        -e "training_username=$username" \
        --limit rhel-target
}

do_destroy_by_user_id() {
    local uid="$1"
    local lookup_result
    lookup_result=$(python3 "$ALLOCATE_SCRIPT" --action status 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['user_id'] == $uid and a['status'] != 'released':
        username = a.get('username', '')
        ip = a.get('client_ip', '')
        print(f'{username}|{ip}')
        break
else:
    print('')
" 2>/dev/null)

    if [[ -z "$lookup_result" ]]; then
        echo "エラー: user_id=$uid の環境が見つかりません。"
        echo ""
        echo "現在の環境一覧:"
        do_status
        exit 1
    fi

    local found_username found_ip
    found_username="${lookup_result%%|*}"
    found_ip="${lookup_result##*|}"

    echo "user_id=$uid の環境を削除します。"
    echo ""

    if [[ -n "$found_username" ]]; then
        ansible-playbook -i "$INVENTORY" "${MODE_ARGS[@]}" playbooks/destroy-my-env.yml \
            -e "training_username=$found_username" \
            --limit rhel-target
    elif [[ -n "$found_ip" ]]; then
        ansible-playbook -i "$INVENTORY" "${MODE_ARGS[@]}" playbooks/destroy-my-env.yml \
            -e "client_ip=$found_ip" \
            --limit rhel-target
    fi
}

do_destroy_test() {
    local test_ips
    test_ips=$(python3 "$ALLOCATE_SCRIPT" --action status 2>/dev/null \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['client_ip'].startswith('198.51.100.') and a['status'] != 'released':
        print(a['client_ip'])
" 2>/dev/null || true)

    if [[ -z "$test_ips" ]]; then
        echo "削除対象のテスト環境はありません。"
        exit 0
    fi

    export ALLOW_TEST_IP=1
    local count
    count=$(echo "$test_ips" | wc -l)
    echo "テスト環境 $count 件を削除します"
    echo ""

    for ip in $test_ips; do
        echo "=== 削除: $ip ==="
        ansible-playbook -i "$INVENTORY" "${MODE_ARGS[@]}" playbooks/destroy-my-env.yml \
            -e "client_ip=$ip" \
            --limit rhel-target
        echo ""
    done
}

do_destroy() {
    if [[ "$TEST_MODE" == true ]]; then
        do_destroy_test
        return
    fi

    if [[ -n "$DESTROY_USER_ID" ]]; then
        do_destroy_by_user_id "$DESTROY_USER_ID"
        return
    fi

    if [[ -n "$DESTROY_IP" ]]; then
        do_destroy_by_ip "$DESTROY_IP"
        return
    fi

    if [[ -n "$DESTROY_USERNAME" ]]; then
        do_destroy_by_username "$DESTROY_USERNAME"
        return
    fi

    # ログインユーザーで自分の環境を削除
    local current_user
    current_user="$(whoami)"

    if [[ "$current_user" == "root" ]]; then
        echo "エラー: root ユーザーでのセルフサービス削除はできません。"
        echo ""
        echo "削除対象を指定してください:"
        echo "  ./deploy-training.sh destroy --user <user_id>"
        echo "  ./deploy-training.sh destroy --username <username>"
        echo "  ./deploy-training.sh destroy --test"
        exit 1
    fi

    do_destroy_by_username "$current_user"
}

# --- deploy (テストモード) ---
do_deploy_test() {
    if [[ "$TEST_COUNT" -gt 99 ]]; then
        echo "エラー: テスト環境は最大 99 人分まで作成できます。"
        exit 1
    fi
    echo "テストモード: $TEST_COUNT 人分の環境を作成します"
    echo ""
    export ALLOW_TEST_IP=1
    for i in $(seq 1 "$TEST_COUNT"); do
        local ip="198.51.100.$i"
        local name="test-user-$i"
        echo "=== [$i/$TEST_COUNT] IP=$ip, label=$name ==="
        ansible-playbook -i "$INVENTORY" "${MODE_ARGS[@]}" playbooks/deploy-my-env.yml \
            -e "client_ip=$ip" \
            -e "client_hostname=$name" \
            --limit rhel-target
        echo ""
    done
}

# --- deploy (通常モード) ---
do_deploy() {
    if [[ "$TEST_COUNT" -gt 0 ]]; then
        do_deploy_test
        return
    fi

    local current_user
    current_user="$(whoami)"

    if [[ "$current_user" == "root" ]]; then
        echo "エラー: root ユーザーでのセルフサービスデプロイはできません。"
        echo "受講者ユーザーでログインするか、--test を使用してください。"
        echo ""
        echo "使い方:"
        echo "  受講者としてログイン: ssh <username>@<training IP>"
        echo "  テスト用:             ./deploy-training.sh --test 3"
        exit 1
    fi

    if [[ -z "$CLIENT_LABEL" ]]; then
        CLIENT_LABEL="$(getent passwd "$current_user" | cut -d: -f5 | cut -d, -f1)"
        if [[ -z "$CLIENT_LABEL" ]]; then
            CLIENT_LABEL="$current_user"
        fi
    fi

    echo "ユーザー: $current_user"
    echo "受講者名: $CLIENT_LABEL"
    echo ""

    ansible-playbook -i "$INVENTORY" "${MODE_ARGS[@]}" playbooks/deploy-my-env.yml \
        -e "training_username=$current_user" \
        -e "client_hostname=$CLIENT_LABEL" \
        --limit rhel-target
}

# --- メイン ---
cd "$SCRIPT_DIR"

case "$SUBCOMMAND" in
    deploy)  do_deploy ;;
    status)  do_status ;;
    destroy) do_destroy ;;
esac
