#!/bin/bash
# 演習環境のセルフサービスデプロイ
# 受講者が Linux サーバーに SSH ログイン後に実行する
#
# 使い方:
#   ./deploy-training.sh                    # SSH 接続元 IP で自動識別
#   ./deploy-training.sh --name 山田太郎    # ホスト名を指定
#   ./deploy-training.sh --test             # テスト用（ダミー IP で環境作成）
#   ./deploy-training.sh --test testuser1   # テスト用（名前付き）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 引数解析
TEST_MODE=false
CLIENT_HOSTNAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --test) TEST_MODE=true; shift
                if [[ $# -gt 0 && "$1" != --* ]]; then
                    CLIENT_HOSTNAME="$1"; shift
                fi ;;
        --name) CLIENT_HOSTNAME="$2"; shift 2 ;;
        *)      CLIENT_HOSTNAME="$1"; shift ;;
    esac
done

if [[ "$TEST_MODE" == true ]]; then
    # テスト用: RFC 5737 TEST-NET-2 (198.51.100.0/24) からランダム生成
    CLIENT_IP="198.51.100.$((RANDOM % 254 + 1))"
    CLIENT_HOSTNAME="${CLIENT_HOSTNAME:-test-$(date +%s)}"
    echo "テストモード: ダミー IP $CLIENT_IP を使用"
else
    # SSH 接続元 IP を使用（sshd がセットするため偽装不可）
    CLIENT_IP="${SSH_CLIENT%% *}"
    if [[ -z "$CLIENT_HOSTNAME" ]]; then
        CLIENT_HOSTNAME="$(hostname)"
    fi
fi

if [[ -z "$CLIENT_IP" ]]; then
    echo "エラー: 接続元 IP を特定できません。"
    echo ""
    echo "使い方:"
    echo "  SSH 経由でログイン後: ./deploy-training.sh"
    echo "  テスト用:             ./deploy-training.sh --test"
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
