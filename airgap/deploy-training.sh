#!/bin/bash
# 演習環境のセルフサービスデプロイ
# 受講者が Linux サーバーに SSH ログイン後に実行する
#
# 使い方:
#   ./deploy-training.sh                    # SSH 接続元 IP で自動識別
#   ./deploy-training.sh --name 山田太郎    # ホスト名を指定
#   ./deploy-training.sh --test 3           # テスト用（3人分のダミー環境を作成）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TEST_COUNT=0
CLIENT_HOSTNAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --test) TEST_COUNT="${2:-1}"; shift 2 ;;
        --name) CLIENT_HOSTNAME="$2"; shift 2 ;;
        *)      CLIENT_HOSTNAME="$1"; shift ;;
    esac
done

if [[ "$TEST_COUNT" -gt 0 ]]; then
    if [[ "$TEST_COUNT" -gt 99 ]]; then
        echo "エラー: テスト環境は最大 99 人分まで作成できます。"
        exit 1
    fi
    echo "テストモード: $TEST_COUNT 人分の環境を作成します"
    echo ""
    cd "$SCRIPT_DIR"
    export ALLOW_TEST_IP=1
    for i in $(seq 1 "$TEST_COUNT"); do
        IP="198.51.100.$i"
        NAME="test-user-$i"
        echo "=== [$i/$TEST_COUNT] IP=$IP, name=$NAME ==="
        ansible-playbook -i inventory/hosts.yml playbooks/deploy-my-env.yml \
            -e "client_ip=$IP" \
            -e "client_hostname=$NAME" \
            --limit rhel-target
        echo ""
    done
    exit 0
fi

# SSH 接続元 IP を使用（sshd がセットするため偽装不可）
CLIENT_IP="${SSH_CLIENT%% *}"
if [[ -z "$CLIENT_HOSTNAME" ]]; then
    CLIENT_HOSTNAME="$(hostname)"
fi

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo ""
    echo "使い方:"
    echo "  SSH 経由でログイン後: ./deploy-training.sh"
    echo "  テスト用:             ./deploy-training.sh --test 3"
    exit 1
fi

echo "接続元 IP: $CLIENT_IP"
echo "ホスト名:  $CLIENT_HOSTNAME"
echo ""

cd "$SCRIPT_DIR"
ansible-playbook -i inventory/hosts.yml playbooks/deploy-my-env.yml \
    -e "client_ip=$CLIENT_IP" \
    -e "client_hostname=$CLIENT_HOSTNAME" \
    --limit rhel-target
