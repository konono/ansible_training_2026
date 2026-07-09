# 応用演習 9 - インベントリとホスト管理

[前に戻る](./ex8.md)

------

基礎演習では静的なINI形式のインベントリを使用してきました。この演習では、YAML形式のインベントリ、`group_vars` / `host_vars` ディレクトリの活用、`hostvars` による他ホストの情報へのアクセス、動的グループの作成、そしてマルチ環境でのインベントリ管理について学びます。

インベントリの設計は、Ansibleプロジェクトの保守性とスケーラビリティに大きく影響します。

## Section 1: YAML形式 vs INI形式のインベントリ

### Step 1: INI形式のインベントリ

これまで使用してきたINI形式は、シンプルで読みやすいのが特徴です。

```bash
$ mkdir ~/inventory-lab
$ cd ~/inventory-lab
$ vi inventory_ini
```

```ini
[web]
node1 ansible_host=172.20.0.11
node2 ansible_host=172.20.0.12
node3 ansible_host=172.20.0.13

[loadbalancer]
lb ansible_host=172.20.0.14

[web:vars]
http_port=80
app_env=production

[all:vars]
ansible_user=root
ansible_ssh_pass=password
ansible_port=22
```

### Step 2: YAML形式のインベントリ

同じインベントリをYAML形式で記述します。

```bash
$ vi inventory_yaml.yml
```

```yaml
all:
  vars:
    ansible_user: root
    ansible_ssh_pass: password
    ansible_port: 22
  children:
    web:
      vars:
        http_port: 80
        app_env: production
      hosts:
        node1:
          ansible_host: 172.20.0.11
        node2:
          ansible_host: 172.20.0.12
        node3:
          ansible_host: 172.20.0.13
    loadbalancer:
      hosts:
        lb:
          ansible_host: 172.20.0.14
```

### Step 3: 比較と使い分け

| 観点 | INI形式 | YAML形式 |
|------|---------|----------|
| 読みやすさ | シンプルで直感的 | 階層構造が明確 |
| 複雑な変数 | リスト・辞書型が扱いにくい | ネストした構造を自然に記述できる |
| 子グループ | `[parent:children]` で記述 | `children:` キーで直接ネスト |
| レガシー対応 | 多くの既存プロジェクトで使用 | 新規プロジェクトで推奨 |
| ファイル拡張子 | なし、または `.ini` | `.yml` または `.yaml` |

---

**推奨**: 新規プロジェクトでは **YAML形式** を使用しましょう。特に変数にリストや辞書を含む場合、YAML形式の方が自然に記述できます。

---

### Step 4: 動作確認

どちらの形式でも同じように動作することを確認します。

```bash
$ ansible -i inventory_ini web --list-hosts
```

```
  hosts (3):
    node1
    node2
    node3
```

```bash
$ ansible -i inventory_yaml.yml web --list-hosts
```

```
  hosts (3):
    node1
    node2
    node3
```

### Step 5: 子グループの定義

YAML形式では、グループを階層的にネストできます。

```bash
$ vi inventory_nested.yml
```

```yaml
all:
  vars:
    ansible_user: root
    ansible_ssh_pass: password
    ansible_port: 22
  children:
    app_servers:
      children:
        web:
          hosts:
            node1:
              ansible_host: 172.20.0.11
            node2:
              ansible_host: 172.20.0.12
        api:
          hosts:
            node3:
              ansible_host: 172.20.0.13
    loadbalancer:
      hosts:
        lb:
          ansible_host: 172.20.0.14
```

```bash
$ ansible -i inventory_nested.yml app_servers --list-hosts
```

```
  hosts (3):
    node1
    node2
    node3
```

`app_servers` グループには、子グループ `web` と `api` の全ホストが含まれます。

## Section 2: group_vars / host_vars ディレクトリ

### Step 1: ディレクトリ構成の作成

インベントリの変数をインベントリファイルから分離し、ディレクトリで管理します。

```bash
$ mkdir -p group_vars host_vars
```

### Step 2: group_vars/all.yml — 全ホスト共通変数

```bash
$ vi group_vars/all.yml
```

