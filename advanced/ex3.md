# 応用演習 3 - URIモジュールとリトライ制御

この演習では、Ansibleの `uri` モジュールによるHTTPリクエスト、`wait_for` モジュールによるサービス待機、`until`/`retries`/`delay` によるリトライ制御、そして `block`/`rescue` + `include_tasks` を使ったループパターンを学びます。
これらを組み合わせることで、デプロイ後のヘルスチェックや外部APIとの連携を自動化できます。

**前提条件:** 応用演習1（register, assert）を完了していること

[前に戻る](./ex2.md) | [次へ進む](./ex4.md)

---

## Section 1: uri モジュール — HTTP GETリクエスト

`uri` モジュールは、AnsibleからHTTPリクエストを送信するためのモジュールです。APIの呼び出し、ヘルスチェック、Webページの確認などに使用します。

### Step 1: 準備 — nginx の起動

まず、テスト対象のnginxが起動していることを確認します。

```bash
$ cd ~/advanced
```

```bash
$ vi prepare_nginx.yml
```

```yaml
---
- name: テスト環境の準備
  hosts: node1
  become: true

  tasks:
    - name: nginx をインストール
      package:
        name: nginx
        state: present

    - name: テスト用の HTML を作成
      copy:
        dest: /usr/share/nginx/html/index.html
        content: |
          <!DOCTYPE html>
          <html>
          <head><title>Training App</title></head>
          <body>
          <h1>Hello from {{ inventory_hostname }}</h1>
          <p>Status: OK</p>
          </body>
          </html>

    - name: nginx を起動
      service:
        name: nginx
        state: started
        enabled: true
```

```bash
$ ansible-playbook prepare_nginx.yml
```

```
PLAY [テスト環境の準備] ***********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx をインストール] *******************************************************
ok: [node1]

TASK [テスト用の HTML を作成] *****************************************************
changed: [node1]

TASK [nginx を起動] **************************************************************
ok: [node1]

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: uri モジュールで HTTP GET

```bash
$ vi uri_get.yml
```

```yaml
---
- name: uri モジュール - HTTP GET
  hosts: node1
  gather_facts: false

  tasks:
    - name: node1 の nginx に GET リクエスト
      uri:
        url: "http://localhost"
        method: GET
        return_content: true
      register: get_result

    - name: ステータスコードを表示
      debug:
        msg: "HTTP ステータスコード: {{ get_result.status }}"

    - name: レスポンスヘッダーを表示
      debug:
        msg:
          - "Content-Type: {{ get_result.content_type }}"
          - "Server: {{ get_result.server | default('N/A') }}"

    - name: レスポンスボディを表示
      debug:
        msg: "{{ get_result.content }}"
```

```bash
$ ansible-playbook uri_get.yml
```

```
PLAY [uri モジュール - HTTP GET] *************************************************

TASK [node1 の nginx に GET リクエスト] ******************************************
ok: [node1]

TASK [ステータスコードを表示] *****************************************************
ok: [node1] =>
  msg: 'HTTP ステータスコード: 200'

TASK [レスポンスヘッダーを表示] ****************************************************
ok: [node1] =>
  msg:
  - 'Content-Type: text/html'
  - 'Server: nginx/1.26.3'

TASK [レスポンスボディを表示] *****************************************************
ok: [node1] =>
  msg: |-
    <!DOCTYPE html>
    <html>
    <head><title>Training App</title></head>
    <body>
    <h1>Hello from node1</h1>
    <p>Status: OK</p>
    </body>
    </html>

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** `return_content: true` を指定しないと、レスポンスボディは `get_result.content` に格納されません。

---

## Section 2: uri モジュール — HTTP POSTリクエスト

`uri` モジュールはGETだけでなく、POST、PUT、DELETEなどのHTTPメソッドもサポートしています。APIへのデータ送信やトークン取得に使用します。

### Step 1: POST リクエストの送信

```bash
$ vi uri_post.yml
```

