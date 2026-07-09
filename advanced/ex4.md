# 応用演習 4 - データ処理とフィルタ

この演習では、Ansibleのデータ処理とフィルタについて学びます。
`default` フィルタによるデフォルト値設定、`set_fact` とループによるリスト/辞書の動的構築、文字列操作フィルタ、`json_query` による構造化データの問い合わせ、そしてsetupファクトの高度な加工を実践します。

**前提条件:** 応用演習1〜3を完了していること

[前に戻る](./ex3.md) | [次へ進む](./ex5.md)

---

## Section 1: default フィルタ — 未定義変数のデフォルト値

`default` フィルタ（短縮形: `d()`）を使うと、変数が未定義の場合にデフォルト値を設定できます。オプションパラメータの処理やロールの柔軟な設計に欠かせないフィルタです。

### Step 1: default フィルタの基本的な使い方

```bash
$ cd ~/advanced
```

```bash
$ vi default_filter.yml
```

```yaml
---
- name: default フィルタデモ
  hosts: localhost
  gather_facts: false

  tasks:
    - name: 未定義変数にデフォルト値を適用
      debug:
        msg: "値: {{ my_var | d('default_value') }}"

    - name: 定義済み変数ではデフォルト値は使われない
      debug:
        msg: "値: {{ my_var | d('default_value') }}"
      vars:
        my_var: "指定された値"

    - name: 空文字列はデフォルト値に置換されない（通常の default）
      debug:
        msg: "値: '{{ empty_var | d('fallback') }}'"
      vars:
        empty_var: ""

    - name: 空文字列もデフォルト値に置換する（boolean=true）
      debug:
        msg: "値: '{{ empty_var | d('fallback', true) }}'"
      vars:
        empty_var: ""
```

```bash
$ ansible-playbook default_filter.yml
```

以下のような出力が表示されます。

```
PLAY [default フィルタデモ] ********************************************************

TASK [未定義変数にデフォルト値を適用] **************************************************
ok: [localhost] =>
  msg: '値: default_value'

TASK [定義済み変数ではデフォルト値は使われない] ****************************************
ok: [localhost] =>
  msg: '値: 指定された値'

TASK [空文字列はデフォルト値に置換されない（通常の default）] **************************
ok: [localhost] =>
  msg: '値: '''

TASK [空文字列もデフォルト値に置換する（boolean=true）] ********************************
ok: [localhost] =>
  msg: '値: ''fallback'''

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: 実践的な使い方 — オプションパラメータの処理

`default` フィルタは、Playbookにオプションパラメータを持たせる場合に非常に便利です。

```bash
$ vi default_practical.yml
```

```yaml
---
- name: オプションパラメータの処理
  hosts: node1
  become: true

  tasks:
    - name: "パッケージをインストール（デフォルト: nginx）"
      package:
        name: "{{ package_name | d('nginx') }}"
        state: "{{ package_state | d('present') }}"

    - name: インストール結果を確認
      command: "rpm -q {{ package_name | d('nginx') }}"
      register: rpm_result
      changed_when: false

    - name: 結果を表示
      debug:
        msg: "インストール済み: {{ rpm_result.stdout }}"
```

```bash
$ ansible-playbook default_practical.yml
```

```
PLAY [オプションパラメータの処理] ****************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [パッケージをインストール（デフォルト: nginx）] **********************************
ok: [node1]

TASK [インストール結果を確認] ********************************************************
ok: [node1]

TASK [結果を表示] ******************************************************************
ok: [node1] =>
  msg: 'インストール済み: nginx-1.26.3-x.el10.x86_64'

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

extra-vars で上書きすることも可能です。

```bash
$ ansible-playbook default_practical.yml -e "package_name=curl"
```

---

## Section 2: set_fact とループ — リスト/辞書の動的構築

`set_fact` をループと組み合わせることで、リストや辞書を動的に構築できます。

### Step 1: ループでリストを構築

```bash
$ vi build_list.yml
```

```yaml
---
- name: リストの動的構築
  hosts: localhost
  gather_facts: false

  tasks:
    - name: サーバーリストを初期化して構築
      set_fact:
        server_list: "{{ server_list | d([]) + [item] }}"
      loop:
        - "web-server-01"
        - "web-server-02"
        - "db-server-01"

    - name: 構築したリストを表示
      debug:
        var: server_list

    - name: 条件付きでリストを構築
      set_fact:
        web_servers: "{{ web_servers | d([]) + [item] }}"
      loop:
        - "web-server-01"
        - "web-server-02"
        - "db-server-01"
        - "web-server-03"
      when: item is match('^web-')

    - name: Web サーバーのみのリスト
      debug:
        var: web_servers
```

