#!/bin/bash
# 演習環境の削除
# 受講者が Linux サーバーに SSH ログイン後に実行する

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CLIENT_IP="${SSH_CLIENT%% *}"

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: SSH 経由でログインしてから実行してください。"
    exit 1
fi

echo "接続元 IP: $CLIENT_IP の環境を削除します。"
echo ""

cd "$SCRIPT_DIR"
ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml \
    -e "caller_ip=$CLIENT_IP" \
    --limit rhel-target