```yaml
---
- name: uri モジュール - HTTP POST
  hosts: node1
  gather_facts: false

  tasks:
    - name: JSON データを POST（擬似 API コール）
      uri:
        url: "http://localhost"
        method: POST
        body_format: json
        body:
          username: "admin"
          action: "health_check"
          timestamp: "2026-07-06T10:00:00Z"
        headers:
          Content-Type: "application/json"
          X-Request-ID: "training-001"
        status_code: [200, 405]
        return_content: true
      register: post_result

    - name: POST の結果を表示
      debug:
        msg:
          - "ステータスコード: {{ post_result.status }}"
          - "レスポンス: {{ post_result.content | default('なし') }}"
```

**Note:** nginxのデフォルト設定ではPOSTは405（Method Not Allowed）を返すため、`status_code: [200, 405]` で両方を許容しています。実際のAPIサーバーに対しては `status_code: 201` などを指定します。

```bash
$ ansible-playbook uri_post.yml
```

```
PLAY [uri モジュール - HTTP POST] ************************************************

TASK [JSON データを POST（擬似 API コール）] **************************************
ok: [node1]

TASK [POST の結果を表示] **********************************************************
ok: [node1] =>
  msg:
  - 'ステータスコード: 405'
  - 'レスポンス: <html>...(405 Not Allowed)...</html>'

PLAY RECAP *********************************************************************
node1                      : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: API トークン取得パターン

実際のOpenStack やクラウドAPIでよく使われる、トークン取得のパターンを簡略化した例です。

```bash
$ vi uri_token_pattern.yml
```

```yaml
---
- name: API トークン取得パターン（概念デモ）
  hosts: node1
  gather_facts: false

  vars:
    api_endpoint: "http://localhost"
    api_user: "admin"
    api_password: "secretpassword"

  tasks:
    - name: "認証リクエスト（実環境では POST /auth/tokens 等）"
      uri:
        url: "{{ api_endpoint }}"
        method: GET
        return_content: true
        status_code: 200
      register: auth_result

    - name: レスポンスを表示
      debug:
        msg: "認証レスポンス ステータス: {{ auth_result.status }}"

    - name: トークンを変数に設定（実環境の例）
      set_fact:
        api_token: "dummy-token-for-demo"
      when: auth_result.status == 200

    - name: トークンを使って API を呼び出し（概念デモ）
      debug:
        msg: "取得したトークン: {{ api_token }} を使って後続の API コールを実行します"
```

```bash
$ ansible-playbook uri_token_pattern.yml
```

```
PLAY [API トークン取得パターン（概念デモ）] ****************************************

TASK [認証リクエスト（実環境では POST /auth/tokens 等）] ***************************
ok: [node1]

TASK [レスポンスを表示] ***********************************************************
ok: [node1] =>
  msg: '認証レスポンス ステータス: 200'

TASK [トークンを変数に設定（実環境の例）] ******************************************
ok: [node1]

TASK [トークンを使って API を呼び出し（概念デモ）] *********************************
ok: [node1] =>
  msg: '取得したトークン: dummy-token-for-demo を使って後続の API コールを実行します'

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** 実際のAPI連携では、認証レスポンスからトークンを抽出し（例: `auth_result.json.token`）、後続のリクエストの `Authorization` ヘッダーに設定します。

---

## Section 3: wait_for モジュール — サービス待機

`wait_for` モジュールは、指定した条件が満たされるまで待機するモジュールです。TCPポートの開放やファイルの作成を待つことができ、サービスの起動完了を待つ場面で使用します。

### Step 1: TCP ポートの待機

```bash
$ vi wait_for_port.yml
```

```yaml
---
- name: wait_for - TCP ポート待機
  hosts: node1
  become: true

  tasks:
    - name: nginx を停止
      service:
        name: nginx
        state: stopped

    - name: nginx を起動（非同期）
      service:
        name: nginx
        state: started

    - name: ポート 80 が開くのを待機
      wait_for:
        port: 80
        timeout: 30
        state: started

    - name: ポートが開いたことを確認
      debug:
        msg: "node1 のポート 80 がリッスン状態になりました"
```

```bash
$ ansible-playbook wait_for_port.yml
```

