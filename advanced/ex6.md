# 応用演習 6 - Jinja2テンプレート応用

この演習では、Jinja2テンプレートの応用的な使い方を学びます。
制御構造（for/if）の詳細、空白文字の切り詰め、テンプレートの継承、サンドボックスによるセキュリティ、ネイティブ型の保持、そして実践的なテンプレート生成を行います。

**前提条件:** 応用演習1〜5を完了していること

[前に戻る](./ex5.md) | [次へ進む](./ex7.md)

---

## Section 1: Jinja2 制御構造の詳細

Jinja2の制御構造（`for`、`if`）について、ループ変数やネストを含む詳細な使い方を学びます。

### Step 1: for ループとループ変数

```bash
$ cd ~/advanced
$ mkdir -p templates
```

```bash
$ vi templates/loop_demo.j2
```

```jinja2
=== サーバー一覧 ===
{% for server in servers %}
{{ loop.index }}. {{ server.name }}
   ロール: {{ server.role }}
   ポート: {{ server.port }}
{% if loop.first %}
   ★ 最初のサーバー
{% endif %}
{% if loop.last %}
   ★ 最後のサーバー
{% endif %}
{% if not loop.last %}

{% endif %}
{% endfor %}

合計: {{ servers | length }} 台

=== 番号付きリスト（0始まり） ===
{% for item in items %}
[{{ loop.index0 }}] {{ item }}
{% endfor %}

=== 逆順ループ ===
{% for item in items | reverse %}
{{ loop.index }}. {{ item }}
{% endfor %}
```

```bash
$ vi loop_demo.yml
```

```yaml
---
- name: for ループデモ
  hosts: localhost
  gather_facts: false
  vars:
    servers:
      - { name: "web-01", role: "frontend", port: 8080 }
      - { name: "web-02", role: "frontend", port: 8081 }
      - { name: "db-01", role: "database", port: 5432 }
    items:
      - "alpha"
      - "beta"
      - "gamma"

  tasks:
    - name: テンプレートを展開して表示
      template:
        src: templates/loop_demo.j2
        dest: /tmp/loop_demo.txt

    - name: 結果を表示
      command: cat /tmp/loop_demo.txt
      register: result
      changed_when: false

    - name: 出力
      debug:
        msg: "{{ result.stdout }}"
```

```bash
$ ansible-playbook loop_demo.yml
```

```
PLAY [for ループデモ] **************************************************************

TASK [テンプレートを展開して表示] ****************************************************
changed: [localhost]

TASK [結果を表示] ******************************************************************
ok: [localhost]

TASK [出力] ************************************************************************
ok: [localhost] =>
  msg: |-
    === サーバー一覧 ===
    1. web-01
       ロール: frontend
       ポート: 8080
       ★ 最初のサーバー

    2. web-02
       ロール: frontend
       ポート: 8081

    3. db-01
       ロール: database
       ポート: 5432
       ★ 最後のサーバー

    合計: 3 台

    === 番号付きリスト（0始まり） ===
    [0] alpha
    [1] beta
    [2] gamma

    === 逆順ループ ===
    1. gamma
    2. beta
    3. alpha

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

主なループ変数:

| 変数 | 説明 |
|------|------|
| `loop.index` | 現在のループ回数（1始まり） |
| `loop.index0` | 現在のループ回数（0始まり） |
| `loop.first` | 最初のイテレーションで `True` |
| `loop.last` | 最後のイテレーションで `True` |
| `loop.length` | ループの総回数 |
| `loop.revindex` | 末尾からのカウント（1始まり） |

### Step 2: if/elif/else と set

```bash
$ vi templates/condition_demo.j2
```

```jinja2
=== サーバーステータスレポート ===
{% for server in servers %}
{% if server.status == 'running' %}
[OK]    {{ server.name }} - 正常稼働中
{% elif server.status == 'stopped' %}
[WARN]  {{ server.name }} - 停止中
{% elif server.status == 'error' %}
[ERROR] {{ server.name }} - エラー発生
{% else %}
[???]   {{ server.name }} - 状態不明
{% endif %}
{% endfor %}