```yaml
---
ansible_user: root
ntp_server: ntp.example.com
dns_servers:
  - 8.8.8.8
  - 8.8.4.4
```

`all` は暗黙のグループで、全てのホストに適用されます。`ansible_user` はインベントリファイルの `all.vars` でも定義していますが、`group_vars/all.yml` の方が優先されるため、ここでも同じ値を設定する必要があります。

### Step 3: group_vars/web.yml — webグループ変数

```bash
$ vi group_vars/web.yml
```

```yaml
---
http_port: 80
app_env: production
app_packages:
  - nginx
  - python3
```

ファイル名はグループ名と一致させます（`web` グループ → `web.yml`）。

### Step 4: host_vars/node1.yml — ホスト固有変数

```bash
$ vi host_vars/node1.yml
```

```yaml
---
node_role: primary
backup_enabled: true
custom_port: 8080
```

ファイル名はホスト名と一致させます（ホスト名 `node1` → `node1.yml`）。

### Step 5: ディレクトリ形式の group_vars

グループの変数が多い場合、ファイルではなくディレクトリにすることもできます。

```bash
$ rm group_vars/web.yml
$ mkdir group_vars/web
$ vi group_vars/web/main.yml
```

```yaml
---
http_port: 80
```

```bash
$ vi group_vars/web/packages.yml
```

```yaml
---
app_packages:
  - nginx
  - python3
```

ディレクトリ内の全ての `.yml` ファイルが自動的に読み込まれます。変数が多い場合に、論理的な単位でファイルを分割できます。

### Step 6: 動作確認

```bash
$ vi ansible.cfg
```

```ini
[defaults]
inventory = ./inventory_yaml.yml
retry_files_enabled = False
host_key_checking = False
stdout_callback = ansible.builtin.default
callback_result_format = yaml
```

```bash
$ vi check_vars.yml
```

```yaml
---
- name: group_vars / host_vars の確認
  hosts: web
  gather_facts: false
  tasks:
    - name: 全ホスト共通変数を表示
      debug:
        msg: "NTP: {{ ntp_server }}, DNS: {{ dns_servers }}"

    - name: webグループ変数を表示
      debug:
        msg: "Port: {{ http_port }}, Env: {{ app_env }}"

    - name: ホスト固有変数を表示（node1のみ）
      debug:
        msg: "Role: {{ node_role }}, Custom Port: {{ custom_port }}"
      when: node_role is defined
```

```bash
$ ansible-playbook check_vars.yml
```

```
PLAY [group_vars / host_vars の確認] ******************************************************

TASK [全ホスト共通変数を表示] *************************************************************
ok: [node1] =>
    msg: 'NTP: ntp.example.com, DNS: [''8.8.8.8'', ''8.8.4.4'']'
ok: [node2] =>
    msg: 'NTP: ntp.example.com, DNS: [''8.8.8.8'', ''8.8.4.4'']'
ok: [node3] =>
    msg: 'NTP: ntp.example.com, DNS: [''8.8.8.8'', ''8.8.4.4'']'

TASK [webグループ変数を表示] *************************************************************
ok: [node1] =>
    msg: 'Port: 80, Env: production'
ok: [node2] =>
    msg: 'Port: 80, Env: production'
ok: [node3] =>
    msg: 'Port: 80, Env: production'

TASK [ホスト固有変数を表示（node1のみ）] **************************************************
skipping: [node2]
ok: [node1] =>
    msg: 'Role: primary, Custom Port: 8080'
skipping: [node3]

PLAY RECAP *******************************************************************************
node1                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=2    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
node3                      : ok=2    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
```

`node_role` は `host_vars/node1.yml` でのみ定義されているため、node2とnode3ではタスクがスキップされます。

## Section 3: hostvars によるアクセスパターン

### Step 1: hostvars の基本

`hostvars` は、全ホストの変数にアクセスできる特殊な辞書変数です。他のホストの情報を参照する場合に使用します。

```bash
$ vi hostvars_demo.yml
```