```
PLAY [wait_for - TCP ポート待機] *************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx を停止] **************************************************************
changed: [node1]

TASK [nginx を起動（非同期）] *****************************************************
changed: [node1]

TASK [ポート 80 が開くのを待機] ***************************************************
ok: [node1]

TASK [ポートが開いたことを確認] ****************************************************
ok: [node1] =>
  msg: node1 のポート 80 がリッスン状態になりました

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: ファイルの待機

```bash
$ vi wait_for_file.yml
```

```yaml
---
- name: wait_for - ファイル待機
  hosts: node1
  become: true

  tasks:
    - name: nginx を再起動
      service:
        name: nginx
        state: restarted

    - name: nginx の PID ファイルが作成されるのを待機
      wait_for:
        path: /run/nginx.pid
        state: present
        timeout: 10

    - name: PID ファイルの内容を確認
      command: cat /run/nginx.pid
      register: pid_content
      changed_when: false

    - name: nginx の PID を表示
      debug:
        msg: "nginx の PID: {{ pid_content.stdout }}"
```

```bash
$ ansible-playbook wait_for_file.yml
```

```
PLAY [wait_for - ファイル待機] ***************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx を再起動] ************************************************************
changed: [node1]

TASK [nginx の PID ファイルが作成されるのを待機] ************************************
ok: [node1]

TASK [PID ファイルの内容を確認] ****************************************************
ok: [node1]

TASK [nginx の PID を表示] ********************************************************
ok: [node1] =>
  msg: 'nginx の PID: 12345'

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 3: wait_for と uri の違い

| 特性 | wait_for | uri + until |
|------|----------|-------------|
| チェックレベル | TCP レベル（ポートが開いているか） | HTTP レベル（正しいレスポンスが返るか） |
| 用途 | サービスが起動してポートをリッスンし始めたか確認 | HTTPレスポンスの内容まで検証 |
| 速度 | 高速（TCP接続のみ） | 低速（HTTPリクエスト全体） |
| 失敗パターン | ポートが開かない = サービス未起動 | 500エラー、タイムアウト等のHTTPレベルの問題も検出 |

一般的には、まず `wait_for` でポートが開くのを確認し、その後 `uri` でHTTPレベルの正常性を確認する、という2段階のチェックが推奨されます。

---

## Section 4: until / retries / delay — リトライ制御

`until`/`retries`/`delay` は、タスクが成功するまで繰り返し実行するための仕組みです。サービスの起動直後など、一時的に失敗する可能性がある操作に有効です。

### Step 1: uri + until によるHTTPヘルスチェック

```bash
$ vi uri_until.yml
```

```yaml
---
- name: uri + until - HTTP ヘルスチェック（リトライ付き）
  hosts: node1
  become: true

  tasks:
    - name: nginx を再起動
      service:
        name: nginx
        state: restarted

    - name: HTTP 200 が返るまでリトライ
      uri:
        url: "http://localhost"
        method: GET
        status_code: 200
      register: health_result
      until: health_result.status == 200
      retries: 5
      delay: 5

    - name: ヘルスチェック結果を表示
      debug:
        msg:
          - "ステータス: {{ health_result.status }}"
          - "リトライ回数: {{ health_result.attempts }}"
```

```bash
$ ansible-playbook uri_until.yml
```

```
PLAY [uri + until - HTTP ヘルスチェック（リトライ付き）] ***************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx を再起動] ************************************************************
changed: [node1]

TASK [HTTP 200 が返るまでリトライ] ************************************************
FAILED - RETRYING: [node1]: HTTP 200 が返るまでリトライ (5 retries left).
ok: [node1]

TASK [ヘルスチェック結果を表示] ****************************************************
ok: [node1] =>
  msg:
  - 'ステータス: 200'
  - 'リトライ回数: 1'

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: リトライ動作の詳細

`until`/`retries`/`delay` の動作を理解するために、意図的に失敗する例を見てみましょう。

```bash
$ vi uri_retry_fail.yml
```

```yaml
---
- name: リトライの動作確認（意図的に失敗）
  hosts: node1
  gather_facts: false

  tasks:
    - name: 存在しないポートへのリクエスト（最大3回リトライ）
      uri:
        url: "http://localhost:9999"
        method: GET
        status_code: 200
        timeout: 3
      register: retry_result
      until: retry_result.status == 200
      retries: 3
      delay: 2
      ignore_errors: true

    - name: リトライ結果を表示
      debug:
        msg:
          - "成功: {{ not retry_result.failed }}"
          - "試行回数: {{ retry_result.attempts }}"
          - "メッセージ: {{ retry_result.msg | default('N/A') }}"
