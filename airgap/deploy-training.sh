#!/bin/bash
# 演習環境のセルフサービスデプロイ
# 受講者が Linux サーバーに SSH ログイン後に実行する
#
# 使い方:
#   ./deploy-training.sh                    # IP 自動取得
#   ./deploy-training.sh --ip 10.0.0.3      # IP 手動指定（テスト・代理実行用）
#   ./deploy-training.sh --name 山田太郎    # ホスト名を指定

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 引数解析
ARG_IP=""
CLIENT_HOSTNAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)   ARG_IP="$2"; shift 2 ;;
        --name) CLIENT_HOSTNAME="$2"; shift 2 ;;
        *)      CLIENT_HOSTNAME="$1"; shift ;;
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
    # コンソール直接ログイン（管理者用途）→ --ip を許可
    CLIENT_IP="$ARG_IP"
fi

if [[ -z "$CLIENT_HOSTNAME" ]]; then
    CLIENT_HOSTNAME="$(hostname)"
fi

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo ""
    echo "使い方:"
    echo "  SSH 経由でログイン後: ./deploy-training.sh"
    echo "  コンソールから手動:   ./deploy-training.sh --ip 10.0.0.3"
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
