#!/bin/bash
# 演習環境の削除
# 受講者が Linux サーバーに SSH ログイン後に実行する
#
# 使い方:
#   ./destroy-training.sh          # 自分の環境を削除
#   ./destroy-training.sh --test   # テスト用環境を全て削除

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TEST_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --test) TEST_MODE=true; shift ;;
        *)      shift ;;
    esac
done

cd "$SCRIPT_DIR"

if [[ "$TEST_MODE" == true ]]; then
    # テスト環境（198.51.100.x）を全て検索して削除
    ALLOCATE_SCRIPT="$SCRIPT_DIR/scripts/allocate.py"
    TEST_IPS=$(python3 "$ALLOCATE_SCRIPT" --action status 2>/dev/null \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['allocations']:
    if a['client_ip'].startswith('198.51.100.') and a['status'] != 'released':
        print(a['client_ip'])
" 2>/dev/null || true)

    if [[ -z "$TEST_IPS" ]]; then
        echo "削除対象のテスト環境はありません。"
        exit 0
    fi

    export ALLOW_TEST_IP=1
    COUNT=$(echo "$TEST_IPS" | wc -l)
    echo "テスト環境 $COUNT 件を削除します"
    echo ""

    for IP in $TEST_IPS; do
        echo "=== 削除: $IP ==="
        ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml \
            -e "client_ip=$IP" \
            --limit rhel-target
        echo ""
    done
    exit 0
fi

# SSH 接続元 IP を使用（sshd がセットするため偽装不可）
CLIENT_IP="${SSH_CLIENT%% *}"

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo ""
    echo "使い方:"
    echo "  SSH 経由でログイン後: ./destroy-training.sh"
    echo "  テスト環境の全削除:   ./destroy-training.sh --test"
    exit 1
fi

echo "接続元 IP: $CLIENT_IP の環境を削除します。"
echo ""

ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml \
    -e "client_ip=$CLIENT_IP" \
    --limit rhel-target