```

```bash
$ ansible-playbook uri_retry_fail.yml
```

```
PLAY [リトライの動作確認（意図的に失敗）] ******************************************

TASK [存在しないポートへのリクエスト（最大3回リトライ）] ****************************
FAILED - RETRYING: [node1]: 存在しないポートへのリクエスト（最大3回リトライ） (3 retries left).
FAILED - RETRYING: [node1]: 存在しないポートへのリクエスト（最大3回リトライ） (2 retries left).
FAILED - RETRYING: [node1]: 存在しないポートへのリクエスト（最大3回リトライ） (1 retries left).
fatal: [node1]: FAILED! => changed=false
  attempts: 3
  msg: Status code was -1 and not [200]: Connection refused
...ignoring

TASK [リトライ結果を表示] *********************************************************
ok: [node1] =>
  msg:
  - '成功: False'
  - '試行回数: 3'
  - 'メッセージ: Status code was -1 and not [200]: Connection refused'

PLAY RECAP *********************************************************************
node1                      : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`until`/`retries`/`delay` の動作:

1. タスクを実行する
2. `until` の条件を評価する
3. 条件が `true` なら成功、`false` なら `delay` 秒待って再実行する
4. `retries` 回繰り返しても条件が満たされなければ失敗する

---

## Section 5: block/rescue + include_tasks によるループパターン

`until`/`retries`/`delay` は1つのタスクに対してのみ使えますが、複数のタスクをまとめてリトライしたい場合は、`block`/`rescue` と `include_tasks` を組み合わせた再帰的なループパターンを使います。

### Step 1: ヘルスチェックループの作成

まず、再帰的に呼び出されるタスクファイルを作成します。

```bash
$ vi health_check_loop.yml
```

```yaml
---
- name: リトライカウントを設定
  set_fact:
    retry_count: "{{ 0 if retry_count is undefined else (retry_count | int + 1) }}"

- name: "ヘルスチェックループ（試行: {{ retry_count }}）"
  block:
    - name: HTTP ヘルスチェック
      uri:
        url: "http://{{ target_host }}"
        method: GET
        status_code: 200
        return_content: true
      register: health_result

    - name: レスポンス内容を検証
      assert:
        that:
          - health_result.status == 200
          - "'OK' in health_result.content"
        success_msg: "ヘルスチェック成功（試行 {{ retry_count }} 回目）"
        fail_msg: "レスポンス内容が期待値と異なります"

    - name: チェック結果を表示
      debug:
        msg: "{{ target_host }} のヘルスチェック合格 - ステータス: {{ health_result.status }}"

  rescue:
    - name: 最大リトライ回数に達したか確認
      fail:
        msg: "ヘルスチェック失敗: {{ retry_count | int }} 回リトライしましたが成功しませんでした"
      when: retry_count | int >= 10

    - name: "リトライ前の待機（{{ retry_count }}/10）"
      pause:
        seconds: 5

    - name: リトライ
      include_tasks: health_check_loop.yml
```

次に、このループを呼び出す親Playbookを作成します。

```bash
$ vi health_check_main.yml
```

```yaml
---
- name: ヘルスチェックループのデモ
  hosts: node1
  become: true

  vars:
    target_host: "172.20.0.11"

  tasks:
    - name: nginx が起動していることを確認
      service:
        name: nginx
        state: started

    - name: ヘルスチェックループを開始
      include_tasks: health_check_loop.yml
```

```bash
$ ansible-playbook health_check_main.yml
```

正常時の出力:

