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
CLIENT_IP=""
CLIENT_HOSTNAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)   CLIENT_IP="$2"; shift 2 ;;
        --name) CLIENT_HOSTNAME="$2"; shift 2 ;;
        *)      CLIENT_HOSTNAME="$1"; shift ;;
    esac
done

# IP 自動取得（未指定時）
if [[ -z "$CLIENT_IP" ]]; then
    CLIENT_IP="${SSH_CLIENT%% *}"
fi
if [[ -z "$CLIENT_HOSTNAME" ]]; then
    CLIENT_HOSTNAME="$(hostname)"
fi

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo ""
    echo "使い方:"
    echo "  SSH 経由でログイン後: ./deploy-training.sh"
    echo "  IP を手動指定:       ./deploy-training.sh --ip 10.0.0.3"
    exit 1
fi

REAL_IP="${SSH_CLIENT%% *}"
if [[ -n "$REAL_IP" && "$CLIENT_IP" != "$REAL_IP" ]]; then
    echo "警告: --ip ($CLIENT_IP) が SSH 接続元 ($REAL_IP) と異なります。"
    echo "他の受講者の環境に影響する可能性があります。"
    echo "管理者以外は --ip を使わず、自動検出を利用してください。"
    echo ""
fi

echo "接続元 IP: $CLIENT_IP"
echo "ホスト名:  $CLIENT_HOSTNAME"
echo ""

cd "$SCRIPT_DIR"
ansible-playbook -i inventory/hosts.yml playbooks/deploy-my-env.yml \
    -e "client_ip=$CLIENT_IP" \
    -e "client_hostname=$CLIENT_HOSTNAME" \
    --limit rhel-target
