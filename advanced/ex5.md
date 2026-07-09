# 応用演習 5 - タグと実行制御

この演習では、Ansibleのタグと実行制御について学びます。
タグによるタスクの選択的実行、`include_tasks` と `import_tasks` の違い、`serial` によるローリングアップデート、そして `delegate_to` と `run_once` による委任実行を実践します。

**前提条件:** 応用演習1〜4を完了していること

[前に戻る](./ex4.md) | [次へ進む](./ex6.md)

---

## Section 1: タグ — タスクの選択的実行

タグを使うと、Playbook内の特定のタスクだけを実行したり、スキップしたりすることができます。大規模なPlaybookの一部だけをテスト・実行する場合に非常に便利です。

### Step 1: タグの基本的な使い方

```bash
$ cd ~/advanced
```

```bash
$ vi tags_demo.yml
```

```yaml
---
- name: タグデモ
  hosts: node1
  become: true

  tasks:
    - name: nginx をインストール
      package:
        name: nginx
        state: present
      tags:
        - install
        - nginx

    - name: nginx の設定ファイルを配置
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
      tags:
        - config
        - nginx

    - name: index.html をデプロイ
      copy:
        dest: /usr/share/nginx/html/index.html
        content: |
          <h1>Hello from {{ inventory_hostname }}</h1>
      tags:
        - deploy
        - nginx

    - name: nginx を再起動
      service:
        name: nginx
        state: restarted
        enabled: true
      tags:
        - deploy
        - config
        - nginx

    - name: デプロイ後の確認
      uri:
        url: "http://localhost:8080"
        return_content: true
      register: result
      tags:
        - verify

    - name: 確認結果を表示
      debug:
        msg: "レスポンス: {{ result.content | trim }}"
      tags:
        - verify
```

特定のタグのタスクだけを実行します。

```bash
$ ansible-playbook tags_demo.yml --tags install
```

```
PLAY [タグデモ] ******************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx をインストール] *******************************************************
ok: [node1]

PLAY RECAP *********************************************************************
node1                      : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`install` タグが付いたタスクのみが実行されました。

### Step 2: --skip-tags でタグをスキップ

```bash
$ ansible-playbook tags_demo.yml --skip-tags config
```

```
PLAY [タグデモ] ******************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx をインストール] *******************************************************
ok: [node1]

TASK [index.html をデプロイ] ******************************************************
ok: [node1]

TASK [デプロイ後の確認] ***********************************************************
ok: [node1]

TASK [確認結果を表示] *************************************************************
ok: [node1] =>
  msg: 'レスポンス: <h1>Hello from node1</h1>'

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`config` タグを持つ「nginx の設定ファイルを配置」と「nginx を再起動」がスキップされました。`--skip-tags` は指定したタグを **含む** タスクをすべてスキップするため、他のタグ（`deploy` 等）も持っていてもスキップ対象になります。

### Step 3: 特殊タグ — always と never

```bash
$ vi special_tags.yml
```

```yaml
---
- name: 特殊タグデモ
  hosts: node1
  become: true

  tasks:
    - name: "[always] 開始ログ"
      debug:
        msg: "Playbook 実行開始: {{ ansible_date_time.iso8601 }}"
      tags:
        - always

    - name: パッケージ更新
      debug:
        msg: "パッケージを更新します"
      tags:
        - update

    - name: デバッグ情報（通常はスキップ）
      debug:
        msg: |
          デバッグ情報:
            ホスト: {{ inventory_hostname }}
            IP: {{ ansible_default_ipv4.address | d(ansible_host) }}
            OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
      tags:
        - never
        - debug

    - name: "[always] 終了ログ"
      debug:
        msg: "Playbook 実行完了"
      tags:
        - always
```

`always` タグは、`--tags` の指定に関係なく常に実行されます。

```bash
$ ansible-playbook special_tags.yml --tags update
```

```
PLAY [特殊タグデモ] ****************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [[always] 開始ログ] **********************************************************
ok: [node1] =>
  msg: 'Playbook 実行開始: 2026-07-06T10:00:00Z'

TASK [パッケージ更新] **************************************************************
ok: [node1] =>
  msg: パッケージを更新します

TASK [[always] 終了ログ] **********************************************************
ok: [node1] =>
  msg: Playbook 実行完了

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`never` タグは、明示的に `--tags debug` を指定しない限りスキップされます。

```bash
$ ansible-playbook special_tags.yml --tags debug
```

```
PLAY [特殊タグデモ] ****************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [[always] 開始ログ] **********************************************************
ok: [node1] =>
  msg: 'Playbook 実行開始: 2026-07-06T10:00:00Z'

