# 非airgap 対応 テスト指示プロンプト

テスト実施環境の Claude Code / 作業者にそのまま渡すためのプロンプト。
`<...>` の箇所は実環境に合わせて置き換えること。

---

## 前提条件（依頼者側が事前に済ませておくこと）

- [ ] ブランチ `feature/non-airgap-deployment` が push 済み
- [ ] `docs/developer-access-guide.md`（平文パスワード・内部IPを含む）がコミットに**含まれていない**こと
- [ ] テスト環境に libvirt/KVM と RHEL DVD ISO（airgap 回帰テスト用）がある
- [ ] テスト環境がインターネットに到達でき、RHSM 登録済みまたは有効な dnf リポジトリがある

---

## プロンプト本文（ここから下をコピーして渡す）

````
# 依頼

Ansible 研修環境デプロイ基盤に「非airgap（インターネット接続あり）対応」を実装しました。
実機で検証し、結果を報告してください。

## 対象

- リポジトリ: <リポジトリURL>
- ブランチ: `feature/non-airgap-deployment`
- 作業ディレクトリ: リポジトリ直下の `airgap/`

## 実装の概要

単一のブール変数 `airgap_mode`（既定 `true`）で全ての分岐を制御しています。

| 項目 | airgap (既定) | 非airgap |
|---|---|---|
| インベントリ | `inventory/hosts.yml` | `inventory/hosts-online.yml` |
| yum リポジトリ | DVD ISO → nginx 配信 | RHSM / 既存 dnf リポジトリ |
| コンテナイメージ | `podman load` (tar) | `podman build`（既定）/ `podman pull` |
| ansible-core | バンドルの pip パッケージ | PyPI |
| コレクション | ローカル tarball | Ansible Galaxy |
| docker-compose | バンドルのバイナリ | GitHub Releases から取得 |
| 研修資材 | tar.gz 展開 | tar.gz 展開（既定）/ git clone |
| KVM ネットワーク | 隔離 (`training-isolated`) | NAT (`training-nat`, 192.168.130.0/24) |

モードは `roles/*/defaults/main.yml` を既定値とし、インベントリ変数で上書きする設計です。
**`group_vars/all.yml` にモード変数を書いてはいけません**（`vars_files` はインベントリ変数より優先度が高く、
インベントリの指定を握りつぶすため）。`group_vars/all.yml` の冒頭コメントに理由を記載しています。

事前に静的検証は済んでいます（playbook `--syntax-check` 20件、`bash -n` 8件、変数優先順位の実証）。
**実機でのデプロイ動作は一切未検証**です。そこを確認してほしいのが今回の依頼です。

## 最重要の観点

**既存の airgap 動作が1ミリも壊れていないこと**が最優先です。
非airgap が動くことより、airgap の回帰がないことを重視して検証してください。

## テスト項目

### A. airgap 回帰テスト（最優先）

A-1. 既存の airgap フルテストが従来どおり完走すること
```
cd airgap
make full-test
```
- 期待: `clean → setup-vms → transfer-rhel → deploy-all → test` が全て成功
- 確認: repo-server の nginx がリポジトリを配信、rhel-target でコンテナが起動

A-2. `airgap_mode` を明示しなくても airgap として動くこと
- `inventory/hosts.yml` には `airgap_mode: true` を明示していますが、
  この行をコメントアウトしても **ロールの defaults により airgap 動作になる**こと
- 確認方法: `ansible -i inventory/hosts.yml rhel -m debug -a 'var=airgap_mode'`

A-3. 受講者向けフローの回帰
- bastion 上で `./deploy-training.sh` を実行し、従来どおり環境が払い出されること
- `/opt/airgap/deploy-mode.conf` が生成され、`AIRGAP_MODE=true` になっていること
- `./destroy-training.sh` で正常に破棄できること

A-4. `update-airgap.sh` の回帰
```
./update-airgap.sh                    # ローカル更新
./update-airgap.sh <bastion IP>       # リモート更新
```
- 期待: `offline-resources/` が保持され、Step 7 検証が OK、Step 8 の sync-code が成功
- 確認: `allocations.json` と `credentials` が消えていないこと

### B. 非airgap 新規パス

B-1. NAT ネットワークと検証用 VM の作成
```
make setup-online-network
make setup-online-vm
make verify-online
```
- 期待: `training-nat` が作成され、VM から `ping 8.8.8.8` が通る
- **注意**: 192.168.130.0/24 を使用。libvirt の `default`(192.168.122.0/24) と
  衝突しない想定だが、環境に既存ネットワークがあれば事前に確認すること

