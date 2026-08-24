#!/bin/bash
# 演習環境の削除
# 受講者が Linux サーバーに SSH ログイン後に実行する
#
# 使い方:
#   ./destroy-training.sh                   # IP 自動取得
#   ./destroy-training.sh --ip 10.0.0.3     # IP 手動指定

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CLIENT_IP=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip) CLIENT_IP="$2"; shift 2 ;;
        *)    shift ;;
    esac
done

if [[ -z "$CLIENT_IP" ]]; then
    CLIENT_IP="${SSH_CLIENT%% *}"
fi

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo "使い方: ./destroy-training.sh --ip 10.0.0.3"
    exit 1
fi

echo "接続元 IP: $CLIENT_IP の環境を削除します。"
echo ""

cd "$SCRIPT_DIR"
ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml \
    -e "caller_ip=$CLIENT_IP" \
    --limit rhel-target