```yaml
---
- name: hostvars のデモ
  hosts: web
  gather_facts: false
  tasks:
    - name: 自分自身のホスト変数にアクセス
      debug:
        msg: "{{ hostvars[inventory_hostname]['ansible_host'] }}"

    - name: 全webホストのIPアドレスを表示（node1でのみ実行）
      debug:
        msg: "{{ item }} => {{ hostvars[item]['ansible_host'] }}"
      loop: "{{ groups['web'] }}"
      run_once: true
```

```bash
$ ansible-playbook hostvars_demo.yml
```

```
TASK [自分自身のホスト変数にアクセス] *****************************************************
ok: [node1] =>
    msg: 172.20.0.11
ok: [node2] =>
    msg: 172.20.0.12
ok: [node3] =>
    msg: 172.20.0.13

TASK [全webホストのIPアドレスを表示（node1でのみ実行）] *************************************
ok: [node1] => (item=node1) =>
    msg: node1 => 172.20.0.11
ok: [node1] => (item=node2) =>
    msg: node2 => 172.20.0.12
ok: [node1] => (item=node3) =>
    msg: node3 => 172.20.0.13
```

### Step 2: テンプレートで /etc/hosts 形式のファイルを生成する

`hostvars` の典型的な活用例として、インベントリ情報から `/etc/hosts` 形式のファイルを動的に生成するパターンがあります。

**Note:** コンテナ環境では `/etc/hosts` はコンテナランタイムがマウントしているため直接書き込めません（`Device or resource busy` エラーになります）。ここでは `/tmp/generated_hosts` に生成して内容を確認します。本番環境では `dest: /etc/hosts` に変更してください。

```bash
$ mkdir templates
$ vi templates/hosts.j2
```

```jinja2
# Ansible managed - Do not edit manually
127.0.0.1   localhost localhost.localdomain

# Lab hosts
{% for host in groups['all'] %}
{{ hostvars[host]['ansible_default_ipv4']['address'] }}   {{ host }}
{% endfor %}
```

```bash
$ vi generate_hosts.yml
```

```yaml
---
- name: /etc/hosts 形式ファイルをインベントリから生成する
  hosts: all
  gather_facts: true
  tasks: []

- name: テンプレートの生成と表示
  hosts: localhost
  gather_facts: false
  tasks:
    - name: /etc/hosts 形式ファイルをテンプレートから生成
      template:
        src: templates/hosts.j2
        dest: /tmp/generated_hosts

    - name: 生成結果を表示
      command: cat /tmp/generated_hosts
      register: result
      changed_when: false

    - name: 出力
      debug:
        msg: "{{ result.stdout }}"
```

```bash
$ ansible-playbook generate_hosts.yml
```

```
PLAY [/etc/hosts 形式ファイルをインベントリから生成する] ****************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

PLAY [テンプレートの生成と表示] ************************************************

TASK [/etc/hosts 形式ファイルをテンプレートから生成] ****************************
changed: [localhost]

TASK [生成結果を表示] **********************************************************
ok: [localhost]

TASK [出力] ********************************************************************
ok: [localhost] =>
  msg: |-
    # Ansible managed - Do not edit manually
    127.0.0.1   localhost localhost.localdomain

    # Lab hosts
    172.20.0.11   node1
    172.20.0.12   node2
    172.20.0.13   node3
    172.20.0.14   lb

PLAY RECAP *********************************************************************
lb                         : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
localhost                  : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node1                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 3: 他ホストのファクトをテンプレートで使用する

他のホストで収集されたファクト情報をテンプレート内で参照するには、まず対象ホストでファクトを収集しておく必要があります。

```bash
$ vi render_config.yml
```

```yaml
---
- name: 全ホストのファクトを収集
  hosts: all
  gather_facts: true
  tasks: []

- name: ロードバランサー設定を生成
  hosts: loadbalancer
  gather_facts: false
  tasks:
    - name: webサーバーの情報を表示
      debug:
        msg: >
          {{ item }}:
          IP={{ hostvars[item]['ansible_default_ipv4']['address'] }}
      loop: "{{ groups['web'] }}"
```

```bash
$ ansible-playbook render_config.yml
```

```
PLAY [全ホストのファクトを収集] ***********************************************************

TASK [Gathering Facts] ********************************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

PLAY [ロードバランサー設定を生成] *********************************************************

