# 応用演習 1 - 条件分岐とエラーハンドリング

この演習では、Ansibleの条件分岐とエラーハンドリングについて学びます。
`register`によるタスク結果のキャプチャ、`when`による条件分岐、`changed_when`/`failed_when`による結果の制御、`assert`モジュールによるバリデーション、そして`block`/`rescue`/`always`による例外処理パターンを、nginxデプロイのシナリオを通じて実践します。

**前提条件:** 基礎演習1〜6を完了していること

[基礎演習に戻る](../basic-roles/ex6.md) | [次へ進む](./ex2.md)

---

## Section 1: register — タスク結果のキャプチャ

Ansibleでは、`register` キーワードを使ってタスクの実行結果を変数に格納できます。格納した結果は、後続のタスクで条件判定やデバッグに利用できます。

### Step 1: register の基本的な使い方

まず、応用演習用の作業ディレクトリを作成します。

```bash
$ # ワークスペースは既にマウントされています
$ cd ~/advanced
```

基礎演習で作成した `ansible.cfg` と `inventory.yml` をコピーします。

```bash
$ cp ~/basic-intro/ansible.cfg .
$ cp ~/basic-intro/inventory.yml .
```

`register` を使ったPlaybookを作成します。

```bash
$ vi register_demo.yml
```

```yaml
---
- name: register デモ
  hosts: node1
  become: true

  tasks:
    - name: nginx をインストール
      package:
        name: nginx
        state: present

    - name: nginx のバージョンを確認
      command: nginx -v
      register: nginx_result

    - name: 実行結果の全体を表示
      debug:
        var: nginx_result

    - name: 標準エラー出力を表示（nginx -v は stderr に出力）
      debug:
        msg: "nginx バージョン: {{ nginx_result.stderr }}"

    - name: リターンコードを表示
      debug:
        msg: "リターンコード: {{ nginx_result.rc }}"

    - name: changed 状態を表示
      debug:
        msg: "変更あり: {{ nginx_result.changed }}"
```

Playbookを実行します。

```bash
$ ansible-playbook register_demo.yml
```

以下のような出力が表示されます。

```
PLAY [register デモ] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx をインストール] *****************************************************
ok: [node1]

TASK [nginx のバージョンを確認] **************************************************
changed: [node1]

TASK [実行結果の全体を表示] ******************************************************
ok: [node1] =>
  nginx_result:
    changed: true
    cmd:
    - nginx
    - -v
    delta: '0:00:00.005432'
    end: '2026-07-06 10:00:01.123456'
    msg: ''
    rc: 0
    start: '2026-07-06 10:00:01.118024'
    stderr: nginx version: nginx/1.26.3
    stderr_lines:
    - nginx version: nginx/1.26.3
    stdout: ''
    stdout_lines: []

TASK [標準エラー出力を表示（nginx -v は stderr に出力）] ***************************
ok: [node1] =>
  msg: 'nginx バージョン: nginx version: nginx/1.26.3'

TASK [リターンコードを表示] ******************************************************
ok: [node1] =>
  msg: 'リターンコード: 0'

TASK [changed 状態を表示] ********************************************************
ok: [node1] =>
  msg: '変更あり: True'

PLAY RECAP *********************************************************************
node1                      : ok=6    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`register` で格納される主な属性は以下の通りです。

| 属性 | 説明 |
|------|------|
| `.rc` | コマンドのリターンコード（0 = 成功） |
| `.stdout` | 標準出力 |
| `.stderr` | 標準エラー出力 |
| `.stdout_lines` | 標準出力を行ごとのリストにしたもの |
| `.changed` | タスクが変更を行ったかどうか（true/false） |
| `.failed` | タスクが失敗したかどうか（true/false） |

### Step 2: register の結果を後続タスクで使用

register で取得した結果を使って、後続のタスクの実行を制御できます。

```bash
$ vi register_condition.yml
```

```yaml
---
- name: register の結果で分岐
  hosts: node1
  become: true

  tasks:
    - name: nginx がインストール済みか確認
      command: rpm -q nginx
      register: rpm_result
      ignore_errors: true

    - name: nginx が未インストールの場合のみインストール
      package:
        name: nginx
        state: present
      when: rpm_result.rc != 0

    - name: nginx がインストール済みの場合メッセージを表示
      debug:
        msg: "nginx は既にインストールされています: {{ rpm_result.stdout }}"
      when: rpm_result.rc == 0
