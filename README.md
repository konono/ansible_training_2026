# Ansible Playbook ハンズオントレーニング

## 概要

* **目的:** Ansible Playbookの基礎から応用まで実践的に学ぶ
* **対象:** Ansible初学者〜中級者
* **環境:** Podman + UBI 10 コンテナ（Windowsコンテナはオプション）

## 事前準備

→ [環境構築手順](./prepare_training_environment.md)

## ローカル編集モード（ワークスペース）

各セクションの `workspace/` ディレクトリがコントローラーコンテナ内にマウントされています。
ホスト側のエディタ（VS Code 等）でファイルを編集し、コンテナ内で即座に実行できます。

| ホスト側 | コンテナ内 | 用途 |
|---|---|---|
| `basic-intro/workspace/` | `/root/basic-intro/` | 基礎演習 ex1-3（ad-hoc・Playbook 入門） |
| `basic-roles/workspace/` | `/root/basic-roles/` | 基礎演習 ex4-6（Role ベース） |
| `advanced/workspace/` | `/root/advanced/` | 応用演習 |
| `homework/workspace/` | `/root/homework/` | 宿題 |

**使い方:**

1. ホスト側で `basic-intro/workspace/` をエディタで開く
2. ansible.cfg や playbook を作成・編集
3. SSH でコントローラーに入り `cd ~/basic-intro && ansible-playbook site.yml` で実行
4. コンテナ内での変更もホスト側に即座に反映

> SSH 内で vim 等を使った従来の編集も引き続き可能です。

## カリキュラム

### 基礎演習 — 入門 (basic-intro/)

全員必須。順番に実施してください。

| # | タイトル | 学ぶこと |
|---|---------|---------|
| 1 | [環境セットアップと初めての接続](./basic-intro/ex1.md) | ansible.cfg, YAML インベントリ, ping |
| 2 | [ad-hocコマンドの実行](./basic-intro/ex2.md) | command, setup, package, service |
| 3 | [初めてのPlaybook作成](./basic-intro/ex3.md) | YAML, play/task, --check, べき等性 |

### 基礎演習 — Role (basic-roles/)

basic-intro 修了後に実施してください。

| # | タイトル | 学ぶこと |
|---|---------|---------|
| 4 | [変数、ループ、ハンドラ](./basic-roles/ex4.md) | vars, loop, handlers |
| 5 | [テンプレートとJinja2基礎](./basic-roles/ex5.md) | template, Jinja2, facts |
| 6 | [Role: Playbookを再利用可能にする](./basic-roles/ex6.md) | role構造, defaults/vars, import_role |

### 応用演習 (advanced/)

basic修了後、目的に応じて選択してください。

| # | タイトル | 学ぶこと |
|---|---------|---------|
| 1 | [条件分岐とエラーハンドリング](./advanced/ex1.md) | register, when, block/rescue, assert |
| 2 | [ファイル操作と秘密情報管理](./advanced/ex2.md) | lineinfile, blockinfile, vault |
| 3 | [URIモジュールとリトライ制御](./advanced/ex3.md) | uri, wait_for, until, whileループ |
| 4 | [データ処理とフィルタ](./advanced/ex4.md) | default, json_query, regex |
| 5 | [タグと実行制御](./advanced/ex5.md) | tags, serial, delegate_to |
| 6 | [Jinja2テンプレート応用](./advanced/ex6.md) | 空白制御, 継承, サンドボックス |
| 7 | [プラグイン](./advanced/ex7.md) | lookup, filter, test |
| 8 | [変数の優先順位](./advanced/ex8.md) | 20段階の優先順位 |
| 9 | [インベントリとホスト管理](./advanced/ex9.md) | group_vars, hostvars, 動的グループ |
| 10 | [デバッグとベストプラクティス](./advanced/ex10.md) | ansible-lint, debugger |
| 11 | [[オプション] Windowsノードの管理](./advanced/ex11.md) | WinRM, win_ping |

### 宿題

→ [宿題](./homework/hm1.md)

全課題がひとつのシナリオ（Web基盤の構築→運用）として繋がっています。前の課題のPlaybookに機能を追加していく形式です。

| 課題 | シナリオ | 使うテクニック |
|------|------|-----------|
| 1 | Web基盤の構築 | role, template, handler, inventory |
| 2 | サーバー増設 | defaults変数, inventoryのみの変更 |
| 3 | デプロイ後の自動テスト | uri, assert, until/retries, wait_for |
| 4 | セキュリティ対応と安全なデプロイ | lineinfile, vault, block/rescue, tags |
| 5 | 本番運用に向けた仕上げ | serial, Jinja2レポート, ansible-lint |

## コンテナ環境

→ [containers/](./containers/)

## リファレンス設定

→ [example_config/](./homework/example_config/)