TASK [webサーバーの情報を表示] ************************************************************
ok: [lb] => (item=node1) =>
    msg: |-
        node1: IP=172.20.0.11
ok: [lb] => (item=node2) =>
    msg: |-
        node2: IP=172.20.0.12
ok: [lb] => (item=node3) =>
    msg: |-
        node3: IP=172.20.0.13
```

---

**ポイント**: 1つ目のPlayで `hosts: all` としてファクトを収集しておかないと、2つ目のPlayで他ホストの `ansible_*` 変数にアクセスできません。インベントリに直接定義した変数（`ansible_host` など）はファクト収集なしでもアクセス可能です。

---

## Section 4: 動的グループ

### Step 1: add_host による動的ホスト追加

`add_host` モジュールを使うと、実行時にホストやグループを動的に追加できます。

```bash
$ vi dynamic_group.yml
```

```yaml
---
- name: 動的グループの作成
  hosts: localhost
  gather_facts: false
  tasks:
    - name: 動的にホストをグループに追加
      add_host:
        name: "{{ item.name }}"
        ansible_host: "{{ item.ip }}"
        groups:
          - dynamic_web
      loop:
        - { name: "dynamic1", ip: "172.20.0.11" }
        - { name: "dynamic2", ip: "172.20.0.12" }

    - name: 動的グループのメンバーを表示
      debug:
        msg: "{{ groups['dynamic_web'] }}"

- name: 動的グループに対してタスクを実行
  hosts: dynamic_web
  gather_facts: false
  tasks:
    - name: 動的ホストに ping
      ping:
```

```bash
$ ansible-playbook dynamic_group.yml
```

```
PLAY [動的グループの作成] *****************************************************************

TASK [動的にホストをグループに追加] ********************************************************
changed: [localhost] => (item={'name': 'dynamic1', 'ip': '172.20.0.11'})
changed: [localhost] => (item={'name': 'dynamic2', 'ip': '172.20.0.12'})

TASK [動的グループのメンバーを表示] ********************************************************
ok: [localhost] =>
    msg:
    - dynamic1
    - dynamic2

PLAY [動的グループに対してタスクを実行] ****************************************************

TASK [動的ホストに ping] ******************************************************************
ok: [dynamic1]
ok: [dynamic2]
```

### Step 2: group_by によるファクトベースのグループ作成

`group_by` モジュールを使うと、収集したファクトに基づいてホストを動的にグループ分けできます。

```bash
$ vi group_by_demo.yml
```

```yaml
---
- name: OSファミリーでグループ分け
  hosts: web
  gather_facts: true
  tasks:
    - name: OSファミリーに基づいてグループを作成
      group_by:
        key: "os_{{ ansible_os_family }}"

    - name: 所属グループを表示
      debug:
        msg: "{{ inventory_hostname }} は {{ ansible_os_family }} ファミリー → os_{{ ansible_os_family }} グループ"

- name: RedHat系のみに対するタスク
  hosts: os_RedHat
  gather_facts: false
  tasks:
    - name: RedHat系ホストへのタスク
      debug:
        msg: "{{ inventory_hostname }} は RedHat 系です"
```

```bash
$ ansible-playbook group_by_demo.yml
```

```
PLAY [OSファミリーでグループ分け] *********************************************************

TASK [Gathering Facts] ********************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [OSファミリーに基づいてグループを作成] ************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [所属グループを表示] *****************************************************************
ok: [node1] =>
    msg: node1 は RedHat ファミリー → os_RedHat グループ
ok: [node2] =>
    msg: node2 は RedHat ファミリー → os_RedHat グループ
ok: [node3] =>
    msg: node3 は RedHat ファミリー → os_RedHat グループ

PLAY [RedHat系のみに対するタスク] *********************************************************

TASK [RedHat系ホストへのタスク] ***********************************************************
ok: [node1] =>
    msg: node1 は RedHat 系です
ok: [node2] =>
    msg: node2 は RedHat 系です
ok: [node3] =>
    msg: node3 は RedHat 系です