```

```bash
$ ansible-playbook register_condition.yml
```

```
PLAY [register の結果で分岐] ****************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx がインストール済みか確認] *********************************************
changed: [node1]

TASK [nginx が未インストールの場合のみインストール] *******************************
skipping: [node1]

TASK [nginx がインストール済みの場合メッセージを表示] *****************************
ok: [node1] =>
  msg: 'nginx は既にインストールされています: nginx-1.26.3-x.el10.x86_64'

PLAY RECAP *********************************************************************
node1                      : ok=3    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
```

**Note:** `ignore_errors: true` を付けることで、`rpm -q` がリターンコード 1（パッケージ未インストール）を返してもPlaybookが中断しません。

---

## Section 2: when — 条件分岐

`when` キーワードを使うと、特定の条件を満たした場合にのみタスクを実行できます。Jinja2の式を使って条件を記述します。

### Step 1: ファクト情報による条件分岐

```bash
$ vi when_facts.yml
```

```yaml
---
- name: when 条件分岐デモ
  hosts: all
  become: true

  tasks:
    - name: OS ディストリビューションを表示
      debug:
        msg: "このホストの OS は {{ ansible_distribution }} {{ ansible_distribution_version }} です"

    - name: RedHat 系 OS の場合のみ実行
      debug:
        msg: "RedHat 系 OS が検出されました"
      when: ansible_distribution == "RedHat"

    - name: メジャーバージョンが 10 以上の場合のみ実行
      debug:
        msg: "メジャーバージョン: {{ ansible_distribution_major_version }}"
      when: ansible_distribution_major_version | int >= 10
```

```bash
$ ansible-playbook when_facts.yml
```

```
PLAY [when 条件分岐デモ] ********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

TASK [OS ディストリビューションを表示] ********************************************
ok: [node1] =>
  msg: このホストの OS は RedHat 10.2 です
ok: [node2] =>
  msg: このホストの OS は RedHat 10.2 です
ok: [node3] =>
  msg: このホストの OS は RedHat 10.2 です
ok: [lb] =>
  msg: このホストの OS は RedHat 10.2 です

TASK [RedHat 系 OS の場合のみ実行] ***********************************************
ok: [node1] =>
  msg: RedHat 系 OS が検出されました
ok: [node2] =>
  msg: RedHat 系 OS が検出されました
ok: [node3] =>
  msg: RedHat 系 OS が検出されました
ok: [lb] =>
  msg: RedHat 系 OS が検出されました

TASK [メジャーバージョンが 10 以上の場合のみ実行] *********************************
ok: [node1] =>
  msg: 'メジャーバージョン: 10'
ok: [node2] =>
  msg: 'メジャーバージョン: 10'
ok: [node3] =>
  msg: 'メジャーバージョン: 10'
ok: [lb] =>
  msg: 'メジャーバージョン: 10'

PLAY RECAP *********************************************************************
lb                         : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: register の結果とグループによる条件分岐

```bash
$ vi when_advanced.yml
```

```yaml
---
- name: 高度な when 条件分岐
  hosts: all
  become: true

  tasks:
    - name: nginx がインストール済みか確認
      command: rpm -q nginx
      register: rpm_result
      ignore_errors: true

    - name: register の結果で分岐（リターンコード）
      debug:
        msg: "nginx はインストール済みです"
      when: rpm_result.rc == 0

    - name: グループによる分岐（web グループのみ）
      debug:
        msg: "{{ inventory_hostname }} は web グループに所属しています"
      when: inventory_hostname in groups['web']

    - name: グループによる分岐（loadbalancer グループのみ）
      debug:
        msg: "{{ inventory_hostname }} は loadbalancer グループに所属しています"
      when: inventory_hostname in groups['loadbalancer']
```

```bash
$ ansible-playbook when_advanced.yml
```