TASK [デバッグ情報（通常はスキップ）] ************************************************
ok: [node1] =>
  msg: |-
    デバッグ情報:
      ホスト: node1
      IP: 172.20.0.11
      OS: RedHat 10.2

TASK [[always] 終了ログ] **********************************************************
ok: [node1] =>
  msg: Playbook 実行完了

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

| タグ | 動作 |
|------|------|
| 通常のタグ | `--tags` で指定した場合のみ実行される |
| `always` | `--tags` の指定に関係なく常に実行される |
| `never` | 明示的に `--tags` で指定しない限りスキップされる |

---

## Section 2: include_tasks vs import_tasks

タスクファイルの読み込みには `include_tasks`（動的）と `import_tasks`（静的）の2つの方法があります。

### Step 1: 動的読み込み（include_tasks）

```bash
$ vi tasks_install.yml
```

```yaml
---
- name: "{{ package_name }} をインストール"
  package:
    name: "{{ package_name }}"
    state: present

- name: "{{ package_name }} のバージョンを確認"
  command: "rpm -q {{ package_name }}"
  register: pkg_version
  changed_when: false

- name: "{{ package_name }} のバージョンを表示"
  debug:
    msg: "{{ pkg_version.stdout }}"
```

```bash
$ vi tasks_configure_nginx.yml
```

```yaml
---
- name: nginx の設定ファイルを配置
  copy:
    dest: /etc/nginx/sites-enabled/default.conf
    content: |
      server {
          listen 80;
          server_name localhost;
          location / {
              root /usr/share/nginx/html;
              index index.html;
          }
      }

- name: nginx を再起動
  service:
    name: nginx
    state: restarted
```

```bash
$ vi include_demo.yml
```

```yaml
---
- name: include_tasks デモ（動的読み込み）
  hosts: node1
  become: true

  tasks:
    - name: nginx をインストール（include_tasks）
      include_tasks: tasks_install.yml
      vars:
        package_name: nginx

    - name: OS ファミリに応じたタスクを読み込み
      include_tasks: "tasks_configure_{{ ansible_os_family | lower }}.yml"
      when: ansible_os_family == "RedHat"
```

`include_tasks` は**実行時**（ランタイム）にタスクファイルを読み込みます。そのため、ファイル名に変数を使用できます。

```bash
$ vi tasks_configure_redhat.yml
```

```yaml
---
- name: RedHat 固有の設定
  debug:
    msg: "RedHat 系 OS 固有の設定を適用中..."

- name: SELinux の状態を確認
  command: getenforce
  register: selinux_status
  changed_when: false
  ignore_errors: true

- name: SELinux の状態を表示
  debug:
    msg: "SELinux: {{ selinux_status.stdout | d('N/A') }}"
```

```bash
$ ansible-playbook include_demo.yml
```

```
PLAY [include_tasks デモ（動的読み込み）] ********************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx をインストール（include_tasks）] ****************************************
included: /root/advanced/tasks_install.yml for node1

TASK [nginx をインストール] *******************************************************
ok: [node1]

TASK [nginx のバージョンを確認] ****************************************************
ok: [node1]

TASK [nginx のバージョンを表示] ****************************************************
ok: [node1] =>
  msg: nginx-1.26.3-x.el10.x86_64

TASK [OS ファミリに応じたタスクを読み込み] ********************************************
included: /root/advanced/tasks_configure_redhat.yml for node1

TASK [RedHat 固有の設定] **********************************************************
ok: [node1] =>
  msg: RedHat 系 OS 固有の設定を適用中...

TASK [SELinux の状態を確認] ********************************************************
ok: [node1]

TASK [SELinux の状態を表示] ********************************************************
ok: [node1] =>
  msg: 'SELinux: Disabled'

PLAY RECAP *********************************************************************
node1                      : ok=9    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: 静的読み込み（import_tasks）

```bash
$ vi import_demo.yml
```

```yaml
---
- name: import_tasks デモ（静的読み込み）
  hosts: node1
  become: true

  tasks:
    - name: nginx をインストール（import_tasks）
      import_tasks: tasks_install.yml
      vars:
        package_name: nginx
      tags:
        - install