```

## Section 5: マルチ環境でのインベントリ管理

### Step 1: 環境ごとにインベントリファイルを分ける

本番環境とステージング環境で異なるインベントリを使い分ける方法です。

```bash
$ mkdir -p environments/staging environments/production
```

```bash
$ vi environments/staging/inventory.yml
```

```yaml
all:
  vars:
    ansible_user: root
    ansible_ssh_pass: password
    ansible_port: 22
  children:
    web:
      hosts:
        node1:
          ansible_host: 172.20.0.11
        node2:
          ansible_host: 172.20.0.12
    loadbalancer:
      hosts:
        lb:
          ansible_host: 172.20.0.14
```

```bash
$ vi environments/production/inventory.yml
```

```yaml
all:
  vars:
    ansible_user: root
    ansible_ssh_pass: password
    ansible_port: 22
  children:
    web:
      hosts:
        node1:
          ansible_host: 172.20.0.11
        node2:
          ansible_host: 172.20.0.12
        node3:
          ansible_host: 172.20.0.13
    loadbalancer:
      hosts:
        lb:
          ansible_host: 172.20.0.14
```

### Step 2: 環境ごとの group_vars

各環境ディレクトリ内に `group_vars` を配置します。

```bash
$ mkdir -p environments/staging/group_vars environments/production/group_vars
```

```bash
$ vi environments/staging/group_vars/all.yml
```

```yaml
---
app_env: staging
debug_mode: true
log_level: debug
```

```bash
$ vi environments/production/group_vars/all.yml
```

```yaml
---
app_env: production
debug_mode: false
log_level: warn
```

### Step 3: 環境の使い分け

`-i` オプションで使用するインベントリを指定します。

```bash
# ステージング環境にデプロイ
$ ansible-playbook -i environments/staging/inventory.yml site.yml

# 本番環境にデプロイ
$ ansible-playbook -i environments/production/inventory.yml site.yml
```

### Step 4: --limit によるターゲット制限

全ホストではなく、特定のホストやグループだけを対象にする場合は `--limit` を使います。

```bash
# node1 のみに実行
$ ansible-playbook -i environments/production/inventory.yml site.yml --limit node1

# web グループのみに実行
$ ansible-playbook -i environments/production/inventory.yml site.yml --limit web

# node1 と node2 に実行
$ ansible-playbook -i environments/production/inventory.yml site.yml --limit 'node1,node2'

# node1 を除外して実行
$ ansible-playbook -i environments/production/inventory.yml site.yml --limit 'all:!node1'
```

### Step 5: ディレクトリベースのインベントリ

ディレクトリをインベントリとして指定すると、ディレクトリ内の全てのインベントリファイルが読み込まれます。

```
environments/production/
├── inventory.yml          ← ホスト定義
├── group_vars/
│   ├── all.yml            ← 全ホスト共通変数
│   └── web.yml            ← webグループ変数
└── host_vars/
    └── node1.yml          ← node1固有変数
```

```bash
# ディレクトリ全体をインベントリとして指定
$ ansible-playbook -i environments/production/ site.yml
```

### Step 6: 動作確認

```bash
$ vi env_check.yml
```

```yaml
---
- name: 環境変数の確認
  hosts: web
  gather_facts: false
  tasks:
    - name: 環境情報を表示
      debug:
        msg: "環境: {{ app_env }}, デバッグ: {{ debug_mode }}, ログレベル: {{ log_level }}"
```

```bash
$ ansible-playbook -i environments/staging/inventory.yml env_check.yml
```

```
TASK [環境情報を表示] *********************************************************************
ok: [node1] =>
    msg: '環境: staging, デバッグ: True, ログレベル: debug'
ok: [node2] =>
    msg: '環境: staging, デバッグ: True, ログレベル: debug'
```

```bash
$ ansible-playbook -i environments/production/inventory.yml env_check.yml
```

```
TASK [環境情報を表示] *********************************************************************
ok: [node1] =>
    msg: '環境: production, デバッグ: False, ログレベル: warn'
ok: [node2] =>
    msg: '環境: production, デバッグ: False, ログレベル: warn'
ok: [node3] =>
    msg: '環境: production, デバッグ: False, ログレベル: warn'
```

Playbookを変更することなく、インベントリの切り替えだけで異なる環境にデプロイできることが確認できます。

------

[次へ進む](./ex10.md)