```
PLAY [高度な when 条件分岐] ******************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

TASK [nginx がインストール済みか確認] *********************************************
changed: [node1]
changed: [node2]
changed: [node3]
failed: [lb] (ignored)

TASK [register の結果で分岐（リターンコード）] ************************************
ok: [node1] =>
  msg: nginx はインストール済みです
ok: [node2] =>
  msg: nginx はインストール済みです
ok: [node3] =>
  msg: nginx はインストール済みです
skipping: [lb]

TASK [グループによる分岐（web グループのみ）] *************************************
ok: [node1] =>
  msg: node1 は web グループに所属しています
ok: [node2] =>
  msg: node2 は web グループに所属しています
ok: [node3] =>
  msg: node3 は web グループに所属しています
skipping: [lb]

TASK [グループによる分岐（loadbalancer グループのみ）] **************************************
skipping: [node1]
skipping: [node2]
skipping: [node3]
ok: [lb] =>
  msg: lb は loadbalancer グループに所属しています

PLAY RECAP *********************************************************************
lb                         : ok=3    changed=0    unreachable=0    failed=0    skipped=2    rescued=0    ignored=1
node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
node2                      : ok=4    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
node3                      : ok=4    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
```

### Step 3: and / or による複合条件

```bash
$ vi when_combined.yml
```

```yaml
---
- name: 複合条件デモ
  hosts: all
  become: true

  tasks:
    - name: nginx がインストール済みか確認
      command: rpm -q nginx
      register: rpm_result
      ignore_errors: true

    - name: AND 条件 - RedHat かつ web グループ
      debug:
        msg: "RedHat の Web サーバーです"
      when:
        - ansible_distribution == "RedHat"
        - inventory_hostname in groups['web']

    - name: OR 条件 - node1 または lb の場合
      debug:
        msg: "{{ inventory_hostname }} は node1 または lb です"
      when: inventory_hostname == 'node1' or inventory_hostname == 'lb'

    - name: AND と OR の組み合わせ
      debug:
        msg: "条件に合致しました"
      when: >
        (ansible_distribution == "RedHat" and rpm_result.rc == 0) or
        inventory_hostname in groups['loadbalancer']
```

**Note:** `when` にリストを渡すと、すべての条件がAND（かつ）で評価されます。OR条件を使いたい場合は、1つの文字列内で `or` キーワードを使います。

```bash
$ ansible-playbook when_combined.yml
```

```
PLAY [複合条件デモ] **************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

TASK [nginx がインストール済みか確認] *********************************************
changed: [node1]
changed: [node2]
changed: [node3]
failed: [lb] (ignored)

TASK [AND 条件 - RedHat かつ web グループ] ****************************************
ok: [node1] =>
  msg: RedHat の Web サーバーです
ok: [node2] =>
  msg: RedHat の Web サーバーです
ok: [node3] =>
  msg: RedHat の Web サーバーです
skipping: [lb]

TASK [OR 条件 - node1 または lb の場合] *******************************************
ok: [node1] =>
  msg: node1 は node1 または lb です
skipping: [node2]
skipping: [node3]
ok: [lb] =>
  msg: lb は node1 または lb です

TASK [AND と OR の組み合わせ] *****************************************************
ok: [node1] =>
  msg: 条件に合致しました
ok: [node2] =>
  msg: 条件に合致しました
ok: [node3] =>
  msg: 条件に合致しました
ok: [lb] =>
  msg: 条件に合致しました

PLAY RECAP *********************************************************************
lb                         : ok=4    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=1
node1                      : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
node3                      : ok=4    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
```

---

## Section 3: changed_when / failed_when — 結果の制御

`command` や `shell` モジュールは、実行するたびに `changed` と報告します。しかし、情報収集のみのコマンド（設定チェックなど）は実際にはシステムを変更していません。`changed_when` と `failed_when` を使って、Ansibleの変更判定や失敗判定をカスタマイズできます。

### Step 1: changed_when の使用

```bash
$ vi changed_when_demo.yml
```

```yaml
---
- name: changed_when デモ
  hosts: node1
  become: true

  tasks:
    - name: nginx の設定チェック（changed_when なし）
      command: nginx -t
      register: config_check_1

    - name: 結果を確認（changed になっている）
      debug:
        msg: "changed: {{ config_check_1.changed }}"

    - name: nginx の設定チェック（changed_when あり）
      command: nginx -t
      register: config_check_2
      changed_when: false

    - name: 結果を確認（changed にならない）
      debug:
        msg: "changed: {{ config_check_2.changed }}"
```

```bash
$ ansible-playbook changed_when_demo.yml
```