{% set running_count = servers | selectattr('status', 'equalto', 'running') | list | length %}
{% set total_count = servers | length %}
=== サマリ ===
稼働中: {{ running_count }} / {{ total_count }}
稼働率: {{ (running_count / total_count * 100) | round(1) }}%
```

```bash
$ vi condition_demo.yml
```

```yaml
---
- name: if/elif/else デモ
  hosts: localhost
  gather_facts: false
  vars:
    servers:
      - { name: "web-01", status: "running" }
      - { name: "web-02", status: "stopped" }
      - { name: "db-01", status: "running" }
      - { name: "db-02", status: "error" }
      - { name: "cache-01", status: "running" }

  tasks:
    - name: テンプレートを展開
      template:
        src: templates/condition_demo.j2
        dest: /tmp/condition_demo.txt

    - name: 結果を表示
      command: cat /tmp/condition_demo.txt
      register: result
      changed_when: false

    - name: 出力
      debug:
        msg: "{{ result.stdout }}"
```

```bash
$ ansible-playbook condition_demo.yml
```

```
PLAY [if/elif/else デモ] **********************************************************

TASK [テンプレートを展開] ************************************************************
changed: [localhost]

TASK [結果を表示] ******************************************************************
ok: [localhost]

TASK [出力] ************************************************************************
ok: [localhost] =>
  msg: |-
    === サーバーステータスレポート ===
    [OK]    web-01 - 正常稼働中
    [WARN]  web-02 - 停止中
    [OK]    db-01 - 正常稼働中
    [ERROR] db-02 - エラー発生
    [OK]    cache-01 - 正常稼働中

    === サマリ ===
    稼働中: 3 / 5
    稼働率: 60.0%

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 2: 空白文字の切り詰め（{%- / -%}）

Jinja2のデフォルトでは、制御構造のタグ自体が占める行の改行やスペースもそのまま出力されます。`-` 記号を使うことで、不要な空白を切り詰めることができます。

### 動作例を紹介

以下の6つの例で、`-` の配置による出力の違いを確認します。

#### 例 1: 切り詰めなし

* テンプレート
```
START
{% for i in [1, 2, 3] %}
    {{ i }}
{% endfor %}
END
```

* 出力
```
START

    1

    2

    3

END
```

全ての改行、インデントが保持されています。

#### 例 2: `for` 開始先頭に `-`

* テンプレート
```
START
{%- for i in [1, 2, 3] %}
    {{ i }}
{% endfor %}
END
```

* 出力
```
START
    1

    2

    3

END
```

`START` から `for` 開始までの空白（改行）が切り詰められます。

#### 例 3: `for` 開始末尾に `-`

* テンプレート
```
START
{% for i in [1, 2, 3] -%}
    {{ i }}
{% endfor %}
END
```

* 出力
```
START
    1
    2
    3

END
```

**各ループ内要素に対して**先頭の空白が切り詰められます。

#### 例 4: `endfor` 先頭に `-`

* テンプレート
```
START
{% for i in [1, 2, 3] %}
    {{ i }}
{%- endfor %}
END
```

* 出力
```
START

    1
    2
    3
END
```

**各ループ内要素に対して**末尾の空白が切り詰められます。

#### 例 5: `endfor` 末尾に `-`

* テンプレート
```
START
{% for i in [1, 2, 3] %}
    {{ i }}
{% endfor -%}
END
```

* 出力
```
START

    1

    2

    3
END
```

`for` ループ終了後、次の非空白文字が出現するまでの空白が切り詰められます。

#### 例 6: `for` 開始末尾と `endfor` 先頭に `-`

* テンプレート
```
START
{% for i in [1, 2, 3] -%}
    {{ i }}
{%- endfor %}
END
```

* 出力
```
START
123
END
```

**各ループ内要素に対して**先頭と末尾、両方の空白が切り詰められます。