```

`import_tasks` は**パース時**にタスクファイルを読み込みます。タグや `when` は読み込まれた全タスクに適用されます。

```bash
$ ansible-playbook import_demo.yml --tags install
```

```
PLAY [import_tasks デモ（静的読み込み）] **********************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx をインストール] *******************************************************
ok: [node1]

TASK [nginx のバージョンを確認] ****************************************************
ok: [node1]

TASK [nginx のバージョンを表示] ****************************************************
ok: [node1] =>
  msg: nginx-1.26.3-x.el10.x86_64

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**import_tasks と include_tasks の違い:**

| 特性 | `import_tasks`（静的） | `include_tasks`（動的） |
|------|------|------|
| 読み込みタイミング | パース時 | 実行時 |
| ファイル名に変数 | 使用不可 | 使用可 |
| タグの適用 | 全タスクに適用 | include文のみに適用 |
| `when` の適用 | 全タスクに適用 | include文のみに適用 |
| `--list-tasks` | タスクが表示される | 表示されない |
| 推奨用途 | 固定的な構成 | 条件分岐による動的な構成 |

---

## Section 3: serial — ローリングアップデート

`serial` キーワードを使うと、一度に処理するホスト数を制限し、段階的にデプロイ（ローリングアップデート）を行うことができます。

### Step 1: serial の基本

まず、全ノードにnginxをインストールして起動しておきます。

```bash
$ ansible web -m package -a "name=nginx state=present" --become
$ ansible web -m service -a "name=nginx state=started enabled=yes" --become
```

```bash
$ vi rolling_update.yml
```

```yaml
---
- name: ローリングアップデート
  hosts: web
  become: true
  serial: 1

  pre_tasks:
    - name: "[pre] ヘルスチェック - 更新前"
      uri:
        url: "http://localhost:80"
        status_code: 200
      register: pre_check
      ignore_errors: true

    - name: "[pre] ヘルスチェック結果"
      debug:
        msg: "{{ inventory_hostname }}: 更新前ステータス {{ pre_check.status | d('接続不可') }}"

  tasks:
    - name: nginx を停止
      service:
        name: nginx
        state: stopped

    - name: コンテンツを更新
      copy:
        dest: /usr/share/nginx/html/index.html
        content: |
          <h1>{{ inventory_hostname }} - Updated v2.0</h1>
          <p>Updated at: {{ ansible_date_time.iso8601 }}</p>

    - name: 更新処理をシミュレート（待機）
      pause:
        seconds: 2

    - name: nginx を起動
      service:
        name: nginx
        state: started

  post_tasks:
    - name: "[post] ヘルスチェック - 更新後"
      uri:
        url: "http://localhost:80"
        status_code: 200
        return_content: true
      register: post_check

    - name: "[post] 更新確認"
      debug:
        msg: "{{ inventory_hostname }}: 更新完了 - {{ post_check.content | regex_findall('<h1>(.*)</h1>') | first }}"
```

```bash
$ ansible-playbook rolling_update.yml
```

`serial: 1` により、1台ずつ順番にアップデートが実行されます。

```
PLAY [ローリングアップデート] ********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [[pre] ヘルスチェック - 更新前] ************************************************
ok: [node1]

TASK [[pre] ヘルスチェック結果] ****************************************************
ok: [node1] =>
  msg: 'node1: 更新前ステータス 200'

TASK [nginx を停止] **************************************************************
changed: [node1]

TASK [コンテンツを更新] ************************************************************
changed: [node1]

TASK [更新処理をシミュレート（待機）] ************************************************
Pausing for 2 seconds

TASK [nginx を起動] **************************************************************
changed: [node1]

TASK [[post] ヘルスチェック - 更新後] ************************************************
ok: [node1]

TASK [[post] 更新確認] ************************************************************
ok: [node1] =>
  msg: 'node1: 更新完了 - node1 - Updated v2.0'

PLAY [ローリングアップデート] ********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node2]

... (node2, node3 も同様に1台ずつ実行) ...

PLAY RECAP *********************************************************************
node1                      : ok=9    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=9    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=9    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: serial のパーセント指定と max_fail_percentage

```bash
$ vi rolling_percent.yml
```

```yaml
---
- name: パーセント指定のローリングアップデート
  hosts: web
  become: true
  serial: "50%"
  max_fail_percentage: 25

  tasks:
    - name: コンテンツを更新
      copy:
        dest: /usr/share/nginx/html/index.html
        content: |
          <h1>{{ inventory_hostname }} - v3.0</h1>

    - name: nginx をリロード
      service:
        name: nginx
        state: reloaded

    - name: 更新確認
      debug:
        msg: "{{ inventory_hostname }}: v3.0 にアップデート完了"
