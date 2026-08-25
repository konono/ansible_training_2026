#!/bin/bash
# 演習環境の削除
# 受講者が Linux サーバーに SSH ログイン後に実行する
#
# 使い方:
#   ./destroy-training.sh                   # IP 自動取得
#   ./destroy-training.sh --ip 10.0.0.3     # IP 手動指定

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ARG_IP=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip) ARG_IP="$2"; shift 2 ;;
        *)    shift ;;
    esac
done

# SSH 経由ならセッション情報を信頼（sshd がセットするため偽装不可）
SSH_IP="${SSH_CLIENT%% *}"
if [[ -n "$SSH_IP" ]]; then
    CLIENT_IP="$SSH_IP"
    if [[ -n "$ARG_IP" && "$ARG_IP" != "$SSH_IP" ]]; then
        echo "注意: SSH 接続元 ($SSH_IP) を使用します（--ip は SSH セッション内では無効）"
    fi
else
    CLIENT_IP="$ARG_IP"
fi

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo "使い方:"
    echo "  SSH 経由でログイン後: ./destroy-training.sh"
    echo "  コンソールから手動:   ./destroy-training.sh --ip 10.0.0.3"
    exit 1
fi

echo "接続元 IP: $CLIENT_IP の環境を削除します。"
echo ""

cd "$SCRIPT_DIR"
ansible-playbook -i inventory/hosts.yml playbooks/destroy-my-env.yml \
    -e "client_ip=$CLIENT_IP" \
    --limit rhel-target
