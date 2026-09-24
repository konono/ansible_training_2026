#!/bin/bash
# 演習環境の削除（deploy-training.sh destroy のラッパー）
#
# 使い方:
#   ./destroy-training.sh          # 自分の環境を削除
#   ./destroy-training.sh --test   # テスト用環境を全て削除
#   ./destroy-training.sh --user 3 # user_id=3 の環境を削除
#
# 詳細は ./deploy-training.sh --help を参照

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/deploy-training.sh" destroy "$@"