**Note:** 上記の例 1〜6 は Jinja2 単体での動作を示しています。Ansible の `template` モジュールはデフォルトで `trim_blocks=True`、`lstrip_blocks=True` を使用しているため、ブロックタグ（`{% %}`）直後の改行と、同じ行のタグ前の空白が自動的に除去されます。そのため、Ansible で実際にテンプレートを使う場合は、`{%- -%}` が必要になる場面は Jinja2 単体の場合より少なくなります。以下の実践例で違いを確認しましょう。

### 実践での使い分け

```bash
$ vi templates/whitespace_practical.j2
```

```jinja2
# /etc/hosts 形式の出力
# 切り詰めなし → 余計な空行が入る
{% for host in server_list %}

{{ host.ip }}  {{ host.name }}
{% endfor %}


# 適切な切り詰め → きれいな出力
{% for host in server_list -%}
{{ host.ip }}  {{ host.name }}
{% endfor -%}
```

```bash
$ vi whitespace_demo.yml
```

```yaml
---
- name: 空白切り詰めデモ
  hosts: localhost
  gather_facts: false
  vars:
    server_list:
      - { ip: "172.20.0.11", name: "node1" }
      - { ip: "172.20.0.12", name: "node2" }
      - { ip: "172.20.0.13", name: "node3" }

  tasks:
    - name: テンプレートを展開
      template:
        src: templates/whitespace_practical.j2
        dest: /tmp/whitespace_demo.txt

    - name: 結果を表示
      command: cat /tmp/whitespace_demo.txt
      register: result
      changed_when: false

    - name: 出力
      debug:
        msg: "{{ result.stdout }}"
```

```bash
$ ansible-playbook whitespace_demo.yml
```

```
PLAY [空白切り詰めデモ] ************************************************************

TASK [テンプレートを展開] ************************************************************
changed: [localhost]

TASK [結果を表示] ******************************************************************
ok: [localhost]

TASK [出力] ************************************************************************
ok: [localhost] =>
  msg: |-
    # /etc/hosts 形式の出力
    # 切り詰めなし → 余計な空行が入る

    172.20.0.11  node1

    172.20.0.12  node2

    172.20.0.13  node3


    # 適切な切り詰め → きれいな出力
    172.20.0.11  node1
    172.20.0.12  node2
    172.20.0.13  node3

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

空白切り詰めについて、より詳細な仕様を確認したい場合は[ドキュメント](https://jinja.palletsprojects.com/en/3.1.x/templates/#whitespace-control)を参照してください。

---

## Section 3: テンプレートの継承

Jinja2のテンプレート継承機能を使うと、共通のベーステンプレートを定義し、子テンプレートで特定の部分だけを上書きすることができます。

### Step 1: ベーステンプレートと子テンプレート

```bash
$ vi templates/base_config.j2
```

```jinja2
# ============================================
# {{ config_title | d('Configuration File') }}
# Generated by Ansible on {{ ansible_date_time.iso8601 | d('N/A') }}
# ============================================

{% block header %}
# デフォルトヘッダー
{% endblock %}

{% block main %}
# メインセクション（子テンプレートで上書き）
{% endblock %}

{% block footer %}
# --- End of configuration ---
{% endblock %}
```

```bash
$ vi templates/nginx_config.j2
```

```jinja2
{% extends 'base_config.j2' %}

{% block header %}
# nginx 設定ファイル
# ホスト: {{ inventory_hostname }}
{% endblock %}

{% block main %}
worker_processes auto;