```bash
$ ansible-playbook build_list.yml
```

```
PLAY [リストの動的構築] ************************************************************

TASK [サーバーリストを初期化して構築] **************************************************
ok: [localhost] => (item=web-server-01)
ok: [localhost] => (item=web-server-02)
ok: [localhost] => (item=db-server-01)

TASK [構築したリストを表示] **********************************************************
ok: [localhost] =>
  server_list:
  - web-server-01
  - web-server-02
  - db-server-01

TASK [条件付きでリストを構築] ********************************************************
ok: [localhost] => (item=web-server-01)
ok: [localhost] => (item=web-server-02)
skipping: [localhost] => (item=db-server-01)
ok: [localhost] => (item=web-server-03)

TASK [Web サーバーのみのリスト] ******************************************************
ok: [localhost] =>
  web_servers:
  - web-server-01
  - web-server-02
  - web-server-03

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: 2つのリストから辞書を構築

`zip` フィルタと `dict()` コンストラクタを使って、キーのリストと値のリストから辞書を構築します。

```bash
$ vi build_dict.yml
```

```yaml
---
- name: 辞書の動的構築
  hosts: localhost
  gather_facts: false
  vars:
    keys_list:
      - "name"
      - "role"
      - "port"
    values_list:
      - "web-server"
      - "frontend"
      - "8080"

  tasks:
    - name: zip で2つのリストを組み合わせる
      debug:
        msg: "{{ keys_list | zip(values_list) | list }}"

    - name: dict() で辞書に変換
      set_fact:
        server_info: "{{ dict(keys_list | zip(values_list)) }}"

    - name: 構築した辞書を表示
      debug:
        var: server_info

    - name: 辞書の個別要素にアクセス
      debug:
        msg: "サーバー名: {{ server_info.name }}, ロール: {{ server_info.role }}, ポート: {{ server_info.port }}"

    - name: ループで辞書にエントリを追加
      set_fact:
        host_map: "{{ host_map | d({}) | combine({item.name: item.ip}) }}"
      loop:
        - { name: "node1", ip: "172.20.0.11" }
        - { name: "node2", ip: "172.20.0.12" }
        - { name: "node3", ip: "172.20.0.13" }

    - name: 構築した host_map を表示
      debug:
        var: host_map
```

```bash
$ ansible-playbook build_dict.yml
```

```
PLAY [辞書の動的構築] **************************************************************

TASK [zip で2つのリストを組み合わせる] ************************************************
ok: [localhost] =>
  msg:
  - - name
    - web-server
  - - role
    - frontend
  - - port
    - '8080'

TASK [dict() で辞書に変換] **********************************************************
ok: [localhost]

TASK [構築した辞書を表示] ************************************************************
ok: [localhost] =>
  server_info:
    name: web-server
    port: '8080'
    role: frontend

TASK [辞書の個別要素にアクセス] ******************************************************
ok: [localhost] =>
  msg: 'サーバー名: web-server, ロール: frontend, ポート: 8080'

TASK [ループで辞書にエントリを追加] **************************************************
ok: [localhost] => (item={'name': 'node1', 'ip': '172.20.0.11'})
ok: [localhost] => (item={'name': 'node2', 'ip': '172.20.0.12'})
ok: [localhost] => (item={'name': 'node3', 'ip': '172.20.0.13'})

TASK [構築した host_map を表示] ******************************************************
ok: [localhost] =>
  host_map:
    node1: 172.20.0.11
    node2: 172.20.0.12
    node3: 172.20.0.13

PLAY RECAP *********************************************************************
localhost                  : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** `combine()` フィルタは辞書をマージします。同じキーがある場合は後から指定した値で上書きされます。

---

## Section 3: 文字列操作フィルタ

Ansibleでは、Pythonの文字列メソッドやJinja2フィルタを活用した文字列操作が可能です。

### Step 1: split(), join(), replace()

```bash
$ vi string_operations.yml
```