B-2. コントローラのセットアップ（非airgap）
```
./setup-controller.sh --online
```
- 期待: ISO セットアップがスキップされ、PyPI から ansible-core、Galaxy からコレクションが入る
- 確認: DVD ISO が無い状態でも完走すること
- 確認: 最後に表示される次ステップが `hosts-online.yml` を参照していること
- 確認: `./setup-controller.sh --help` が正しく表示されること

B-3. 非airgap デプロイ（コンテナイメージ = ローカル build）
```
make deploy-online-rhel AIRGAP_MODE=false
```
または手動:
```
ansible-playbook -i inventory/hosts-online.yml playbooks/distribute-resources.yml
ansible-playbook -i inventory/hosts-online.yml playbooks/rhel-setup.yml
```
- 期待: `repo-server-setup.yml` を実行せずに完了する
- 確認: `containers/` の Containerfile がターゲットに配布され、`podman build` で
  `training-controller:latest` と `training-linux-node:latest` が生成される
- 確認: 研修資材 tar.gz が localhost 側で自動生成され配布される
- 確認: コンテナ内の `/etc/yum.repos.d/` に `airgap-*.repo` が**作られていない**こと
  （非airgap では UBI 既定の CDN を使うため）

B-4. 非airgap での受講者フロー
- `/opt/airgap/deploy-mode.conf` が `AIRGAP_MODE=false` で生成されること
- `./deploy-training.sh` が自動的に `inventory/hosts-online.yml` を選択すること
- 払い出されたコンテナに SSH で入り、`dnf install -y <任意のパッケージ>` が
  インターネット経由で成功すること
- `./destroy-training.sh` で破棄できること

B-5. 非airgap での `update-airgap.sh`
```
AIRGAP_MODE=false ./update-airgap.sh
```
- 期待: `offline-resources/` 不在の WARN が出ないこと
- 期待: Step 8 が `inventory/hosts-online.yml` を使うこと

### C. モード切り替えの境界

C-1. 変数優先順位
```
ansible -i inventory/hosts.yml        rhel -m debug -a 'var=airgap_mode'   # → True
ansible -i inventory/hosts-online.yml rhel -m debug -a 'var=airgap_mode'   # → False
ansible -i inventory/hosts-online.yml rhel -m debug -a 'var=airgap_mode' -e airgap_mode=true  # → true
```

C-2. 誤設定時のエラーメッセージが親切か
- `repo_server` グループが無いインベントリで `airgap_mode=true` を指定して
  `rhel-setup.yml` を流し、「非airgap 環境では airgap_mode=false を指定してください」
  という趣旨の assert メッセージが出ることを確認

C-3. コンテナイメージ `pull` モード（レジストリがある環境のみ、任意）
```
ansible-playbook -i inventory/hosts-online.yml playbooks/rhel-setup.yml \
  -e container_image_mode=pull -e container_image_registry=<registry>/<path>
```

C-4. 研修資材の git clone モード（任意）
```
ansible-playbook -i inventory/hosts-online.yml playbooks/rhel-setup.yml \
  -e training_source_mode=git -e training_git_repo=<リポジトリURL>
```

### D. 冪等性

D-1. 以下をそれぞれ**2回連続**で実行し、2回目が `changed=0` になること
- `playbooks/rhel-setup.yml`（airgap / 非airgap 両方）
- `playbooks/deploy-my-env.yml`
- `make deploy-online-rhel AIRGAP_MODE=false`

`changed` が残るタスクがあれば、タスク名と理由を報告してください。
特に `container_images` ロール（`missing_images` による判定）と
`deploy-mode.conf` の生成タスクに注目してください。

### E. ドキュメント

E-1. `docs/online-deployment-guide.md` の手順どおりに**何も読み替えずに**実行して
     完了できるか。詰まった箇所・実際と異なる記述を報告してください。
E-2. `README.md` と `docs/deployment-guide.md` からの導線が妥当か。

## 報告してほしいこと

1. 各テスト項目の結果（OK / NG / 未実施、未実施は理由も）
2. NG の場合: 実行コマンド全文、エラー出力、該当ファイル:行番号
3. 冪等性で `changed` が残ったタスク名の一覧
4. ドキュメントの記述と実際の挙動の差分
5. 設計上気になった点（この分岐の切り方は危ういのでは、等）

## 注意事項

- **airgap のテスト環境を壊さないでください。** 非airgap の検証は
  `make setup-online-vm` で作る専用 VM（`training-nat` 側）で行ってください。
- `make clean` は全 VM を削除します。非airgap VM だけを消す場合は
  `make destroy-online-vm` を使ってください。
- 問題を見つけても修正は不要です。まず報告してください。
  実装の意図と食い違っている可能性があります。
````

---

## 補足: テスト結果を受け取った後の想定作業

- NG 項目の修正
- 冪等性が崩れているタスクの `changed_when` 調整
- ドキュメントの実機反映