events {
    worker_connections {{ worker_connections | d(1024) }};
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile      on;
    keepalive_timeout {{ keepalive_timeout | d(65) }};

{% for server in virtual_hosts | d([]) %}
    server {
        listen {{ server.port }};
        server_name {{ server.name }};

        location / {
            root {{ server.root | d('/usr/share/nginx/html') }};
            index index.html;
        }
    }
{% endfor %}
}
{% endblock %}
```

```bash
$ vi template_inheritance.yml
```

```yaml
---
- name: テンプレート継承デモ
  hosts: node1
  gather_facts: true
  vars:
    config_title: "Nginx Configuration"
    worker_connections: 2048
    keepalive_timeout: 120
    virtual_hosts:
      - { name: "app1.example.com", port: 8080, root: "/var/www/app1" }
      - { name: "app2.example.com", port: 8081, root: "/var/www/app2" }

  tasks:
    - name: 継承テンプレートを展開
      template:
        src: templates/nginx_config.j2
        dest: /tmp/nginx_inherited.conf
      delegate_to: localhost

    - name: 結果を表示
      command: cat /tmp/nginx_inherited.conf
      register: result
      changed_when: false
      delegate_to: localhost

    - name: 出力
      debug:
        msg: "{{ result.stdout }}"
```

```bash
$ ansible-playbook template_inheritance.yml
```

```
PLAY [テンプレート継承デモ] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [継承テンプレートを展開] ********************************************************
changed: [node1 -> localhost]

TASK [結果を表示] ******************************************************************
ok: [node1 -> localhost]

TASK [出力] ************************************************************************
ok: [node1] =>
  msg: |-
    # ============================================
    # Nginx Configuration
    # Generated by Ansible on 2026-07-06T10:00:00Z
    # ============================================

    # nginx 設定ファイル
    # ホスト: node1

    worker_processes auto;

    events {
        worker_connections 2048;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        sendfile      on;
        keepalive_timeout 120;

        server {
            listen 8080;
            server_name app1.example.com;

            location / {
                root /var/www/app1;
                index index.html;
            }
        }
        server {
            listen 8081;
            server_name app2.example.com;

            location / {
                root /var/www/app2;
                index index.html;
            }
        }
    }

    # --- End of configuration ---

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

子テンプレート（`nginx_config.j2`）の `{% block header %}` と `{% block main %}` が上書きされ、`{% block footer %}` はベーステンプレートのデフォルト内容がそのまま使用されています。

---

## Section 4: サンドボックスセキュリティ

AnsibleではJinja2をサンドボックス環境で実行することで、安全なテンプレート評価を可能としています。

### サンドボックスを使わない例（Pythonスクリプト）

```python
#!/usr/bin/env python3

from jinja2 import Environment

env = Environment()
output = env.from_string("{{ func.__code__ }}").render(func=lambda:None)
print("__code__: " + output)
```

* 出力
```
__code__: <code object <lambda> at 0x10bbc09c0, file "./no_sandbox.py", line 5>
```

サンドボックスを使わないと、テンプレートから内部のコードオブジェクト情報にアクセスできてしまいます。

### サンドボックス化した例（Pythonスクリプト）

```python
#!/usr/bin/env python3

from jinja2.sandbox import SandboxedEnvironment

env = SandboxedEnvironment()
output = env.from_string("{{ func.__code__ }}").render(func=lambda:None)
print("__code__: " + output)
```

* 出力
```
__code__:
Traceback (most recent call last):
  ...
jinja2.exceptions.SecurityError: access to attribute '__code__' of 'function' object is unsafe.
```

サンドボックス化された環境では、内部情報へのアクセスがブロックされます。AnsibleからJinja2を実行する際はこのサンドボックス化された環境が使用されるため、安全にテンプレート評価を実行できます。

---

## Section 5: Jinja2 ネイティブ型 — 型の保持

ansible-core 2.21 以降、Jinja2テンプレートの評価結果は **Pythonのネイティブ型（整数、リスト、辞書、ブール値など）がそのまま保持** されます。

以前のバージョンでは `jinja2_native = true` を `ansible.cfg` に設定する必要がありましたが、現在はネイティブ型がデフォルトかつ唯一の動作モードとなっています（`jinja2_native` オプションは非推奨となり、ansible-core 2.23 で削除予定です）。

### Step 1: 型の保持を確認

```bash
$ vi native_types.yml
```