```yaml
---
- name: 文字列操作デモ
  hosts: localhost
  gather_facts: false
  vars:
    url: "https://www.example.com:8080/api/v1/users"
    csv_line: "server01,192.168.1.10,web,active"
    log_entry: "2026-07-06 ERROR [app] Connection timeout on host db-server-01"

  tasks:
    - name: split - 文字列を分割
      debug:
        msg:
          - "URL のパス部分: {{ url.split('/')[3:] | join('/') }}"
          - "CSV を分割: {{ csv_line.split(',') }}"
          - "ログの日付部分: {{ log_entry.split(' ')[0] }}"

    - name: join - リストを結合
      debug:
        msg:
          - "カンマ区切り: {{ ['node1', 'node2', 'node3'] | join(', ') }}"
          - "ハイフン区切り: {{ ['2026', '07', '06'] | join('-') }}"

    - name: replace - 文字列の置換
      debug:
        msg:
          - "置換前: {{ url }}"
          - "置換後: {{ url | replace('https', 'http') | replace('8080', '443') }}"

    - name: upper / lower / title / capitalize
      debug:
        msg:
          - "大文字: {{ 'hello world' | upper }}"
          - "小文字: {{ 'HELLO WORLD' | lower }}"
          - "タイトル: {{ 'hello world' | title }}"
          - "先頭大文字: {{ 'hello world' | capitalize }}"
```

```bash
$ ansible-playbook string_operations.yml
```

```
PLAY [文字列操作デモ] **************************************************************

TASK [split - 文字列を分割] ********************************************************
ok: [localhost] =>
  msg:
  - 'URL のパス部分: api/v1/users'
  - 'CSV を分割: [''server01'', ''192.168.1.10'', ''web'', ''active'']'
  - 'ログの日付部分: 2026-07-06'

TASK [join - リストを結合] **********************************************************
ok: [localhost] =>
  msg:
  - 'カンマ区切り: node1, node2, node3'
  - 'ハイフン区切り: 2026-07-06'

TASK [replace - 文字列の置換] ********************************************************
ok: [localhost] =>
  msg:
  - '置換前: https://www.example.com:8080/api/v1/users'
  - '置換後: http://www.example.com:443/api/v1/users'

TASK [upper / lower / title / capitalize] **************************************
ok: [localhost] =>
  msg:
  - '大文字: HELLO WORLD'
  - '小文字: hello world'
  - 'タイトル: Hello World'
  - '先頭大文字: Hello world'

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: regex_replace() と regex_findall()

正規表現を使った高度な文字列操作です。

```bash
$ vi regex_operations.yml
```

```yaml
---
- name: 正規表現フィルタデモ
  hosts: localhost
  gather_facts: false
  vars:
    filename: "server_backup_2026-07-06.tar.gz"
    log_output: |
      Server: web-01 Status: running Port: 8080
      Server: web-02 Status: stopped Port: 8081
      Server: db-01 Status: running Port: 5432

  tasks:
    - name: regex_replace - 正規表現置換
      debug:
        msg:
          - "拡張子を変更: {{ filename | regex_replace('\\.tar\\.gz$', '.zip') }}"
          - "日付を抽出: {{ filename | regex_replace('.*_(\\d{4}-\\d{2}-\\d{2}).*', '\\1') }}"

    - name: regex_findall - パターンに一致するすべての値を抽出
      debug:
        msg:
          - "サーバー名一覧: {{ log_output | regex_findall('Server: (\\S+)') }}"
          - "ポート番号一覧: {{ log_output | regex_findall('Port: (\\d+)') }}"

    - name: regex_findall + map + extract パターン
      set_fact:
        server_names: "{{ log_output | regex_findall('Server: (\\S+)') }}"
        server_ports: "{{ log_output | regex_findall('Port: (\\d+)') }}"

    - name: 抽出した値を組み合わせて表示
      debug:
        msg: "{{ item.0 }} -> ポート {{ item.1 }}"
      loop: "{{ server_names | zip(server_ports) | list }}"

    - name: map + extract パターン（インデックスで値を取り出す）
      debug:
        msg: "最初のサーバー: {{ [0] | map('extract', server_names) | join() }}"
```

```bash
$ ansible-playbook regex_operations.yml
```

```
PLAY [正規表現フィルタデモ] **********************************************************

TASK [regex_replace - 正規表現置換] **************************************************
ok: [localhost] =>
  msg:
  - '拡張子を変更: server_backup_2026-07-06.zip'
  - '日付を抽出: 2026-07-06'