```
PLAY [changed_when デモ] *********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx の設定チェック（changed_when なし）] ***********************************
changed: [node1]

TASK [結果を確認（changed になっている）] ******************************************
ok: [node1] =>
  msg: 'changed: True'

TASK [nginx の設定チェック（changed_when あり）] ***********************************
ok: [node1]

TASK [結果を確認（changed にならない）] ********************************************
ok: [node1] =>
  msg: 'changed: False'

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** `changed_when: false` を指定すると、タスクの結果が常に `ok`（変更なし）として報告されます。設定チェックやバージョン確認のような、システムを変更しないコマンドに使用します。

### Step 2: failed_when の使用

```bash
$ vi failed_when_demo.yml
```

```yaml
---
- name: failed_when デモ
  hosts: node1
  become: true

  tasks:
    - name: nginx の設定チェック（カスタム失敗条件）
      command: nginx -t
      register: config_result
      changed_when: false
      failed_when: "'error' in config_result.stderr"

    - name: 設定チェック成功
      debug:
        msg: "nginx の設定は正常です: {{ config_result.stderr }}"

    - name: 存在しないファイルを含む設定テスト用ファイルを作成
      copy:
        dest: /etc/nginx/sites-enabled/broken.conf
        content: |
          server {
              listen 9999;
              include /nonexistent/path/file.conf;
          }

    - name: 壊れた設定のチェック（failed_when で制御）
      command: nginx -t
      register: broken_result
      changed_when: false
      failed_when: "'error' in broken_result.stderr or 'emerg' in broken_result.stderr"

    - name: このタスクは実行されない（前のタスクで失敗するため）
      debug:
        msg: "ここには到達しません"
```

```bash
$ ansible-playbook failed_when_demo.yml
```

```
PLAY [failed_when デモ] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx の設定チェック（カスタム失敗条件）] ************************************
ok: [node1]

TASK [設定チェック成功] ***********************************************************
ok: [node1] =>
  msg: 'nginx の設定は正常です: nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
    nginx: configuration file /etc/nginx/nginx.conf test is successful'

TASK [存在しないファイルを含む設定テスト用ファイルを作成] **************************
changed: [node1]

TASK [壊れた設定のチェック（failed_when で制御）] **********************************
fatal: [node1]: FAILED! => changed=false
  cmd:
  - nginx
  - -t
  rc: 1
  stderr: |-
    nginx: [emerg] open() "/nonexistent/path/file.conf" failed (2: No such file or directory) in /etc/nginx/sites-enabled/broken.conf:3
    nginx: configuration file /etc/nginx/nginx.conf test failed

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=1    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
```

壊れた設定ファイルを削除しておきます。

```bash
$ ansible node1 -m file -a "path=/etc/nginx/sites-enabled/broken.conf state=absent" --become
```

---

## Section 4: assert モジュール — バリデーション

`assert` モジュールは、指定した条件が真であることを検証します。条件が偽の場合、タスクは失敗します。設定の妥当性チェックやデプロイ後の検証に非常に有用です。

### Step 1: assert の基本的な使い方

```bash
$ vi assert_demo.yml
```

```yaml
---
- name: assert デモ
  hosts: node1
  become: true
  gather_facts: true

  tasks:
    - name: パッケージ情報を収集
      package_facts:
        manager: auto

    - name: nginx がインストールされていることを確認
      assert:
        that:
          - "'nginx' in ansible_facts.packages"
        success_msg: "nginx はインストールされています"
        fail_msg: "nginx がインストールされていません。先にインストールしてください"

    - name: OS とバージョンの確認
      assert:
        that:
          - ansible_distribution == "RedHat"
          - ansible_distribution_major_version | int >= 10
        success_msg: "対応 OS です（{{ ansible_distribution }} {{ ansible_distribution_version }}）"
        fail_msg: "この Playbook は RedHat 10 以上でのみ動作します"

    - name: メモリの確認
      assert:
        that:
          - ansible_memtotal_mb >= 256
        success_msg: "メモリ容量は十分です（{{ ansible_memtotal_mb }} MB）"
        fail_msg: "メモリが不足しています（最低 256 MB 必要、現在 {{ ansible_memtotal_mb }} MB）"