```
PLAY [ヘルスチェックループのデモ] **************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx が起動していることを確認] **********************************************
ok: [node1]

TASK [リトライカウントを設定] ******************************************************
ok: [node1]

TASK [HTTP ヘルスチェック] ********************************************************
ok: [node1]

TASK [レスポンス内容を検証] ********************************************************
ok: [node1] =>
  msg: ヘルスチェック成功（試行 0 回目）

TASK [チェック結果を表示] *********************************************************
ok: [node1] =>
  msg: '172.20.0.11 のヘルスチェック合格 - ステータス: 200'

PLAY RECAP *********************************************************************
node1                      : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: until と block/rescue+include_tasks の使い分け

| パターン | until/retries/delay | block/rescue + include_tasks |
|----------|-------------------|-----------------------------|
| 対象 | 1つのタスクのリトライ | 複数タスクをまとめてリトライ |
| 記述量 | 少ない（3行追加するだけ） | 多い（別ファイルが必要） |
| 柔軟性 | 低い（単一タスクのみ） | 高い（任意のロジックを含められる） |
| 用途 | 単純なHTTPチェック、コマンド実行 | チェック + バリデーション + 後処理のセット |
| 推奨場面 | 大半のリトライシナリオ | 複数ステップの検証が必要な場合 |

**Note:** 大半のケースでは `until`/`retries`/`delay` で十分です。`block`/`rescue` + `include_tasks` パターンは、HTTPチェック後にレスポンス内容の検証、ログ記録、通知など、複数のタスクを1つのリトライ単位としてまとめたい場合にのみ使用してください。

---

## Section 6: uri + assert — レスポンス検証の組み合わせ

HTTPレスポンスのステータスコードだけでなく、レスポンスボディの内容まで検証するパターンです。

### Step 1: HTTPレスポンスの詳細検証

```bash
$ vi uri_assert.yml
```

```yaml
---
- name: uri + assert - レスポンス詳細検証
  hosts: node1
  gather_facts: false

  vars:
    check_targets:
      - host: "localhost"
        name: "node1"

  tasks:
    - name: HTTP GET リクエスト
      uri:
        url: "http://{{ item.host }}"
        method: GET
        return_content: true
        status_code: 200
      register: http_results
      loop: "{{ check_targets }}"

    - name: レスポンスの詳細検証
      assert:
        that:
          - item.status == 200
          - "'Hello from' in item.content"
          - item.content_type is search('text/html')
        success_msg: >
          {{ item.item.name }} の検証合格:
          ステータス={{ item.status }},
          Content-Type={{ item.content_type }}
        fail_msg: >
          {{ item.item.name }} の検証失敗:
          ステータス={{ item.status }},
          Content-Type={{ item.content_type }},
          ボディ={{ item.content[:100] }}
      loop: "{{ http_results.results }}"

    - name: 全ノードの検証サマリー
      debug:
        msg: "全ノードのヘルスチェックが完了しました（{{ http_results.results | length }} ノード検証済み）"
```

```bash
$ ansible-playbook uri_assert.yml
```

```
PLAY [uri + assert - レスポンス詳細検証] ******************************************

TASK [HTTP GET リクエスト] ********************************************************
ok: [node1] => (item={'host': 'localhost', 'name': 'node1'})

TASK [レスポンスの詳細検証] *******************************************************
ok: [node1] => (item={'status': 200, 'content': '...', ...}) =>
  msg: |-
    node1 の検証合格: ステータス=200, Content-Type=text/html

TASK [全ノードの検証サマリー] *****************************************************
ok: [node1] =>
  msg: 全ノードのヘルスチェックが完了しました（1 ノード検証済み）

PLAY RECAP *********************************************************************
node1                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: 複数ノードの一括ヘルスチェック

全Webノードのヘルスチェックを一括で行う例です。

```bash
$ vi uri_assert_all.yml
```

```yaml
---
- name: 全 Web ノードのヘルスチェック
  hosts: web
  become: true
  gather_facts: true

  tasks:
    - name: nginx が起動していることを確認
      service:
        name: nginx
        state: started
      ignore_errors: true

- name: ヘルスチェック実行
  hosts: node1
  gather_facts: false

  tasks:
    - name: 全 Web ノードに HTTP リクエスト
      uri:
        url: "http://{{ hostvars[item]['ansible_default_ipv4']['address'] }}"
        method: GET
        return_content: true
        timeout: 10
      register: results
      loop: "{{ groups['web'] }}"
      ignore_errors: true

    - name: 各ノードのステータスを表示
      debug:
        msg: >
          {{ item.item }}:
          {{ 'OK' if not item.failed else 'NG' }}
          (ステータス: {{ item.status | default('N/A') }})
      loop: "{{ results.results }}"

    - name: 失敗したノードがないか確認
      assert:
        that:
          - item.status == 200
        success_msg: "{{ item.item }}: ヘルスチェック合格"
        fail_msg: "{{ item.item }}: ヘルスチェック失敗（ステータス: {{ item.status | default('N/A') }}）"
      loop: "{{ results.results }}"
      ignore_errors: true

    - name: 全体の結果サマリー
      debug:
        msg:
          - "--- ヘルスチェック結果 ---"
          - "合計: {{ results.results | length }} ノード"
          - "成功: {{ results.results | selectattr('status', 'defined') | selectattr('status', 'eq', 200) | list | length }} ノード"
          - "失敗: {{ results.results | selectattr('failed', 'eq', true) | list | length }} ノード"
```

