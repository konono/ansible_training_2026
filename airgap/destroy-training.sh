#!/bin/bash
# 演習環境の削除
# 受講者が Linux サーバーに SSH ログイン後に実行する
#
# 使い方:
#   ./destroy-training.sh                          # SSH 接続元 IP で自動識別
#   ./destroy-training.sh --test 198.51.100.42     # テスト用（ダミー IP 指定）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TEST_IP=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --test) TEST_IP="$2"; shift 2 ;;
        *)      shift ;;
    esac
done

if [[ -n "$TEST_IP" ]]; then
    CLIENT_IP="$TEST_IP"
    echo "テストモード: IP $CLIENT_IP の環境を削除します。"
else
    # SSH 接続元 IP を使用（sshd がセットするため偽装不可）
    CLIENT_IP="${SSH_CLIENT%% *}"
fi

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo ""
    echo "使い方:"
    echo "  SSH 経由でログイン後: ./destroy-training.sh"
    echo "  テスト用:             ./destroy-training.sh --test 198.51.100.42"
    exit 1
fi

echo "接続元 IP: $CLIENT_IP の環境を削除します。"
echo ""

cd "$SCRIPT_DIR"
ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml \
    -e "client_ip=$CLIENT_IP" \
    --limit rhel-target