```

```bash
$ ansible-playbook assert_demo.yml
```

```
PLAY [assert デモ] ***************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [パッケージ情報を収集] *******************************************************
ok: [node1]

TASK [nginx がインストールされていることを確認] ************************************
ok: [node1] =>
  msg: nginx はインストールされています

TASK [OS とバージョンの確認] ******************************************************
ok: [node1] =>
  msg: 対応 OS です（RedHat 10.2）

TASK [メモリの確認] ***************************************************************
ok: [node1] =>
  msg: メモリ容量は十分です（1024 MB）

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: assert で複数条件を検証

```bash
$ vi assert_multi.yml
```

```yaml
---
- name: デプロイ前のプリフライトチェック
  hosts: web
  become: true
  gather_facts: true

  tasks:
    - name: パッケージ情報を収集
      package_facts:
        manager: auto

    - name: プリフライトチェック
      assert:
        that:
          - ansible_distribution == "RedHat"
          - ansible_distribution_major_version | int >= 10
          - "'nginx' in ansible_facts.packages"
          - ansible_memtotal_mb >= 256
        success_msg: >
          プリフライトチェック合格:
          OS={{ ansible_distribution }} {{ ansible_distribution_version }},
          nginx=インストール済み,
          メモリ={{ ansible_memtotal_mb }}MB
        fail_msg: >
          プリフライトチェック失敗。
          上記の条件をすべて満たしているか確認してください。
```

```bash
$ ansible-playbook assert_multi.yml
```

```
PLAY [デプロイ前のプリフライトチェック] ********************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [パッケージ情報を収集] *******************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [プリフライトチェック] *******************************************************
ok: [node1] =>
  msg: |-
    プリフライトチェック合格: OS=RedHat 10.2, nginx=インストール済み, メモリ=1024MB
ok: [node2] =>
  msg: |-
    プリフライトチェック合格: OS=RedHat 10.2, nginx=インストール済み, メモリ=1024MB
ok: [node3] =>
  msg: |-
    プリフライトチェック合格: OS=RedHat 10.2, nginx=インストール済み, メモリ=1024MB

PLAY RECAP *********************************************************************
node1                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** 基礎演習を実施済みであればwebグループの全ノードにnginxがインストールされているため、すべて合格します。未インストールのノードがある場合は失敗します。これが `assert` の意図した動作です。

---

## Section 5: block / rescue / always — 例外処理

`block`/`rescue`/`always` は、プログラミング言語の `try`/`catch`/`finally` に相当するAnsibleの例外処理機構です。

- **block**: 通常実行するタスク群
- **rescue**: block 内でエラーが発生した場合に実行するタスク群
- **always**: block の成功・失敗に関わらず常に実行するタスク群

### Step 1: block/rescue/always の基本構造

```bash
$ vi block_demo.yml
```

```yaml
---
- name: block/rescue/always デモ
  hosts: node1
  become: true

  tasks:
    - name: nginx デプロイ（エラーハンドリング付き）
      block:
        - name: 現在の設定をバックアップ
          copy:
            src: /etc/nginx/nginx.conf
            dest: /etc/nginx/nginx.conf.bak
            remote_src: true

        - name: 新しい設定を配置
          copy:
            dest: /etc/nginx/sites-enabled/app.conf
            content: |
              server {
                  listen 8080;
                  server_name app.training.local;

                  location / {
                      root /usr/share/nginx/html;
                      index index.html;
                  }
              }

        - name: 設定チェック
          command: nginx -t
          changed_when: false

        - name: nginx を再起動
          service:
            name: nginx
            state: restarted

      rescue:
        - name: エラー発生 - バックアップから復元
          copy:
            src: /etc/nginx/nginx.conf.bak
            dest: /etc/nginx/nginx.conf
            remote_src: true

        - name: 壊れた設定ファイルを削除
          file:
            path: /etc/nginx/sites-enabled/app.conf
            state: absent

        - name: nginx を復元した設定で再起動
          service:
            name: nginx
            state: restarted

        - name: エラー通知
          debug:
            msg: "デプロイに失敗しました。設定をロールバックしました。"

      always:
        - name: デプロイ結果をログに記録
          debug:
            msg: "デプロイプロセス完了 - ホスト: {{ inventory_hostname }}, 時刻: {{ ansible_date_time.iso8601 }}"

        - name: nginx のステータスを確認
          command: systemctl is-active nginx
          register: nginx_status
          changed_when: false
          ignore_errors: true

        - name: 最終ステータスを表示
          debug:
            msg: "nginx の最終ステータス: {{ nginx_status.stdout }}"