```bash
$ ansible-playbook uri_assert_all.yml
```

```
PLAY [全 Web ノードのヘルスチェック] **********************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx が起動していることを確認] **********************************************
ok: [node1]
ok: [node2]
ok: [node3]

PLAY [ヘルスチェック実行] *********************************************************

TASK [全 Web ノードに HTTP リクエスト] ********************************************
ok: [node1] => (item=node1)
ok: [node1] => (item=node2)
ok: [node1] => (item=node3)

TASK [各ノードのステータスを表示] **************************************************
ok: [node1] => (item={'item': 'node1', 'status': 200, ...}) =>
  msg: 'node1: OK (ステータス: 200)'
ok: [node1] => (item={'item': 'node2', 'status': 200, ...}) =>
  msg: 'node2: OK (ステータス: 200)'
ok: [node1] => (item={'item': 'node3', 'status': 200, ...}) =>
  msg: 'node3: OK (ステータス: 200)'

TASK [失敗したノードがないか確認] **************************************************
ok: [node1] => (item={'item': 'node1', ...}) =>
  msg: 'node1: ヘルスチェック合格'
ok: [node1] => (item={'item': 'node2', ...}) =>
  msg: 'node2: ヘルスチェック合格'
ok: [node1] => (item={'item': 'node3', ...}) =>
  msg: 'node3: ヘルスチェック合格'

TASK [全体の結果サマリー] *********************************************************
ok: [node1] =>
  msg:
  - '--- ヘルスチェック結果 ---'
  - '合計: 3 ノード'
  - '成功: 3 ノード'
  - '失敗: 0 ノード'

PLAY RECAP *********************************************************************
node1                      : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 7: 実践演習 — デプロイ後ヘルスチェック Playbook

ここまで学んだ内容をすべて組み合わせて、「nginxのデプロイ + サービス起動待機 + HTTPヘルスチェック」を一気通貫で行うPlaybookを作成します。

### Step 1: ヘルスチェック付きデプロイ Playbook

```bash
$ vi deploy_with_healthcheck.yml
```

```yaml
---
- name: nginx デプロイ + ヘルスチェック
  hosts: web
  become: true
  gather_facts: true

  vars:
    app_port: 80
    health_check_retries: 5
    health_check_delay: 3

  tasks:
    # --- Phase 1: デプロイ ---
    - name: "Phase 1: nginx のインストール"
      package:
        name: nginx
        state: present

    - name: テスト用のコンテンツを配置
      copy:
        dest: /usr/share/nginx/html/index.html
        content: |
          <!DOCTYPE html>
          <html>
          <head><title>{{ inventory_hostname }}</title></head>
          <body>
          <h1>Hello from {{ inventory_hostname }}</h1>
          <p>Status: OK</p>
          <p>Deployed: 2026-07-06</p>
          </body>
          </html>

    - name: nginx の設定チェック
      command: nginx -t
      changed_when: false
      register: config_check
      failed_when: config_check.rc != 0

    - name: nginx を再起動
      service:
        name: nginx
        state: restarted
        enabled: true

    # --- Phase 2: TCP レベル待機 ---
    - name: "Phase 2: ポート {{ app_port }} が開くのを待機"
      wait_for:
        port: "{{ app_port }}"
        timeout: 30
        state: started

    - name: TCP レベル待機完了
      debug:
        msg: "{{ inventory_hostname }} のポート {{ app_port }} がリッスン状態です"

    # --- Phase 3: HTTP レベルヘルスチェック ---
    - name: "Phase 3: HTTP ヘルスチェック（リトライ付き）"
      uri:
        url: "http://localhost:{{ app_port }}"
        method: GET
        return_content: true
        status_code: 200
      register: health_result
      until: health_result.status == 200
      retries: "{{ health_check_retries }}"
      delay: "{{ health_check_delay }}"

    # --- Phase 4: レスポンス検証 ---
    - name: "Phase 4: レスポンス内容の検証"
      assert:
        that:
          - health_result.status == 200
          - "'Hello from' in health_result.content"
          - "'Status: OK' in health_result.content"
        success_msg: >
          {{ inventory_hostname }} のヘルスチェック合格:
          HTTP {{ health_result.status }},
          レスポンスに期待する文字列を確認
        fail_msg: >
          {{ inventory_hostname }} のヘルスチェック失敗:
          ステータス={{ health_result.status }},
          レスポンスに期待する文字列が含まれていません

    # --- 最終レポート ---
    - name: デプロイ完了レポート
      debug:
        msg:
          - "========================================="
          - "デプロイ完了: {{ inventory_hostname }}"
          - "URL: http://localhost:{{ app_port }}"
          - "HTTP ステータス: {{ health_result.status }}"
          - "ヘルスチェック試行回数: {{ health_result.attempts }}"
          - "========================================="