```yaml
---
- name: ネイティブ型デモ
  hosts: localhost
  gather_facts: false
  vars:
    num_str: "42"

  tasks:
    - name: 数値の型を確認
      debug:
        msg:
          - "値: {{ num_str }}"
          - "型: {{ num_str | type_debug }}"

    - name: 算術演算
      debug:
        msg:
          - "計算結果: {{ num_str | int + 8 }}"
          - "計算結果の型: {{ (num_str | int + 8) | type_debug }}"

    - name: リストの型保持
      set_fact:
        my_list: "{{ [1, 2, 3] }}"

    - name: リストの型を確認
      debug:
        msg:
          - "値: {{ my_list }}"
          - "型: {{ my_list | type_debug }}"

    - name: ブール値の型保持
      set_fact:
        my_bool: "{{ true }}"

    - name: ブール値の型を確認
      debug:
        msg:
          - "値: {{ my_bool }}"
          - "型: {{ my_bool | type_debug }}"
```

```bash
$ ansible-playbook native_types.yml
```

```
TASK [数値の型を確認] ************************************************************
ok: [localhost] =>
  msg:
  - '値: 42'
  - '型: str'

TASK [算術演算] ******************************************************************
ok: [localhost] =>
  msg:
  - '計算結果: 50'
  - '計算結果の型: int'

TASK [リストの型を確認] ************************************************************
ok: [localhost] =>
  msg:
  - '値: [1, 2, 3]'
  - '型: list'

TASK [ブール値の型を確認] **********************************************************
ok: [localhost] =>
  msg:
  - '値: True'
  - '型: bool'
```

`set_fact` で `"{{ [1, 2, 3] }}"` を代入すると、リスト型がそのまま保持されます。同様にブール値も `bool` 型として保持されます。一方、`num_str` は YAML の `vars:` で文字列 `"42"` として定義されているため、`str` のままです。

**Note:** この型保持の動作は、数値計算やブール判定が絡むPlaybookで特に重要です。`| int` フィルタを使わなくても、`set_fact` で代入した数値は整数型として扱われます。

---

## Section 6: 実践的なテンプレート例

### Step 1: /etc/hosts の生成

インベントリ情報から `/etc/hosts` ファイルを動的に生成します。

```bash
$ vi templates/hosts.j2
```

```jinja2
# /etc/hosts - Generated by Ansible
# DO NOT EDIT MANUALLY

127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

# Ansible managed hosts
{% for host in groups['all'] -%}
{{ hostvars[host]['ansible_default_ipv4']['address'] }}  {{ host }}  {{ host }}.training.local
{% endfor %}
```

```bash
$ vi generate_hosts.yml
```

```yaml
---
- name: /etc/hosts の生成
  hosts: all
  gather_facts: true

- name: テンプレートの生成
  hosts: localhost
  gather_facts: false

  tasks:
    - name: /etc/hosts テンプレートを展開
      template:
        src: templates/hosts.j2
        dest: /tmp/generated_hosts

    - name: 生成結果を表示
      command: cat /tmp/generated_hosts
      register: hosts_content
      changed_when: false

    - name: 出力
      debug:
        msg: "{{ hosts_content.stdout }}"
```

```bash
$ ansible-playbook generate_hosts.yml
```

```
PLAY [/etc/hosts の生成] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

PLAY [テンプレートの生成] **********************************************************

TASK [/etc/hosts テンプレートを展開] ************************************************
changed: [localhost]

TASK [生成結果を表示] **************************************************************
ok: [localhost]

TASK [出力] ************************************************************************
ok: [localhost] =>
  msg: |-
    # /etc/hosts - Generated by Ansible
    # DO NOT EDIT MANUALLY

    127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

    # Ansible managed hosts
    172.20.0.11  node1  node1.training.local
    172.20.0.12  node2  node2.training.local
    172.20.0.13  node3  node3.training.local
    172.20.0.14  lb  lb.training.local

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
lb                         : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node1                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: ネットワーク構成レポートの生成

```bash
$ vi templates/network_report.j2
```

```jinja2
===================================================
ネットワーク構成レポート
生成日時: {{ ansible_date_time.iso8601 | d('N/A') }}
===================================================

