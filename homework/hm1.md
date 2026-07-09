# 宿題

今までの基礎演習・応用演習で学んだことを使って実際にAnsible Playbookを書いてもらいます。

みなさんに書いてもらったAnsible Playbookをレビューさせていただいてトレーニングが全て終了となります。

## シナリオ

あなたはインフラエンジニアとして、社内向けWebアプリケーションの基盤を構築・運用することになりました。
最初はシンプルな構成からスタートし、利用者の増加やセキュリティ監査、運用効率化の要求に応じて段階的にシステムを成長させていきます。

各課題は前の課題で作ったPlaybookに機能を追加していく形式です。roleのコードは**壊さず・増やしすぎず**、必要な機能を既存のroleに組み込んでいってください。

## 成果物の構成

最終的に以下のファイル構成で提出してください。課題を進めるごとにファイルが増えていきます。

```
homework/
├── ansible.cfg
├── inventory.yml
├── site.yml                    # メインPlaybook（課題1〜4）
├── rolling_update.yml          # ローリングアップデート用（課題5a）
├── secrets.yml                 # vault暗号化済み（課題4b）
├── vault_pass.txt              # vaultパスワードファイル（課題4b）
└── roles/
    ├── nginx/                  # 課題1で作成
    │   ├── defaults/main.yml
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/
    │       ├── nginx.conf.j2
    │       ├── site.conf.j2
    │       └── index.html.j2
    ├── haproxy/                # 課題1で作成、課題4b,cで拡張
    │   ├── defaults/main.yml
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/
    │       └── haproxy.cfg.j2
    ├── test/                   # 課題3で作成
    │   └── tasks/main.yml
    ├── security/               # 課題4aで作成
    │   ├── tasks/main.yml
    │   └── handlers/main.yml
    └── report/                 # 課題5bで作成
        ├── tasks/main.yml
        └── templates/
            └── report.md.j2
```

## 宿題のルール

* **生成AI（ChatGPT、GitHub Copilot、Claude等）の使用は禁止です。** 自分の手でコードを書き、自分の頭で考えてください。公式ドキュメントや `ansible-doc` コマンドの参照はもちろんOKです。

## コーディング規約

本宿題では以下の規約に従ってください。

* `site.yml` の各Playには `become: true` を明示的に指定すること（`ansible.cfg` ではなくPlayレベルで書く）
* roleの適用は `roles:` ディレクティブを使うこと
* 「コントローラーで実行する」Playは `hosts: localhost` + `connection: local` で定義する

```yaml
# site.yml の各Playの書き方
- name: Deploy nginx web servers
  hosts: web
  become: true
  roles:
    - nginx
```

`site.yml` には以下のPlayを順番に定義してください。

```yaml
# 1. nginx デプロイ           → hosts: web
# 2. haproxy デプロイ         → hosts: loadbalancer
# 3. セキュリティ設定         → hosts: all（課題4で追加）
# 4. 自動テスト               → hosts: localhost（課題3で追加）
# 5. レポート生成             → hosts: localhost（課題5bで追加）
```

`rolling_update.yml` は課題5aで別ファイルとして作成します。

---

## 課題 1 — Webアプリケーション基盤の構築

新規プロジェクトが始まりました。`nginx` role と `haproxy` role を作成し、ロードバランシング環境を構築してください。

### 課題1の前提条件

* docker-composeで3台のコンテナ（node1〜2, lb）が起動済みであること
* 課題に取り組む前に、**設計ドキュメント**を作成すること（形式: ppt or Markdown）

#### 設計ドキュメントに含める内容
* ソフトウェアの概要（Nginx / HAProxyとは）
* アーキテクチャ図（Client → HAProxy:80 → nginx1〜2:8080）
* 各ソフトウェアの設定項目一覧
* Playbookのディレクトリ構成（上記の「成果物の構成」を参考に）
* Jinja2テンプレートの設計（どの値を変数化するか）
* inventoryファイルの記載

### 要件

* `nginx` role と `haproxy` role を作成し、`site.yml` から呼び出すこと
* **nginx**: port 8080で待ち受け、`index.html` に**自ノードのIPアドレス**と**バージョン情報**（デフォルト `v1.0`）を表示すること
* **HAProxy**: port 80で待ち受け、backendのnginxに**Round-Robin**で分散すること

<details>
<summary>ヒント</summary>

* nginxのlistenポートやバージョンは `defaults/main.yml` で変数定義し、テンプレートから参照する
* UBI 10ではnginxのサイト設定は `/etc/nginx/conf.d/` に配置する（`sites-enabled/` はDebian系の慣習）

**参考演習:**
* roleの作り方、`defaults/main.yml` の使い方 → [基礎演習6](../basic-roles/ex6.md)
* テンプレート（`.j2`）と変数の埋め込み → [基礎演習5](../basic-roles/ex5.md)
* handlersとnotify → [基礎演習4](../basic-roles/ex4.md)

</details>

---

## 課題 2 — サーバー増設

利用者が増えてきたため、nginxを1台増設して3台体制にすることになりました。