```

```bash
$ ansible-playbook block_demo.yml
```

正常終了の場合（rescue は実行されません）:

```
PLAY [block/rescue/always デモ] *************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [現在の設定をバックアップ] ****************************************************
changed: [node1]

TASK [新しい設定を配置] ***********************************************************
changed: [node1]

TASK [設定チェック] ***************************************************************
ok: [node1]

TASK [nginx を再起動] ************************************************************
changed: [node1]

TASK [デプロイ結果をログに記録] ****************************************************
ok: [node1] =>
  msg: 'デプロイプロセス完了 - ホスト: node1, 時刻: 2026-07-06T10:00:00Z'

TASK [nginx のステータスを確認] ****************************************************
ok: [node1]

TASK [最終ステータスを表示] *******************************************************
ok: [node1] =>
  msg: 'nginx の最終ステータス: active'

PLAY RECAP *********************************************************************
node1                      : ok=8    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: rescue が発動する場合を確認

意図的に壊れた設定をデプロイして、rescue の動作を確認します。

```bash
$ vi block_rescue_test.yml
```

```yaml
---
- name: rescue の動作確認
  hosts: node1
  become: true

  tasks:
    - name: nginx デプロイ（意図的にエラーを発生させる）
      block:
        - name: 現在の設定をバックアップ
          copy:
            src: /etc/nginx/nginx.conf
            dest: /etc/nginx/nginx.conf.bak
            remote_src: true

        - name: 壊れた設定を配置
          copy:
            dest: /etc/nginx/sites-enabled/broken_test.conf
            content: |
              server {
                  listen 8080
                  # セミコロンが抜けている（構文エラー）
              }

        - name: 設定チェック（ここで失敗する）
          command: nginx -t
          changed_when: false
          register: config_check
          failed_when: config_check.rc != 0

        - name: このタスクは実行されない
          service:
            name: nginx
            state: restarted

      rescue:
        - name: "[rescue] 壊れた設定ファイルを削除"
          file:
            path: /etc/nginx/sites-enabled/broken_test.conf
            state: absent

        - name: "[rescue] 設定を復元して再チェック"
          command: nginx -t
          changed_when: false

        - name: "[rescue] エラー通知"
          debug:
            msg: "デプロイに失敗しました。壊れた設定を削除し、正常な状態に復元しました。"

      always:
        - name: "[always] 最終状態を確認"
          command: nginx -t
          register: final_check
          changed_when: false
          ignore_errors: true

        - name: "[always] 最終レポート"
          debug:
            msg: "最終設定チェック: {{ 'OK' if final_check.rc == 0 else 'NG' }}"
```

```bash
$ ansible-playbook block_rescue_test.yml
```

```
PLAY [rescue の動作確認] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [現在の設定をバックアップ] ****************************************************
changed: [node1]

TASK [壊れた設定を配置] ***********************************************************
changed: [node1]

TASK [設定チェック（ここで失敗する）] **********************************************
fatal: [node1]: FAILED! => changed=false
  cmd:
  - nginx
  - -t
  rc: 1
  stderr: |-
    nginx: [emerg] unexpected "}" in /etc/nginx/sites-enabled/broken_test.conf:4
    nginx: configuration file /etc/nginx/nginx.conf test failed

TASK [[rescue] 壊れた設定ファイルを削除] ******************************************
changed: [node1]

TASK [[rescue] 設定を復元して再チェック] ******************************************
ok: [node1]

TASK [[rescue] エラー通知] ********************************************************
ok: [node1] =>
  msg: デプロイに失敗しました。壊れた設定を削除し、正常な状態に復元しました。

TASK [[always] 最終状態を確認] ****************************************************
ok: [node1]

TASK [[always] 最終レポート] ******************************************************
ok: [node1] =>
  msg: '最終設定チェック: OK'

PLAY RECAP *********************************************************************
node1                      : ok=8    changed=3    unreachable=0    failed=0    skipped=0    rescued=1    ignored=0
```

`rescued=1` と表示され、rescueブロックが正常に動作したことがわかります。

