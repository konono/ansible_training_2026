#!/bin/bash
# 演習環境のセルフサービスデプロイ
# 受講者が Linux サーバーに SSH ログイン後に実行する

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# SSH 接続元の IP を自動取得
CLIENT_IP="${SSH_CLIENT%% *}"
CLIENT_HOSTNAME="${1:-$(hostname)}"

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: SSH 経由でログインしてから実行してください。"
    echo "使用方法: ssh root@<Linux サーバー> して、このスクリプトを実行"
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