### 前提条件

* node3コンテナ（172.20.0.13）がdocker-composeで起動済みであること（初期構築時に起動済み）

### 要件

* `inventory.yml` にnode3を追加し、計4台（nginx×3, haproxy×1）の構成にする
* 最終的に、Playbookの実行だけで増設が完了する状態にすること

### 取り組み方

まず `inventory.yml` にnode3を追加して `ansible-playbook site.yml` を実行してみてください。

* うまくいった場合 → node3にnginxがデプロイされ、HAProxyのbackendにもnode3が自動的に追加されていれば完了です
* うまくいかなかった場合 → 課題1で作ったroleのコードを見直しましょう。例えば以下のような点が原因になることが多いです
  * HAProxyテンプレートのbackendホスト一覧が**ハードコード**されていないか？ → inventoryの `web` グループから**動的に列挙**する形に修正する
  * nginxのポート番号などがHAProxyテンプレート内で**固定値**になっていないか？ → `hostvars` 経由で変数を参照する形に修正する

### 確認ポイント
* `inventory.yml` の変更とPlaybook実行だけでnginxのデプロイとHAProxyのbackend追加が完了しているか？
* テンプレート内で `{% for %}` ループを使い、inventoryから動的にホスト一覧を取得しているか？

<details>
<summary>ヒント</summary>

* HAProxyテンプレートで `groups['web']` をループすれば、inventoryの `web` グループに属する全ホストを動的に列挙できる
* HAProxyテンプレートからnginxのポートを参照するには、inventoryのwebグループ変数にも定義しておき、`hostvars` 経由で取得する（例: `hostvars[host]['nginx_listen_port']`）

**参考演習:**
* テンプレート内の `{% for %}` ループ、`{% if %}` 分岐 → [応用演習6 - Jinja2テンプレート](../advanced/ex6.md)
* `hostvars` を使ったホスト間の変数参照 → [応用演習9 - インベントリ](../advanced/ex9.md) Section 4
* inventory のグループ変数（`group_vars`） → [応用演習9 - インベントリ](../advanced/ex9.md) Section 2

</details>

---

## 課題 3 — デプロイ後の自動テスト

「ちゃんとデプロイできたか毎回curlで確認するのが面倒です」という運用チームからの声を受けて、`test` role を追加してください。

### 要件

* `test` role を作成し、コントローラーからHAProxyに対してHTTPリクエストを投げるPlayを `site.yml` に追加すること
* 以下を `assert` モジュールで自動検証し、失敗したらPlaybookをエラーで停止させること
  * レスポンスの**ステータスコードが200**であること
  * レスポンスボディに**webグループのいずれかのIPアドレス**が含まれていること
  * webノードの台数分リクエストを投げたとき、**レスポンスボディが全て異なる**こと（Round-Robin確認）
* HAProxyのポートが応答可能になるまで**待機してから**テストを開始すること（待機とHTTPリクエストは別タスク）
* HTTPリクエストには**リトライ制御**を入れること

<details>
<summary>ヒント</summary>

* ポートの待機には `wait_for` モジュール、HTTPリクエストには `uri` モジュールを使う
* `uri` モジュールはcheck mode非対応。`--check` でも動くようにするには `check_mode: false` を付ける

**参考演習:**
* `uri` モジュールと `wait_for` モジュール → [応用演習3 - URIモジュールとリトライ制御](../advanced/ex3.md) Section 1〜2
* `until` / `retries` / `delay` によるリトライ制御 → [応用演習3](../advanced/ex3.md) Section 3
* `assert` モジュールによる検証 → [応用演習1 - 条件分岐とエラー処理](../advanced/ex1.md) Section 3

</details>

---

## 課題 4 — セキュリティ対応と安全なデプロイ

セキュリティ監査チームから以下の要件が来ました。既存のroleに組み込んで対応してください。

### 要件

**a) SSH設定の強化** — `security` role を新規作成

全ノードの`sshd_config`に以下を反映すること。設定ファイル全体の置き換えではなく、**正規表現で該当行を検索・編集**する方法で対応すること。変更後は**sshdを再起動**すること。

* `MaxAuthTries 3`
* `PermitEmptyPasswords no`
* `ClientAliveInterval 300`

**b) 秘密情報の保護** — `haproxy` role を拡張

HAProxyの stats 画面に認証（`stats auth user:pass`）を追加する。ユーザー名とパスワードは `secrets.yml` に記述し、`ansible-vault encrypt` で**暗号化して管理**すること。`haproxy` role のタスク内で読み込んで使うこと。

**c) 設定変更時の安全装置** — `haproxy` role を拡張

HAProxyのコンフィグ変更を安全に行うため、**`block` / `rescue`** で以下の流れを実装すること。

1. 現在の設定ファイルを**バックアップ**する
2. 新しい設定をデプロイし、**`haproxy -c -f ...` で構文チェック**を実行する
3. 構文チェックが**失敗した場合は、バックアップから自動で復元**し、Playを**エラーで停止**する

**d) 部分実行の対応**