---

## Section 6: 実践演習 — nginx ロールにバリデーションを追加

基礎演習6で作成したnginxロールに、設定チェックのバリデーションタスクを追加します。

### Step 1: ロールの tasks/main.yml を改良

基礎演習6のnginxロールに以下の改良を加えてください。ロールのディレクトリが `~/basic-roles/roles/nginx-simple/` にある前提です。

```bash
$ vi ~/basic-roles/roles/nginx-simple/tasks/main.yml
```

以下の内容に書き換えます。

```yaml
---
- name: nginx デプロイ（バリデーション付き）
  block:
    - name: nginx をインストール
      package:
        name: nginx
        state: present

    - name: パッケージ情報を収集
      package_facts:
        manager: auto

    - name: nginx がインストールされたことを確認
      assert:
        that:
          - "'nginx' in ansible_facts.packages"
        success_msg: "nginx のインストールを確認しました"
        fail_msg: "nginx のインストールに失敗しました"

    - name: nginx の設定ファイルを配置
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
        owner: root
        group: root
        mode: '0644'
      register: config_result

    - name: 設定ファイルの構文チェック
      command: nginx -t
      changed_when: false
      register: syntax_check
      failed_when: syntax_check.rc != 0

    - name: nginx を再起動（設定が変更された場合のみ）
      service:
        name: nginx
        state: restarted
        enabled: true
      when: config_result.changed

    - name: nginx を起動・有効化（初回）
      service:
        name: nginx
        state: started
        enabled: true
      when: not config_result.changed

  rescue:
    - name: "[rescue] 設定エラーの詳細を表示"
      debug:
        msg: "nginx の設定にエラーがあります: {{ syntax_check.stderr | default('不明なエラー') }}"

    - name: "[rescue] デプロイ失敗を通知"
      fail:
        msg: >
          nginx のデプロイに失敗しました。
          設定ファイルを確認してください。

  always:
    - name: "[always] nginx のサービス状態を確認"
      command: systemctl is-active nginx
      register: service_status
      changed_when: false
      ignore_errors: true

    - name: "[always] 最終ステータスレポート"
      debug:
        msg: "nginx サービス: {{ service_status.stdout | default('unknown') }}"
```

### Step 2: 改良したロールをテスト

```bash
$ cd ~/basic-roles
$ ansible-playbook site.yml
```

```
PLAY [This is my role-based playbook] ******************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : nginx をインストール] ***************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : パッケージ情報を収集] ****************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : nginx がインストールされたことを確認] *************************
ok: [node1] =>
  msg: nginx のインストールを確認しました
ok: [node2] =>
  msg: nginx のインストールを確認しました
ok: [node3] =>
  msg: nginx のインストールを確認しました

TASK [nginx-simple : nginx の設定ファイルを配置] ***********************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : 設定ファイルの構文チェック] ***********************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : nginx を再起動（設定が変更された場合のみ）] *******************
skipping: [node1]
skipping: [node2]
skipping: [node3]

TASK [nginx-simple : nginx を起動・有効化（初回）] *********************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : [always] nginx のサービス状態を確認] **************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : [always] 最終ステータスレポート] ******************************
ok: [node1] =>
  msg: 'nginx サービス: active'
ok: [node2] =>
  msg: 'nginx サービス: active'
ok: [node3] =>
  msg: 'nginx サービス: active'

PLAY RECAP *********************************************************************
node1                      : ok=9    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
node2                      : ok=9    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
node3                      : ok=9    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
```

これで、nginxロールにバリデーション（assert）、設定チェック（changed_when/failed_when）、エラーハンドリング（block/rescue/always）が組み込まれました。

---

## まとめ

この演習で学んだ内容:

| 機能 | 用途 |
|------|------|
| `register` | タスクの実行結果を変数に格納する |
| `when` | 条件に基づいてタスクの実行を制御する |
| `changed_when` | タスクの「変更あり」判定をカスタマイズする |
| `failed_when` | タスクの「失敗」判定をカスタマイズする |
| `assert` | 条件が真であることを検証し、偽の場合は失敗させる |
| `block/rescue/always` | タスク群の例外処理（try/catch/finally 相当） |

---

[基礎演習に戻る](../basic-roles/ex6.md) | [次へ進む](./ex2.md)