{% for host in groups['web'] %}
--- {{ host }} ---
  ホスト名    : {{ hostvars[host]['ansible_hostname'] | d('N/A') }}
  FQDN        : {{ hostvars[host]['ansible_fqdn'] | d('N/A') }}
  OS          : {{ hostvars[host]['ansible_distribution'] | d('N/A') }} {{ hostvars[host]['ansible_distribution_version'] | d('') }}
  カーネル    : {{ hostvars[host]['ansible_kernel'] | d('N/A') }}

  ネットワークインターフェース:
{% for iface in hostvars[host]['ansible_interfaces'] | d([]) | sort %}
{% set iface_detail = hostvars[host]['ansible_' + iface] | d({}) %}
    {{ iface }}:
      MAC     : {{ iface_detail.macaddress | d('N/A') }}
{% if iface_detail.ipv4 is defined %}
      IPv4    : {{ iface_detail.ipv4.address }}/{{ iface_detail.ipv4.netmask }}
{% endif %}
      MTU     : {{ iface_detail.mtu | d('N/A') }}
      状態    : {{ iface_detail.active | d(false) | ternary('UP', 'DOWN') }}
{% endfor %}

  DNS サーバー:
{% for dns in hostvars[host]['ansible_dns']['nameservers'] | d([]) %}
    - {{ dns }}
{%- endfor %}

{% endfor %}
===================================================
合計ホスト数: {{ groups['web'] | length }}
===================================================
```

```bash
$ vi network_report.yml
```

```yaml
---
- name: ネットワーク情報の収集
  hosts: web
  gather_facts: true

- name: レポートの生成
  hosts: localhost
  gather_facts: true

  tasks:
    - name: ネットワーク構成レポートを生成
      template:
        src: templates/network_report.j2
        dest: /tmp/network_report.txt

    - name: レポートを表示
      command: cat /tmp/network_report.txt
      register: report
      changed_when: false

    - name: 出力
      debug:
        msg: "{{ report.stdout }}"
```

```bash
$ ansible-playbook network_report.yml
```

```
PLAY [ネットワーク情報の収集] ********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

PLAY [レポートの生成] **************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [ネットワーク構成レポートを生成] ************************************************
changed: [localhost]

TASK [レポートを表示] **************************************************************
ok: [localhost]

TASK [出力] ************************************************************************
ok: [localhost] =>
  msg: |-
    ===================================================
    ネットワーク構成レポート
    生成日時: 2026-07-06T10:00:00Z
    ===================================================

    --- node1 ---
      ホスト名    : node1
      FQDN        : node1
      OS          : RedHat 10.2
      カーネル    : 6.17.7-300.fc43.aarch64

      ネットワークインターフェース:
        eth0:
          MAC     : 02:42:ac:14:00:0b
          IPv4    : 172.20.0.11/255.255.255.0
          MTU     : 1500
          状態    : UP
        lo:
          MAC     : N/A
          IPv4    : 127.0.0.1/255.0.0.0
          MTU     : 65536
          状態    : UP

      DNS サーバー:
        - 8.8.8.8
        - 8.8.4.4

    --- node2 ---
      ...（同様の出力）...

    --- node3 ---
      ...（同様の出力）...

    ===================================================
    合計ホスト数: 3
    ===================================================

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node1                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## まとめ

この演習で学んだ内容:

| 機能 | 用途 |
|------|------|
| `loop.index` / `loop.first` / `loop.last` | ループ内の位置情報にアクセス |
| `if` / `elif` / `else` | テンプレート内の条件分岐 |
| `set` | テンプレート内でローカル変数を定義 |
| `{%-` / `-%}` | 空白文字の切り詰め制御 |
| `extends` / `block` | テンプレートの継承 |
| サンドボックス | 安全なテンプレート評価環境 |
| ネイティブ型 | テンプレート評価結果の型を保持（ansible-core 2.21+ のデフォルト動作） |
| `hostvars` | 他ホストのファクト情報にアクセス |

---

[前に戻る](./ex5.md) | [次へ進む](./ex7.md)