`site.yml` の security role を呼び出す**Playレベルに `tags: security`** をつけて `--tags security` で個別実行できるようにすること。

<details>
<summary>ヒント</summary>

**参考演習:**
* a) `lineinfile` による正規表現での行編集 → [応用演習2 - ファイル操作と秘密情報管理](../advanced/ex2.md) Section 1
* b) `ansible-vault` による暗号化 → [応用演習2](../advanced/ex2.md) Section 4
* c) `block` / `rescue` / `always` によるエラー処理 → [応用演習1 - 条件分岐とエラー処理](../advanced/ex1.md) Section 4
* d) `tags` による部分実行 → [応用演習5 - タグと実行制御](../advanced/ex5.md) Section 1

</details>

---

## 課題 5 — 本番運用に向けた仕上げ

いよいよ本番環境へのデプロイが近づいてきました。以下の要件を追加して、本番運用に耐えるPlaybookに仕上げてください。

### 要件

**a) ローリングアップデート** — `rolling_update.yml` を新規作成

`site.yml` とは別に `rolling_update.yml` を作成し、nginxのサイト内容を**1台ずつ順番に**更新すること。

* `nginx` role を使い回すこと（roleの中身は変更しない）
* バージョンは実行時に **`-e "site_version=v2.0"`** で指定できること
* 各ノードの更新後、ハンドラ（nginx再起動）を実行してから**HTTP 200**が返ることを確認し、OKなら次のノードに進むこと。ヘルスチェックには**リトライ制御**を入れること
* 全台完了後にコントローラーから `test` role を実行してRound-Robinを再検証すること

実行例:
```bash
ansible-playbook rolling_update.yml --vault-password-file vault_pass.txt -e "site_version=v2.0"
```

<details>
<summary>ヒント</summary>

* `serial: 1` で1台ずつ処理する
* role適用後のハンドラをヘルスチェック前に実行するには `meta: flush_handlers` を使う
* `-e "site_version=v2.0"` で渡した値を nginx role の変数にマッピングするには、playの `vars:` で橋渡しする

**参考演習:**
* `serial` によるローリングアップデート → [応用演習5 - タグと実行制御](../advanced/ex5.md) Section 3
* `uri` + リトライでヘルスチェック → [応用演習3 - URIモジュールとリトライ制御](../advanced/ex3.md) Section 3
* 変数の優先順位（`-e` で渡した値の扱い） → [応用演習8 - 変数の優先順位](../advanced/ex8.md)

</details>

**b) 構成レポートの自動生成** — `report` role を新規作成

`site.yml` にレポート生成用のPlayを追加し、全ノードの構成情報をまとめたレポートを自動生成すること。

* レポートに含める情報: ホスト名、IPアドレス、OS、メモリ、各サービス（nginx / haproxy）の稼働状態
* **Markdown形式**の Jinja2 テンプレートで生成し、コントローラー上の `/tmp/infra_report.md` に出力すること
* テンプレート内で `hostvars` をループし、webグループかどうかで表示するサービス名を分岐すること

<details>
<summary>ヒント</summary>

* サービスの稼働状態は `service_facts` モジュールで取得する
* レポートPlayは `hosts: localhost` で動くため、その前に全ノードからファクトを収集するPlayが必要

**参考演習:**
* テンプレート内の `{% for %}` ループと `{% if %}` 分岐 → [応用演習6 - Jinja2テンプレート](../advanced/ex6.md)
* `hostvars` をループして複数ホストの情報をまとめる → [応用演習9 - インベントリ](../advanced/ex9.md) Section 4
* `delegate_to` / `run_once` の使い方 → [応用演習5 - タグと実行制御](../advanced/ex5.md) Section 4

</details>

---

## 付録: 環境情報

| コンテナ | ホスト名 | IP | 用途 |
|---|---|---|---|
| controller | controller | 172.20.0.10 | Ansible実行環境（受講者はここにログイン） |
| node1 | node1 | 172.20.0.11 | nginx (web) — 課題1から使用 |
| node2 | node2 | 172.20.0.12 | nginx (web) — 課題1から使用 |
| node3 | node3 | 172.20.0.13 | nginx (web) — 課題2で追加 |
| lb | lb | 172.20.0.14 | haproxy (loadbalancer) |

* OS: Red Hat UBI 10（全コンテナ共通）
* SSH: root / password（全コンテナ共通、port 22）
* 全コンテナはdocker-composeで一括起動済み（課題2でnode3をinventoryに追加する）

### 環境上の制約

* `stdout_callback = yaml` は **廃止済み**。代わりに以下を使うこと:
  ```ini
  [defaults]
  stdout_callback = ansible.builtin.default
  callback_result_format = yaml
  ```
* コンテナ内の `/etc/hosts` は**編集不可**（`Device or resource busy` になる）
* inventoryの**グループ名とホスト名が重複すると警告**が出る。`lb` をグループ名にせず `loadbalancer` にすること
* 認証変数は `ansible_password` を使うこと（`ansible_ssh_pass` は非推奨）