```

```bash
$ ansible-playbook rolling_percent.yml
```

```
PLAY [パーセント指定のローリングアップデート] ******************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [コンテンツを更新] ************************************************************
changed: [node1]

TASK [nginx をリロード] ************************************************************
changed: [node1]

TASK [更新確認] ******************************************************************
ok: [node1] =>
  msg: 'node1: v3.0 にアップデート完了'

PLAY [パーセント指定のローリングアップデート] ******************************************

TASK [Gathering Facts] *********************************************************
ok: [node2]

TASK [コンテンツを更新] ************************************************************
changed: [node2]

TASK [nginx をリロード] ************************************************************
changed: [node2]

TASK [更新確認] ******************************************************************
ok: [node2] =>
  msg: 'node2: v3.0 にアップデート完了'

PLAY [パーセント指定のローリングアップデート] ******************************************

TASK [Gathering Facts] *********************************************************
ok: [node3]

TASK [コンテンツを更新] ************************************************************
changed: [node3]

TASK [nginx をリロード] ************************************************************
changed: [node3]

TASK [更新確認] ******************************************************************
ok: [node3] =>
  msg: 'node3: v3.0 にアップデート完了'

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`serial: "50%"` により、各バッチで50%（3台の50% = 1台、切り捨て）ずつ処理されます。

`max_fail_percentage: 25` は、各バッチ内で25%以上のホストが失敗した場合にPlaybook全体を中断する設定です。これにより、障害の拡大を防ぐことができます。

### Step 3: 段階的な serial

`serial` にリストを指定すると、バッチごとに処理台数を増やすことができます。最初のバッチで少数のホストを処理し、問題がなければ徐々に台数を増やすカナリアデプロイのパターンです。

```bash
$ vi rolling_staged.yml
```

```yaml
---
- name: 段階的ローリングアップデート
  hosts: web
  become: true
  serial:
    - 1
    - 50%
    - 100%

  tasks:
    - name: "バッチ内のホスト: {{ inventory_hostname }}"
      debug:
        msg: "{{ inventory_hostname }} を処理中"

    - name: コンテンツを更新
      copy:
        dest: /usr/share/nginx/html/index.html
        content: |
          <h1>{{ inventory_hostname }} - v4.0 (canary)</h1>

    - name: nginx をリロード
      service:
        name: nginx
        state: reloaded
```

```bash
$ ansible-playbook rolling_staged.yml
```

```
PLAY [段階的ローリングアップデート] **************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [バッチ内のホスト: node1] ****************************************************
ok: [node1] =>
  msg: node1 を処理中

TASK [コンテンツを更新] ************************************************************
changed: [node1]

TASK [nginx をリロード] ************************************************************
changed: [node1]

PLAY [段階的ローリングアップデート] **************************************************

TASK [Gathering Facts] *********************************************************
ok: [node2]

TASK [バッチ内のホスト: node2] ****************************************************
ok: [node2] =>
  msg: node2 を処理中

TASK [コンテンツを更新] ************************************************************
changed: [node2]

TASK [nginx をリロード] ************************************************************
changed: [node2]

PLAY [段階的ローリングアップデート] **************************************************

TASK [Gathering Facts] *********************************************************
ok: [node3]

TASK [バッチ内のホスト: node3] ****************************************************
ok: [node3] =>
  msg: node3 を処理中

TASK [コンテンツを更新] ************************************************************
changed: [node3]

TASK [nginx をリロード] ************************************************************
changed: [node3]

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

最初のバッチで1台（カナリア）、次のバッチで50%、最後に残りの全台が処理されます。

---

## Section 4: delegate_to / run_once — 委任実行

`delegate_to` を使うと、タスクを別のホストで実行できます。`run_once` と組み合わせることで、クラスタ全体に対する操作を効率的に行えます。

### Step 1: delegate_to の基本

```bash
$ vi delegate_demo.yml
```

```yaml
---
- name: delegate_to デモ
  hosts: web
  become: true
  gather_facts: true

  tasks:
    - name: 各ノードの時刻を取得
      command: date '+%Y-%m-%d %H:%M:%S'
      register: server_time
      changed_when: false

    - name: 取得した時刻をローカルに保存
      copy:
        content: "{{ inventory_hostname }} ({{ ansible_host }}): {{ server_time.stdout }}\n"
        dest: "/tmp/server_times_{{ inventory_hostname }}.txt"
      delegate_to: localhost
      become: false

    - name: 保存結果を確認
      command: "cat /tmp/server_times_{{ inventory_hostname }}.txt"
      delegate_to: localhost
      register: saved_time
      changed_when: false
      become: false

    - name: 結果を表示
      debug:
        msg: "{{ saved_time.stdout }}"