TASK [regex_findall - パターンに一致するすべての値を抽出] ****************************
ok: [localhost] =>
  msg:
  - 'サーバー名一覧: [''web-01'', ''web-02'', ''db-01'']'
  - 'ポート番号一覧: [''8080'', ''8081'', ''5432'']'

TASK [regex_findall + map + extract パターン] ************************************
ok: [localhost]

TASK [抽出した値を組み合わせて表示] **************************************************
ok: [localhost] => (item=['web-01', '8080'])
  msg: web-01 -> ポート 8080
ok: [localhost] => (item=['web-02', '8081'])
  msg: web-02 -> ポート 8081
ok: [localhost] => (item=['db-01', '5432'])
  msg: db-01 -> ポート 5432

TASK [map + extract パターン（インデックスで値を取り出す）] **************************
ok: [localhost] =>
  msg: '最初のサーバー: web-01'

PLAY RECAP *********************************************************************
localhost                  : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 4: json_query — JMESPath による構造化データの問い合わせ

`json_query` フィルタは、[JMESPath](https://jmespath.org/) 構文を使ってJSONデータを問い合わせることができます。複雑なデータ構造から必要な情報を効率的に抽出する場合に威力を発揮します。

### Step 1: json_query の基本

```bash
$ vi json_query_basic.yml
```

```yaml
---
- name: json_query 基本デモ
  hosts: localhost
  gather_facts: false

  tasks:
    - name: サンプルデータを定義
      set_fact:
        servers:
          - name: "web-01"
            role: "frontend"
            port: 8080
            status: "running"
            tags: ["production", "web"]
          - name: "web-02"
            role: "frontend"
            port: 8081
            status: "stopped"
            tags: ["staging", "web"]
          - name: "db-01"
            role: "database"
            port: 5432
            status: "running"
            tags: ["production", "database"]
          - name: "db-02"
            role: "database"
            port: 5433
            status: "running"
            tags: ["staging", "database"]

    - name: 全サーバー名を取得
      debug:
        msg: "{{ servers | community.general.json_query('[*].name') }}"

    - name: running 状態のサーバーを取得
      debug:
        msg: "{{ servers | community.general.json_query('[?status==`running`].name') }}"

    - name: frontend ロールのサーバーのポート番号を取得
      debug:
        msg: "{{ servers | community.general.json_query('[?role==`frontend`].port') }}"

    - name: production タグを持つサーバー名を取得
      debug:
        msg: "{{ servers | community.general.json_query('[?contains(tags, `production`)].name') }}"
```

```bash
$ ansible-playbook json_query_basic.yml
```

```
PLAY [json_query 基本デモ] ********************************************************

TASK [サンプルデータを定義] **********************************************************
ok: [localhost]

TASK [全サーバー名を取得] ************************************************************
ok: [localhost] =>
  msg:
  - web-01
  - web-02
  - db-01
  - db-02

TASK [running 状態のサーバーを取得] **************************************************
ok: [localhost] =>
  msg:
  - web-01
  - db-01
  - db-02

TASK [frontend ロールのサーバーのポート番号を取得] ************************************
ok: [localhost] =>
  msg:
  - 8080
  - 8081

TASK [production タグを持つサーバー名を取得] ******************************************
ok: [localhost] =>
  msg:
  - web-01
  - db-01

PLAY RECAP *********************************************************************
localhost                  : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: json_query の応用 — ネストされたデータの問い合わせ

```bash
$ vi json_query_advanced.yml
```

```yaml
---
- name: json_query 応用デモ
  hosts: localhost
  gather_facts: false

  tasks:
    - name: ネストされたサンプルデータを定義
      set_fact:
        infrastructure:
          datacenters:
            - name: "dc-tokyo"
              location: "Tokyo"
              clusters:
                - name: "cluster-1"
                  servers:
                    - name: "srv-01"
                      cpu: 4
                      memory: 8192
                    - name: "srv-02"
                      cpu: 8
                      memory: 16384
                - name: "cluster-2"
                  servers:
                    - name: "srv-03"
                      cpu: 16
                      memory: 32768
            - name: "dc-osaka"
              location: "Osaka"
              clusters:
                - name: "cluster-3"
                  servers:
                    - name: "srv-04"
                      cpu: 4
                      memory: 8192

    - name: 全データセンター名を取得
      debug:
        msg: "{{ infrastructure | community.general.json_query('datacenters[*].name') }}"

    - name: 全サーバー名を取得（ネストされた構造から）
      debug:
        msg: "{{ infrastructure | community.general.json_query('datacenters[*].clusters[*].servers[*].name') }}"

    - name: フラットなサーバーリストを取得
      debug:
        msg: "{{ infrastructure | community.general.json_query('datacenters[].clusters[].servers[].name') }}"

    - name: メモリが16GB以上のサーバーを取得
      debug:
        msg: "{{ infrastructure | community.general.json_query('datacenters[].clusters[].servers[?memory>=`16384`].name') }}"

    - name: 変数を使ったクエリ
      debug:
        msg: "{{ infrastructure | community.general.json_query(jmespath_query) }}"
      vars:
        target_dc: "dc-tokyo"
        jmespath_query: "datacenters[?name=='{{ target_dc }}'].clusters[].servers[].name"
```

```bash
$ ansible-playbook json_query_advanced.yml
```

```
PLAY [json_query 応用デモ] ********************************************************

TASK [ネストされたサンプルデータを定義] **********************************************
ok: [localhost]

TASK [全データセンター名を取得] ******************************************************
ok: [localhost] =>
  msg:
  - dc-tokyo
  - dc-osaka

TASK [全サーバー名を取得（ネストされた構造から）] ************************************
ok: [localhost] =>
  msg:
  - - - srv-01
      - srv-02
    - - srv-03
  - - - srv-04

TASK [フラットなサーバーリストを取得] ************************************************
ok: [localhost] =>
  msg:
  - srv-01
  - srv-02
  - srv-03
  - srv-04

TASK [メモリが16GB以上のサーバーを取得] **********************************************
ok: [localhost] =>
  msg:
  -   - srv-02
  -   - srv-03
  - []

TASK [変数を使ったクエリ] ************************************************************
ok: [localhost] =>
  msg:
  - srv-01
  - srv-02
  - srv-03

PLAY RECAP *********************************************************************
localhost                  : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** `json_query` で JMESPath のリテラル文字列を使う場合、バッククォート（`` ` ``）で囲みます。Ansible変数を含める場合は、`vars:` で別途クエリを定義すると可読性が向上します。

---

## Section 5: setup ファクトの加工

`ansible_facts` から取得したファクト情報を、`select`、`selectattr`、`map`、`items2dict`、`dict2items` などのフィルタで加工します。

### Step 1: select と selectattr

```bash
$ vi process_facts.yml
```

```yaml
---
- name: setup ファクトの加工
  hosts: node1
  gather_facts: true

  tasks:
    - name: 全ネットワークインターフェースを表示
      debug:
        var: ansible_interfaces

    - name: eth で始まるインターフェースのみ抽出
      debug:
        msg: "{{ ansible_interfaces | select('match', '^eth') | list }}"

    - name: マウントポイント情報を加工
      debug:
        msg: "{{ ansible_mounts | selectattr('mount', 'equalto', '/') | list }}"
      when: ansible_mounts | length > 0

    - name: マウントポイントのパスのみ抽出
      debug:
        msg: "{{ ansible_mounts | map(attribute='mount') | list }}"
      when: ansible_mounts | length > 0

    - name: マウントポイント情報を取得（コンテナ環境用フォールバック）
      command: df -h /
      register: df_result
      changed_when: false
      when: ansible_mounts | length == 0

    - name: マウントポイント情報を表示（コンテナ環境）
      debug:
        msg: "{{ df_result.stdout_lines }}"
      when: ansible_mounts | length == 0

    - name: 利用可能なメモリ情報をフォーマット
      debug:
        msg: >
          合計メモリ: {{ ansible_memtotal_mb }} MB,
          空きメモリ: {{ ansible_memfree_mb }} MB,
          使用率: {{ ((ansible_memtotal_mb - ansible_memfree_mb) / ansible_memtotal_mb * 100) | round(1) }}%
```

```bash
$ ansible-playbook process_facts.yml
```

```
PLAY [setup ファクトの加工] ********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [全ネットワークインターフェースを表示] ********************************************
ok: [node1] =>
  ansible_interfaces:
  - lo
  - eth0

TASK [eth で始まるインターフェースのみ抽出] ********************************************
ok: [node1] =>
  msg:
  - eth0

TASK [マウントポイント情報を加工] ****************************************************
ok: [node1] =>
  msg:
  - block_available: 1234567
    block_size: 4096
    block_total: 2345678
    block_used: 1111111
    device: overlay
    fstype: overlay
    mount: /
    ...

TASK [マウントポイントのパスのみ抽出] ************************************************
ok: [node1] =>
  msg:
  - /
  - /etc/resolv.conf
  - /etc/hostname
  - /etc/hosts

**Note:** 実機環境では上記のようにマウント情報が表示されます。コンテナ環境では `ansible_mounts` が空のリストを返すことがあり、その場合はマウント関連のタスクがスキップされ、代わりにフォールバックタスクが `df -h /` の結果を表示します。

TASK [利用可能なメモリ情報をフォーマット] **********************************************
ok: [node1] =>
  msg: '合計メモリ: 1024 MB, 空きメモリ: 512 MB, 使用率: 50.0%'

PLAY RECAP *********************************************************************
node1                      : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: dict2items と items2dict

辞書とリストの相互変換を行うフィルタです。

```bash
$ vi dict_conversion.yml
```

```yaml
---
- name: dict2items / items2dict デモ
  hosts: localhost
  gather_facts: false
  vars:
    server_ports:
      nginx: 80
      app: 8080
      db: 5432

  tasks:
    - name: 辞書を表示
      debug:
        var: server_ports

    - name: dict2items - 辞書をリストに変換
      debug:
        msg: "{{ server_ports | dict2items }}"

    - name: dict2items でフィルタリング（ポート番号 1024 以上）
      debug:
        msg: "{{ server_ports | dict2items | selectattr('value', '>=', 1024) | list }}"

    - name: フィルタ後に items2dict で辞書に戻す
      set_fact:
        high_ports: "{{ server_ports | dict2items | selectattr('value', '>=', 1024) | items2dict }}"

    - name: 変換結果を表示
      debug:
        var: high_ports

    - name: カスタムキー名で dict2items
      set_fact:
        custom_list: "{{ server_ports | dict2items(key_name='service', value_name='port') }}"

    - name: カスタムキー名の結果
      debug:
        var: custom_list
```

```bash
$ ansible-playbook dict_conversion.yml
```

```
PLAY [dict2items / items2dict デモ] **********************************************

TASK [辞書を表示] ******************************************************************
ok: [localhost] =>
  server_ports:
    app: 8080
    db: 5432
    nginx: 80

TASK [dict2items - 辞書をリストに変換] **********************************************
ok: [localhost] =>
  msg:
  - key: nginx
    value: 80
  - key: app
    value: 8080
  - key: db
    value: 5432

TASK [dict2items でフィルタリング（ポート番号 1024 以上）] ****************************
ok: [localhost] =>
  msg:
  - key: app
    value: 8080
  - key: db
    value: 5432

TASK [フィルタ後に items2dict で辞書に戻す] ******************************************
ok: [localhost]

TASK [変換結果を表示] **************************************************************
ok: [localhost] =>
  high_ports:
    app: 8080
    db: 5432

TASK [カスタムキー名で dict2items] **************************************************
ok: [localhost]

TASK [カスタムキー名の結果] **********************************************************
ok: [localhost] =>
  custom_list:
  - port: 80
    service: nginx
  - port: 8080
    service: app
  - port: 5432
    service: db

PLAY RECAP *********************************************************************
localhost                  : ok=7    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 6: 実践演習 — ホスト情報レポートの生成

ここまで学んだフィルタを組み合わせて、全Webノードの情報を収集し、テンプレートを使ってサマリレポートを生成します。

### Step 1: テンプレートファイルの作成

```bash
$ mkdir -p templates
$ vi templates/host_report.j2
```

```jinja2
=== ホスト情報レポート ===
生成日時: {{ ansible_date_time.iso8601 | d('N/A') }}

{% for host in groups['web'] %}
--- {{ host }} ---
  IP アドレス : {{ hostvars[host]['ansible_default_ipv4']['address'] | d('N/A') }}
  OS          : {{ hostvars[host]['ansible_distribution'] | d('N/A') }} {{ hostvars[host]['ansible_distribution_version'] | d('') }}
  カーネル    : {{ hostvars[host]['ansible_kernel'] | d('N/A') }}
  CPU 数      : {{ hostvars[host]['ansible_processor_vcpus'] | d('N/A') }}
  メモリ      : {{ hostvars[host]['ansible_memtotal_mb'] | d('N/A') }} MB
  インターフェース: {{ hostvars[host]['ansible_interfaces'] | select('match', '^eth') | join(', ') }}

{% endfor %}
=== サマリ ===
  合計ホスト数: {{ groups['web'] | length }}
  合計メモリ  : {{ groups['web'] | map('extract', hostvars, 'ansible_memtotal_mb') | map('int') | sum }} MB
```

### Step 2: レポート生成Playbookの作成

```bash
$ vi host_report.yml
```

```yaml
---
- name: ホスト情報の収集
  hosts: web
  gather_facts: true

- name: レポートの生成
  hosts: localhost
  gather_facts: true

  tasks:
    - name: Web ノードのサマリを構築
      set_fact:
        web_summary: "{{ web_summary | d([]) + [node_info] }}"
      vars:
        node_info:
          name: "{{ item }}"
          ip: "{{ hostvars[item]['ansible_default_ipv4']['address'] | d('N/A') }}"
          os: "{{ hostvars[item]['ansible_distribution'] | d('N/A') }} {{ hostvars[item]['ansible_distribution_version'] | d('') }}"
          memory_mb: "{{ hostvars[item]['ansible_memtotal_mb'] | d(0) }}"
      loop: "{{ groups['web'] }}"

    - name: サマリを表示
      debug:
        var: web_summary

    - name: レポートファイルを生成
      template:
        src: templates/host_report.j2
        dest: /tmp/host_report.txt
      delegate_to: localhost

    - name: 生成されたレポートを表示
      command: cat /tmp/host_report.txt
      register: report_content
      changed_when: false
      delegate_to: localhost

    - name: レポート内容
      debug:
        msg: "{{ report_content.stdout }}"
```

```bash
$ ansible-playbook host_report.yml
```

```
PLAY [ホスト情報の収集] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

PLAY [レポートの生成] **************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [Web ノードのサマリを構築] ******************************************************
ok: [localhost] => (item=node1)
ok: [localhost] => (item=node2)
ok: [localhost] => (item=node3)

TASK [サマリを表示] ****************************************************************
ok: [localhost] =>
  web_summary:
  - ip: 172.20.0.11
    memory_mb: '1024'
    name: node1
    os: RedHat 10.2
  - ip: 172.20.0.12
    memory_mb: '1024'
    name: node2
    os: RedHat 10.2
  - ip: 172.20.0.13
    memory_mb: '1024'
    name: node3
    os: RedHat 10.2

TASK [レポートファイルを生成] ********************************************************
changed: [localhost]

TASK [生成されたレポートを表示] ******************************************************
ok: [localhost]

TASK [レポート内容] ****************************************************************
ok: [localhost] =>
  msg: |-
    === ホスト情報レポート ===
    生成日時: 2026-07-06T10:00:00Z

    --- node1 ---
      IP アドレス : 172.20.0.11
      OS          : RedHat 10.2
      カーネル    : 6.17.7-300.fc43.aarch64
      CPU 数      : 2
      メモリ      : 1024 MB
      インターフェース: eth0

    --- node2 ---
      IP アドレス : 172.20.0.12
      OS          : RedHat 10.2
      カーネル    : 6.17.7-300.fc43.aarch64
      CPU 数      : 2
      メモリ      : 1024 MB
      インターフェース: eth0

    --- node3 ---
      IP アドレス : 172.20.0.13
      OS          : RedHat 10.2
      カーネル    : 6.17.7-300.fc43.aarch64
      CPU 数      : 2
      メモリ      : 1024 MB
      インターフェース: eth0

    === サマリ ===
      合計ホスト数: 3
      合計メモリ  : 3072 MB

PLAY RECAP *********************************************************************
localhost                  : ok=6    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node1                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## まとめ

この演習で学んだ内容:

| フィルタ/機能 | 用途 |
|------|------|
| `default` / `d()` | 未定義変数にデフォルト値を設定する |
| `set_fact` + ループ | リストや辞書を動的に構築する |
| `combine` | 辞書をマージする |
| `split` / `join` / `replace` | 文字列の分割・結合・置換 |
| `regex_replace` / `regex_findall` | 正規表現による文字列操作 |
| `map` + `extract` | インデックスで値を取り出す |
| `json_query` | JMESPath で構造化データを問い合わせる |
| `select` / `selectattr` | リストのフィルタリング |
| `dict2items` / `items2dict` | 辞書とリストの相互変換 |
| `map(attribute=...)` | リストの特定属性を抽出する |

---

[前に戻る](./ex3.md) | [次へ進む](./ex5.md)
