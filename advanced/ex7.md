# 応用演習 7 - プラグイン

この演習では、Ansibleのプラグインシステムについて学びます。
Lookupプラグインによる外部情報の取得、Filterプラグインによるデータ加工、Testプラグインによる値の検証、そしてカスタムフィルタの実装方法を実践します。

**前提条件:** 応用演習1〜6を完了していること

[前に戻る](./ex6.md) | [次へ進む](./ex8.md)

---

## Section 1: Lookup プラグイン

[Lookupプラグイン](https://docs.ansible.com/ansible/latest/plugins/lookup.html)を使うことで、Ansibleの外部に存在する各種情報をPlaybook内で使用することができます。

### Step 1: file — ファイル内容の読み込み

```bash
$ cd ~/advanced
```

まず、読み込み用のサンプルファイルを作成します。

```bash
$ echo "Hello from Ansible Training 2026" > /tmp/sample_message.txt
```

```bash
$ vi lookup_file.yml
```

```yaml
---
- name: file lookup デモ
  hosts: localhost
  gather_facts: false

  tasks:
    - name: ファイルの内容を読み込んで表示
      debug:
        msg: "ファイル内容: {{ lookup('file', '/tmp/sample_message.txt') }}"

    - name: ファイルの内容を変数に格納
      set_fact:
        message: "{{ lookup('file', '/tmp/sample_message.txt') }}"

    - name: 格納した変数を表示
      debug:
        var: message

    - name: 存在しないファイルの場合（エラーを無視）
      debug:
        msg: "{{ lookup('file', '/tmp/nonexistent.txt', errors='ignore') | d('ファイルが見つかりません', true) }}"
```

```bash
$ ansible-playbook lookup_file.yml
```

```
PLAY [file lookup デモ] **********************************************************

TASK [ファイルの内容を読み込んで表示] ************************************************
ok: [localhost] =>
  msg: 'ファイル内容: Hello from Ansible Training 2026'

TASK [ファイルの内容を変数に格納] ****************************************************
ok: [localhost]

TASK [格納した変数を表示] ************************************************************
ok: [localhost] =>
  message: Hello from Ansible Training 2026

TASK [存在しないファイルの場合（エラーを無視）] ****************************************
ok: [localhost] =>
  msg: ファイルが見つかりません

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: template — Jinja2テンプレートのインライン展開

```bash
$ vi /tmp/greeting.j2
```

```jinja2
こんにちは、{{ user_name }} さん！
現在の環境: {{ target_env }}
```

```bash
$ vi lookup_template.yml
```

```yaml
---
- name: template lookup デモ
  hosts: localhost
  gather_facts: false
  vars:
    user_name: "管理者"
    target_env: "training"

  tasks:
    - name: テンプレートを展開して表示
      debug:
        msg: "{{ lookup('template', '/tmp/greeting.j2') }}"
```

```bash
$ ansible-playbook lookup_template.yml
```

```
PLAY [template lookup デモ] ******************************************************

TASK [テンプレートを展開して表示] ****************************************************
ok: [localhost] =>
  msg: |-
    こんにちは、管理者 さん！
    現在の環境: training

PLAY RECAP *********************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 3: pipe — シェルコマンドの実行

```bash
$ vi lookup_pipe.yml
```

```yaml
---
- name: pipe lookup デモ
  hosts: localhost
  gather_facts: false

  tasks:
    - name: 現在のUNIXタイムスタンプを取得
      debug:
        msg: "UNIX タイム: {{ lookup('pipe', 'date +%s') }}"

    - name: ホスト名を取得
      debug:
        msg: "ホスト名: {{ lookup('pipe', 'cat /etc/hostname') }}"

    - name: ディスク使用量を取得
      debug:
        msg: "{{ lookup('pipe', 'df -h / | tail -1') }}"

    - name: 複数コマンドの結果を変数に格納
      set_fact:
        system_info:
          hostname: "{{ lookup('pipe', 'cat /etc/hostname') }}"
          kernel: "{{ lookup('pipe', 'uname -r') }}"
          uptime: "{{ lookup('pipe', 'uptime -p') }}"

    - name: システム情報を表示
      debug:
        var: system_info
```

```bash
$ ansible-playbook lookup_pipe.yml
```

```
PLAY [pipe lookup デモ] **********************************************************

TASK [現在のUNIXタイムスタンプを取得] ************************************************
ok: [localhost] =>
  msg: 'UNIX タイム: 1751788800'

TASK [ホスト名を取得] **************************************************************
ok: [localhost] =>
  msg: 'ホスト名: controller'

TASK [ディスク使用量を取得] **********************************************************
ok: [localhost] =>
  msg: overlay          50G   15G   35G  31% /

TASK [複数コマンドの結果を変数に格納] ************************************************
ok: [localhost]

TASK [システム情報を表示] ************************************************************
ok: [localhost] =>
  system_info:
    hostname: controller
    kernel: 6.17.7-300.fc43.aarch64
    uptime: up 2 days, 3 hours, 15 minutes

PLAY RECAP *********************************************************************
localhost                  : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 4: env — 環境変数の読み取り

```bash
$ vi lookup_env.yml
```

```yaml
---
- name: env lookup デモ
  hosts: localhost
  gather_facts: false

  tasks:
    - name: 環境変数を読み取り
      debug:
        msg:
          - "HOME: {{ lookup('env', 'HOME') }}"
          - "PATH: {{ lookup('env', 'PATH') }}"
          - "USER: {{ lookup('env', 'USER') }}"

    - name: 未定義の環境変数にデフォルト値を設定
      debug:
        msg: "MY_APP_ENV: {{ lookup('env', 'MY_APP_ENV') | d('development', true) }}"
```

```bash
$ ansible-playbook lookup_env.yml
```

```
PLAY [env lookup デモ] ************************************************************

TASK [環境変数を読み取り] ************************************************************
ok: [localhost] =>
  msg:
  - 'HOME: /root'
  - 'PATH: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  - 'USER: '

TASK [未定義の環境変数にデフォルト値を設定] ********************************************
ok: [localhost] =>
  msg: 'MY_APP_ENV: development'

PLAY RECAP *********************************************************************
localhost                  : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 2: Filter プラグイン

Filterプラグインは `|` 記号を使って変数を加工するもので、Ansibleには多数のフィルタが用意されています。応用演習4で学んだフィルタに加え、ここではさらに高度なフィルタを紹介します。

### Step 1: 主要フィルタの復習と応用

```bash
$ vi filter_review.yml
```

```yaml
---
- name: フィルタ復習と応用
  hosts: localhost
  gather_facts: false
  vars:
    servers:
      - { name: "web-01", role: "frontend", port: 8080, active: true }
      - { name: "web-02", role: "frontend", port: 8081, active: false }
      - { name: "db-01", role: "database", port: 5432, active: true }
      - { name: "cache-01", role: "cache", port: 6379, active: true }

  tasks:
    - name: "default - デフォルト値"
      debug:
        msg: "{{ undefined_var | d('デフォルト値') }}"

    - name: "select + map - アクティブなサーバー名"
      debug:
        msg: "{{ servers | selectattr('active', 'equalto', true) | map(attribute='name') | list }}"

    - name: "selectattr + rejectattr の組み合わせ"
      debug:
        msg: "{{ servers | selectattr('active') | rejectattr('role', 'equalto', 'cache') | map(attribute='name') | list }}"

    - name: "zip + dict の応用"
      set_fact:
        port_map: "{{ dict(servers | map(attribute='name') | zip(servers | map(attribute='port'))) }}"

    - name: ポートマップ
      debug:
        var: port_map

    - name: "join の応用 - 改行区切り"
      debug:
        msg: "{{ servers | map(attribute='name') | join('\n') }}"

    - name: "regex_replace の応用"
      debug:
        msg: "{{ 'server_backup_2026-07-06.tar.gz' | regex_replace('(\\d{4})-(\\d{2})-(\\d{2})', '\\1年\\2月\\3日') }}"
```

```bash
$ ansible-playbook filter_review.yml
```

```
PLAY [フィルタ復習と応用] ************************************************************

TASK [default - デフォルト値] ******************************************************
ok: [localhost] =>
  msg: デフォルト値

TASK [select + map - アクティブなサーバー名] ******************************************
ok: [localhost] =>
  msg:
  - web-01
  - db-01
  - cache-01

TASK [selectattr + rejectattr の組み合わせ] ****************************************
ok: [localhost] =>
  msg:
  - web-01
  - db-01

TASK [zip + dict の応用] **********************************************************
ok: [localhost]

TASK [ポートマップ] ****************************************************************
ok: [localhost] =>
  port_map:
    cache-01: 6379
    db-01: 5432
    web-01: 8080
    web-02: 8081

TASK [join の応用 - 改行区切り] ****************************************************
ok: [localhost] =>
  msg: |-
    web-01
    web-02
    db-01
    cache-01

TASK [regex_replace の応用] ******************************************************
ok: [localhost] =>
  msg: server_backup_2026年07月06日.tar.gz

PLAY RECAP *********************************************************************
localhost                  : ok=7    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 2: ipaddr フィルタ — IPアドレスの操作

`ipaddr` フィルタを使うと、IPアドレスの検証や変換が行えます。このフィルタは `netaddr` Pythonライブラリに依存しているため、事前にインストールが必要です。

```bash
$ pip install netaddr
```

```bash
$ vi filter_ipaddr.yml
```

```yaml
---
- name: ipaddr フィルタデモ
  hosts: localhost
  gather_facts: false
  vars:
    addr_list:
      - '192.168.1.1'
      - 'host.example.com'
      - '::1'
      - '172.20.0.0/24'
      - 'fe80::100/10'
      - 'invalid'

  tasks:
    - name: 有効なIPアドレスのみ抽出
      debug:
        msg: "{{ addr_list | ansible.utils.ipaddr }}"

    - name: IPv4 のみ抽出
      debug:
        msg: "{{ addr_list | ansible.utils.ipv4 }}"

    - name: IPv6 のみ抽出
      debug:
        msg: "{{ addr_list | ansible.utils.ipv6 }}"

    - name: ネットワークアドレスの情報を取得
      debug:
        msg:
          - "ネットワーク: {{ '172.20.0.11/24' | ansible.utils.ipaddr('network') }}"
          - "ブロードキャスト: {{ '172.20.0.11/24' | ansible.utils.ipaddr('broadcast') }}"
          - "ネットマスク: {{ '172.20.0.11/24' | ansible.utils.ipaddr('netmask') }}"
          - "ホスト部: {{ '172.20.0.11/24' | ansible.utils.ipaddr('address') }}"
```

```bash
$ ansible-playbook filter_ipaddr.yml
```

```
PLAY [ipaddr フィルタデモ] **********************************************************

TASK [有効なIPアドレスのみ抽出] ******************************************************
ok: [localhost] =>
  msg:
  - 192.168.1.1
  - ::1
  - 172.20.0.0/24
  - fe80::100/10

TASK [IPv4 のみ抽出] **************************************************************
ok: [localhost] =>
  msg:
  - 192.168.1.1
  - 172.20.0.0/24

TASK [IPv6 のみ抽出] **************************************************************
ok: [localhost] =>
  msg:
  - ::1
  - fe80::100/10

TASK [ネットワークアドレスの情報を取得] **********************************************
ok: [localhost] =>
  msg:
  - 'ネットワーク: 172.20.0.0'
  - 'ブロードキャスト: 172.20.0.255'
  - 'ネットマスク: 255.255.255.0'
  - 'ホスト部: 172.20.0.11'

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** `ipaddr` フィルタは `ansible.utils` コレクションに含まれています。FQCN（完全修飾コレクション名）として `ansible.utils.ipaddr` と記述することが推奨されます。

**Note:** `ansible.utils` 6.x + `ansible-core` 2.21 の組み合わせでは、`ipaddr` フィルタの初回使用時に `Deprecation WARNING: Instantiating filter PluginLoader with aliases is deprecated` という警告が表示されることがあります。これはコレクション内部の実装に起因する警告であり、Playbookの記述に問題があるわけではありません。コレクションの将来のバージョンで解消される予定です。

### Step 3: items2dict / dict2items — モダンなデータ変換パターン

```bash
$ vi filter_modern.yml
```

```yaml
---
- name: モダンなフィルタパターン
  hosts: localhost
  gather_facts: false
  vars:
    services:
      nginx: { port: 80, enabled: true }
      postgresql: { port: 5432, enabled: true }
      redis: { port: 6379, enabled: false }
      memcached: { port: 11211, enabled: false }

  tasks:
    - name: "dict2items でリストに変換"
      debug:
        msg: "{{ services | dict2items }}"

    - name: "有効なサービスのみ抽出して辞書に戻す"
      set_fact:
        active_services: "{{ services | dict2items | selectattr('value.enabled') | items2dict }}"

    - name: アクティブなサービス
      debug:
        var: active_services

    - name: "サービス名とポートのマッピング"
      debug:
        msg: "{{ services | dict2items | map(attribute='key') | zip(services | dict2items | map(attribute='value.port')) | list }}"

    - name: "FQCN の使用例: community.general.json_query"
      set_fact:
        sample_data:
          - { name: "item1", category: "A", value: 100 }
          - { name: "item2", category: "B", value: 200 }
          - { name: "item3", category: "A", value: 300 }

    - name: json_query で category A のみ取得（FQCN）
      debug:
        msg: "{{ sample_data | community.general.json_query('[?category==`A`].name') }}"
```

```bash
$ ansible-playbook filter_modern.yml
```

```
PLAY [モダンなフィルタパターン] ******************************************************

TASK [dict2items でリストに変換] ****************************************************
ok: [localhost] =>
  msg:
  - key: nginx
    value:
      enabled: true
      port: 80
  - key: postgresql
    value:
      enabled: true
      port: 5432
  - key: redis
    value:
      enabled: false
      port: 6379
  - key: memcached
    value:
      enabled: false
      port: 11211

TASK [有効なサービスのみ抽出して辞書に戻す] ********************************************
ok: [localhost]

TASK [アクティブなサービス] **********************************************************
ok: [localhost] =>
  active_services:
    nginx:
      enabled: true
      port: 80
    postgresql:
      enabled: true
      port: 5432

TASK [サービス名とポートのマッピング] ************************************************
ok: [localhost] =>
  msg:
  - - nginx
    - 80
  - - postgresql
    - 5432
  - - redis
    - 6379
  - - memcached
    - 11211

TASK [FQCN の使用例: community.general.json_query] ********************************
ok: [localhost]

TASK [json_query で category A のみ取得（FQCN）] ************************************
ok: [localhost] =>
  msg:
  - item1
  - item3

PLAY RECAP *********************************************************************
localhost                  : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 3: Test プラグイン

[Testプラグイン](https://docs.ansible.com/ansible/latest/user_guide/playbooks_tests.html)は `is` 文を使って値の検証を行います。テストは常に `True` / `False` のいずれかを返却します。

### Step 1: タスク実行結果のテスト

```bash
$ vi test_task_result.yml
```

```yaml
---
- name: タスク結果テストデモ
  hosts: node1
  become: true

  tasks:
    - name: 成功するコマンドを実行
      command: echo "success"
      register: success_result

    - name: 失敗するコマンドを実行
      command: /bin/false
      register: fail_result
      ignore_errors: true

    - name: 条件付きスキップ
      debug:
        msg: "このタスクはスキップされます"
      when: false
      register: skip_result

    - name: "is succeeded テスト"
      debug:
        msg: "成功: {{ success_result is succeeded }}"

    - name: "is failed テスト"
      debug:
        msg: "失敗: {{ fail_result is failed }}"

    - name: "is changed テスト"
      debug:
        msg: "変更あり: {{ success_result is changed }}"

    - name: "is skipped テスト"
      debug:
        msg: "スキップ: {{ skip_result is skipped }}"

    - name: テスト結果に基づく処理
      debug:
        msg: "前のタスクが失敗したため、リカバリ処理を実行します"
      when: fail_result is failed

    - name: 成功時のみ実行
      debug:
        msg: "前のタスクが成功したので、後続処理を実行します"
      when: success_result is succeeded and success_result is not failed
```

```bash
$ ansible-playbook test_task_result.yml
```

```
PLAY [タスク結果テストデモ] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [成功するコマンドを実行] ********************************************************
changed: [node1]

TASK [失敗するコマンドを実行] ********************************************************
fatal: [node1]: FAILED! => 
    changed: true
    cmd:
    - /bin/false
    ...（省略）...
    rc: 1
...ignoring

TASK [条件付きスキップ] ************************************************************
skipping: [node1]

TASK [is succeeded テスト] ********************************************************
ok: [node1] =>
  msg: '成功: True'

TASK [is failed テスト] ************************************************************
ok: [node1] =>
  msg: '失敗: True'

TASK [is changed テスト] **********************************************************
ok: [node1] =>
  msg: '変更あり: True'

TASK [is skipped テスト] **********************************************************
ok: [node1] =>
  msg: 'スキップ: True'

TASK [テスト結果に基づく処理] ********************************************************
ok: [node1] =>
  msg: 前のタスクが失敗したため、リカバリ処理を実行します

TASK [成功時のみ実行] **************************************************************
ok: [node1] =>
  msg: 前のタスクが成功したので、後続処理を実行します

PLAY RECAP *********************************************************************
node1                      : ok=9    changed=2    unreachable=0    failed=0    skipped=1    rescued=0    ignored=1
```

| テスト | 説明 |
|------|------|
| `is succeeded` | タスクが成功した場合に True（changed でも True） |
| `is failed` | タスクが失敗した場合に True |
| `is changed` | タスクが変更を行った場合に True |
| `is skipped` | タスクがスキップされた場合に True |

**Note:** `is succeeded` テストは、変更の有無に関わらず `True` となる点に注意してください。テストの反転には `is not` を使用します。

### Step 2: version テスト — バージョン比較

```bash
$ vi test_version.yml
```

```yaml
---
- name: バージョン比較テストデモ
  hosts: node1
  gather_facts: true

  tasks:
    - name: OS バージョンが 10.0 以上であることを確認
      debug:
        msg: "バージョンチェック: {{ ansible_distribution_version is version('10.0', '>=') }}"

    - name: バージョン比較の各種演算子
      debug:
        msg:
          - "== 10.0 : {{ ansible_distribution_version is version('10.0', '==') }}"
          - ">= 9.0  : {{ ansible_distribution_version is version('9.0', '>=') }}"
          - "<  11.0  : {{ ansible_distribution_version is version('11.0', '<') }}"
          - "!= 9.0  : {{ ansible_distribution_version is version('9.0', '!=') }}"

    - name: when 条件でバージョンテストを使用
      debug:
        msg: "このホストは RHEL 10 以上です"
      when: ansible_distribution_version is version('10.0', '>=')

    - name: カーネルバージョンの確認
      debug:
        msg: "カーネル {{ ansible_kernel }} はバージョン 6.0 以上です"
      when: ansible_kernel is version('6.0', '>=')

    - name: セマンティックバージョニングの比較
      debug:
        msg: "{{ item.pkg }} {{ item.ver }} は {{ item.check }} {{ item.op }} : {{ item.ver is version(item.check, item.op) }}"
      loop:
        - { pkg: "nginx", ver: "1.26.3", check: "1.20.0", op: ">=" }
        - { pkg: "python", ver: "3.12.0", check: "3.10.0", op: ">" }
        - { pkg: "openssl", ver: "3.0.2", check: "3.1.0", op: "<" }
```

```bash
$ ansible-playbook test_version.yml
```

```
PLAY [バージョン比較テストデモ] ******************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [OS バージョンが 10.0 以上であることを確認] **************************************
ok: [node1] =>
  msg: 'バージョンチェック: True'

TASK [バージョン比較の各種演算子] ****************************************************
ok: [node1] =>
  msg:
  - '== 10.0 : False'
  - '>= 9.0  : True'
  - '<  11.0  : True'
  - '!= 9.0  : True'

TASK [when 条件でバージョンテストを使用] **********************************************
ok: [node1] =>
  msg: このホストは RHEL 10 以上です

TASK [カーネルバージョンの確認] ******************************************************
ok: [node1] =>
  msg: カーネル 6.17.7-300.fc43.aarch64 はバージョン 6.0 以上です

TASK [セマンティックバージョニングの比較] **********************************************
ok: [node1] => (item={'pkg': 'nginx', 'ver': '1.26.3', 'check': '1.20.0', 'op': '>='})
  msg: nginx 1.26.3 は 1.20.0 >= : True
ok: [node1] => (item={'pkg': 'python', 'ver': '3.12.0', 'check': '3.10.0', 'op': '>'})
  msg: python 3.12.0 は 3.10.0 > : True
ok: [node1] => (item={'pkg': 'openssl', 'ver': '3.0.2', 'check': '3.1.0', 'op': '<'})
  msg: openssl 3.0.2 は 3.1.0 < : True

PLAY RECAP *********************************************************************
node1                      : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 4: カスタムフィルタの実装

組み込みフィルタでは対応できない加工が必要な場合や、複雑なフィルタの組み合わせを簡潔にしたい場合、Pythonを使ってカスタムフィルタを定義できます。

### Step 1: カスタムフィルタの配置場所

カスタムフィルタは、Playbookと同じディレクトリの `filter_plugins/` ディレクトリに配置します。

```bash
$ mkdir -p filter_plugins
```

### Step 2: カスタムフィルタの実装

```bash
$ vi filter_plugins/custom_filters.py
```

```python
#!/usr/bin/env python3
"""カスタムフィルタの実装例"""


def bytes_to_human(value, precision=2):
    """バイト数を人が読みやすい形式に変換する"""
    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
    value = float(value)
    for unit in units:
        if value < 1024.0:
            return f"{value:.{precision}f} {unit}"
        value /= 1024.0
    return f"{value:.{precision}f} EB"


def mask_string(value, visible_chars=4, mask_char='*'):
    """文字列の末尾以外をマスクする"""
    value = str(value)
    if len(value) <= visible_chars:
        return value
    masked_length = len(value) - visible_chars
    return mask_char * masked_length + value[-visible_chars:]


def server_status_emoji(status):
    """サーバーステータスを記号に変換する"""
    status_map = {
        'running': '[OK]',
        'stopped': '[STOP]',
        'error': '[ERR]',
        'maintenance': '[MAINT]',
    }
    return status_map.get(status.lower(), '[???]')


class FilterModule(object):
    """Ansible カスタムフィルタ"""

    def filters(self):
        return {
            'bytes_to_human': bytes_to_human,
            'mask_string': mask_string,
            'server_status_emoji': server_status_emoji,
        }
```

### Step 3: カスタムフィルタのテスト

```bash
$ vi custom_filter_test.yml
```

```yaml
---
- name: カスタムフィルタテスト
  hosts: localhost
  gather_facts: false

  tasks:
    - name: bytes_to_human フィルタのテスト
      debug:
        msg:
          - "1024 bytes = {{ 1024 | bytes_to_human }}"
          - "1048576 bytes = {{ 1048576 | bytes_to_human }}"
          - "5368709120 bytes = {{ 5368709120 | bytes_to_human }}"
          - "精度指定: {{ 1536 | bytes_to_human(1) }}"

    - name: mask_string フィルタのテスト
      debug:
        msg:
          - "パスワード: {{ 'SuperSecretPassword123' | mask_string }}"
          - "API キー: {{ 'sk-abc123def456ghi789' | mask_string(6) }}"
          - "短い文字列: {{ 'abc' | mask_string }}"

    - name: server_status_emoji フィルタのテスト
      debug:
        msg: "{{ item.name }}: {{ item.status | server_status_emoji }}"
      loop:
        - { name: "web-01", status: "running" }
        - { name: "web-02", status: "stopped" }
        - { name: "db-01", status: "error" }
        - { name: "cache-01", status: "maintenance" }
        - { name: "unknown-01", status: "unknown" }
```

```bash
$ ansible-playbook custom_filter_test.yml
```

```
PLAY [カスタムフィルタテスト] ********************************************************

TASK [bytes_to_human フィルタのテスト] **********************************************
ok: [localhost] =>
  msg:
  - 1024 bytes = 1.00 KB
  - 1048576 bytes = 1.00 MB
  - 5368709120 bytes = 5.00 GB
  - '精度指定: 1.5 KB'

TASK [mask_string フィルタのテスト] **************************************************
ok: [localhost] =>
  msg:
  - 'パスワード: ******************d123'
  - 'API キー: ***************ghi789'
  - '短い文字列: abc'

TASK [server_status_emoji フィルタのテスト] ******************************************
ok: [localhost] => (item={'name': 'web-01', 'status': 'running'})
  msg: 'web-01: [OK]'
ok: [localhost] => (item={'name': 'web-02', 'status': 'stopped'})
  msg: 'web-02: [STOP]'
ok: [localhost] => (item={'name': 'db-01', 'status': 'error'})
  msg: 'db-01: [ERR]'
ok: [localhost] => (item={'name': 'cache-01', 'status': 'maintenance'})
  msg: 'cache-01: [MAINT]'
ok: [localhost] => (item={'name': 'unknown-01', 'status': 'unknown'})
  msg: 'unknown-01: [???]'

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### カスタムフィルタ実装のポイント

| 項目 | 説明 |
|------|------|
| 配置場所 | `filter_plugins/` ディレクトリ（Playbookと同じ階層） |
| クラス名 | `FilterModule` 固定 |
| `filters()` メソッド | フィルタ名と関数のマッピングを辞書で返す |
| 引数 | 第1引数がパイプの左側の値、第2引数以降がフィルタのパラメータ |
| 参照 | [Ansible Filter Plugin ドキュメント](https://docs.ansible.com/ansible/latest/dev_guide/developing_plugins.html#filter-plugins) |

**Note:** カスタムフィルタはAnsibleコレクションの一部として配布することも可能です。チーム内で共有する場合は、コレクション化を検討してください。

---

## まとめ

この演習で学んだ内容:

| プラグイン種別 | 名前 | 用途 |
|------|------|------|
| Lookup | `file` | ファイルの内容を読み込む |
| Lookup | `template` | Jinja2テンプレートを展開する |
| Lookup | `pipe` | シェルコマンドを実行して結果を取得する |
| Lookup | `env` | 環境変数を読み取る |
| Filter | `select` / `selectattr` | リストのフィルタリング |
| Filter | `map` | リストの変換 |
| Filter | `json_query` | JMESPath による構造化データ問い合わせ |
| Filter | `ipaddr` | IPアドレスの検証・変換 |
| Filter | `items2dict` / `dict2items` | 辞書とリストの相互変換 |
| Test | `is failed` / `is changed` / `is succeeded` / `is skipped` | タスク結果の検証 |
| Test | `version()` | バージョン文字列の比較 |
| カスタム | `FilterModule` | Pythonでフィルタを自作 |

---

[前に戻る](./ex6.md) | [次へ進む](./ex8.md)