```

```bash
$ ansible-playbook delegate_demo.yml
```

```
PLAY [delegate_to デモ] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [各ノードの時刻を取得] ********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [取得した時刻をローカルに保存] **************************************************
changed: [node1 -> localhost]
changed: [node2 -> localhost]
changed: [node3 -> localhost]

TASK [保存結果を確認] **************************************************************
ok: [node1 -> localhost]
ok: [node2 -> localhost]
ok: [node3 -> localhost]

TASK [結果を表示] ******************************************************************
ok: [node1] =>
  msg: 'node1 (172.20.0.11): 2026-07-06 10:00:01'
ok: [node2] =>
  msg: 'node2 (172.20.0.12): 2026-07-06 10:00:01'
ok: [node3] =>
  msg: 'node3 (172.20.0.13): 2026-07-06 10:00:01'

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

出力中の `[node1 -> localhost]` は、タスクが node1 の代わりに localhost で実行されたことを示しています。

### Step 2: run_once と delegate_to の組み合わせ

```bash
$ vi run_once_demo.yml
```

```yaml
---
- name: run_once デモ
  hosts: web
  become: true
  gather_facts: true

  tasks:
    - name: "[run_once] 全ホストの一覧を生成"
      copy:
        content: |
          {% for host in groups['web'] %}
          {{ host }}: {{ hostvars[host]['ansible_default_ipv4']['address'] | d(hostvars[host]['ansible_host']) }}
          {% endfor %}
        dest: /tmp/host_list.txt
      delegate_to: localhost
      run_once: true
      become: false

    - name: "[run_once] 生成ファイルを確認"
      command: cat /tmp/host_list.txt
      delegate_to: localhost
      run_once: true
      register: host_list
      changed_when: false
      become: false

    - name: ホスト一覧を表示
      debug:
        msg: "{{ host_list.stdout }}"
      run_once: true

    - name: 各ホストからのヘルスチェック
      uri:
        url: "http://localhost:80"
        status_code: 200
      register: health_check

    - name: ヘルスチェック結果
      debug:
        msg: "{{ inventory_hostname }}: HTTP {{ health_check.status }}"
```

```bash
$ ansible-playbook run_once_demo.yml
```

```
PLAY [run_once デモ] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [[run_once] 全ホストの一覧を生成] ********************************************
changed: [node1 -> localhost]

TASK [[run_once] 生成ファイルを確認] ************************************************
ok: [node1 -> localhost]

TASK [ホスト一覧を表示] ************************************************************
ok: [node1] =>
  msg: |-
    node1: 172.20.0.11
    node2: 172.20.0.12
    node3: 172.20.0.13

TASK [各ホストからのヘルスチェック] **************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [ヘルスチェック結果] **********************************************************
ok: [node1] =>
  msg: 'node1: HTTP 200'
ok: [node2] =>
  msg: 'node2: HTTP 200'
ok: [node3] =>
  msg: 'node3: HTTP 200'

PLAY RECAP *********************************************************************
node1                      : ok=6    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`run_once: true` が付いたタスクは最初のホスト（node1）でのみ実行されます。ヘルスチェックのように `run_once` を付けないタスクは全ホストに対して実行されます。

---

## まとめ

この演習で学んだ内容:

| 機能 | 用途 |
|------|------|
| `tags` | タスクにタグを付けて選択的に実行・スキップする |
| `always` タグ | `--tags` 指定に関係なく常に実行される |
| `never` タグ | 明示的に指定しない限りスキップされる |
| `include_tasks` | 実行時にタスクファイルを動的に読み込む |
| `import_tasks` | パース時にタスクファイルを静的に読み込む |
| `serial` | 一度に処理するホスト数を制限する（ローリングアップデート） |
| `max_fail_percentage` | バッチ内の許容失敗率を指定する |
| `delegate_to` | タスクを別のホストで実行する |
| `run_once` | タスクを1回だけ実行する |

---

[前に戻る](./ex4.md) | [次へ進む](./ex6.md)