```

### Step 2: 実行

```bash
$ ansible-playbook deploy_with_healthcheck.yml
```

```
PLAY [nginx デプロイ + ヘルスチェック] *********************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [Phase 1: nginx のインストール] **********************************************
ok: [node1]
changed: [node2]
changed: [node3]

TASK [テスト用のコンテンツを配置] **************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [nginx の設定チェック] *******************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx を再起動] ************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [Phase 2: ポート 80 が開くのを待機] ******************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [TCP レベル待機完了] *********************************************************
ok: [node1] =>
  msg: node1 のポート 80 がリッスン状態です
ok: [node2] =>
  msg: node2 のポート 80 がリッスン状態です
ok: [node3] =>
  msg: node3 のポート 80 がリッスン状態です

TASK [Phase 3: HTTP ヘルスチェック（リトライ付き）] *********************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [Phase 4: レスポンス内容の検証] ***********************************************
ok: [node1] =>
  msg: >-
    node1 のヘルスチェック合格: HTTP 200, レスポンスに期待する文字列を確認
ok: [node2] =>
  msg: >-
    node2 のヘルスチェック合格: HTTP 200, レスポンスに期待する文字列を確認
ok: [node3] =>
  msg: >-
    node3 のヘルスチェック合格: HTTP 200, レスポンスに期待する文字列を確認

TASK [デプロイ完了レポート] *******************************************************
ok: [node1] =>
  msg:
  - '========================================='
  - 'デプロイ完了: node1'
  - 'URL: http://localhost:80'
  - 'HTTP ステータス: 200'
  - 'ヘルスチェック試行回数: 1'
  - '========================================='
ok: [node2] =>
  msg:
  - '========================================='
  - 'デプロイ完了: node2'
  - 'URL: http://localhost:80'
  - 'HTTP ステータス: 200'
  - 'ヘルスチェック試行回数: 1'
  - '========================================='
ok: [node3] =>
  msg:
  - '========================================='
  - 'デプロイ完了: node3'
  - 'URL: http://localhost:80'
  - 'HTTP ステータス: 200'
  - 'ヘルスチェック試行回数: 1'
  - '========================================='

PLAY RECAP *********************************************************************
node1                      : ok=10   changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=10   changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=10   changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

全ノードのデプロイとヘルスチェックが正常に完了しました。

---

## まとめ

この演習で学んだ内容:

| 機能 | 用途 |
|------|------|
| `uri` (GET) | HTTPリクエストを送信し、レスポンスを取得する |
| `uri` (POST) | APIへデータを送信する |
| `wait_for` (port) | TCPポートが開くまで待機する |
| `wait_for` (path) | ファイルが作成されるまで待機する |
| `until`/`retries`/`delay` | タスクが成功するまでリトライする |
| `block`/`rescue` + `include_tasks` | 複数タスクをまとめてリトライする再帰パターン |
| `uri` + `assert` | HTTPレスポンスのステータスとボディを詳細検証する |

**デプロイ後の検証フロー（推奨パターン）:**

```
デプロイ → wait_for（TCP）→ uri + until（HTTP）→ assert（レスポンス検証）
```

---

[前に戻る](./ex2.md) | [次へ進む](./ex4.md)
