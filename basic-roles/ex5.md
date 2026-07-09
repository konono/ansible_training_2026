# 演習 5 - テンプレートとJinja2基礎

[前に戻る](./ex4.md)

------

前演習ではパッケージのインストールとサービスの起動を変数・ハンドラを使って実装しました。
この演習では、Ansibleのテンプレート機能を使って設定ファイルやHTMLを動的に生成・配置する方法を学びます。

テンプレートを使うと、環境ごとに異なる値（IPアドレス、ホスト名、設定値など）を含むファイルを、変数に基づいて自動的に生成することができます。これは設定ファイルの管理において非常に強力な機能です。

Ansibleのテンプレートエンジンには [Jinja2](https://jinja.palletsprojects.com/) が使われています。Jinja2はPythonのテンプレートエンジンであり、変数展開だけでなく、条件分岐やループなどの制御構文もテンプレート内で使用できます。

## Section 1: templateモジュールの概要

### Step 1: templateモジュールとは

`template` モジュールは、Jinja2テンプレートファイルを処理し、変数を展開した上でリモートホストに配置するモジュールです。

主な特徴は以下の通りです。

- テンプレートファイルの拡張子は慣例的に **`.j2`** を使用します。
- `src` にテンプレートファイルのパス、`dest` に配置先のパスを指定します。
- テンプレートファイル内の `{{ 変数名 }}` がplaybook内で定義された変数やファクト情報で置き換えられます。
- `copy` モジュールとは異なり、変数展開が行われるため、動的なファイル生成に適しています。

### Step 2: templatesディレクトリの作成

テンプレートファイルを格納するディレクトリを作成します。

```bash
$ cd ~/basic-roles
$ mkdir templates
$ cd templates
```

## Section 2: テンプレートファイルの作成

`templates` ディレクトリ内に4つのテンプレートファイルを作成します。
全ての拡張子が`.j2`となっているのは、これらのファイルがJinja2テンプレートであることを示しています。

### Step 1: nginx.conf.j2

nginx本体の設定ファイルテンプレートを作成します。

```bash
$ vi nginx.conf.j2
```

以下の内容を記述します。

```
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   {{ nginx_keep_alive_timeout }};
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/sites-enabled/*.conf;
}
```

このテンプレートの中で変数化されているのは以下の1箇所のみです。

```
    keepalive_timeout   {{ nginx_keep_alive_timeout }};
```

`nginx_keep_alive_timeout` の値がplaybookで定義した変数の値で展開されます。

### Step 2: site.conf.j2

バーチャルホスト定義のテンプレートを作成します。

```bash
$ vi site.conf.j2
```

```
server {
    listen       80 default_server;
    listen       [::]:80 default_server;
    server_name  _;
    root         /usr/share/nginx/html;

    # Load configuration files for the default server block.
    include /etc/nginx/default.d/*.conf;

    location / {
    }

    error_page 404 /404.html;
        location = /40x.html {
    }

    error_page 500 502 503 504 /50x.html;
        location = /50x.html {
    }
}
```

このテンプレートには変数は含まれていませんが、`template` モジュールを使って配置することで、将来的に変数化が必要になった際にスムーズに対応できます。

### Step 3: index.html.j2

メインページのHTMLテンプレートを作成します。

```bash
$ vi index.html.j2
```

```html
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>Ansible: Automation for Everyone</title>
  <style>
    body {
      font-family: sans-serif;
      text-align: center;
      font-size: 150%;
    }
  </style>
</head>
<body>
  <p>{{ nginx_test_message }}</p>
  <p><a href=info.html>System Info</a></p>
</body>
</html>
```

`nginx_test_message` 変数の内容がメッセージとして表示されます。

### Step 4: info.html.j2

システム情報表示ページのテンプレートを作成します。

```bash
$ vi info.html.j2
```

```html
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>Ansible: Automation for Everyone</title>
  <style>
    body {
      font-family: sans-serif;
      text-align: center;
      font-size: 150%;
    }
  </style>
</head>
<body>
  <p>
    Hostname: {{ inventory_hostname }}<br />
    IP Address: {{ ansible_default_ipv4.address }}<br />
    OS: {{ ansible_distribution }} {{ ansible_distribution_version }}<br />
  </p>
</body>
</html>
```

このテンプレートでは、playbook中で定義していない変数を展開しています。これらについては Section 4 で解説します。

### Step 5:

テンプレートの作成が終わったら、playbookが置いてあるディレクトリに戻りましょう。

```bash
$ cd ~/basic-roles
```

## Section 3: templateモジュールを使ったタスク

### Step 1: Playbookに変数を追加する

`site.yml` を開いて、テンプレートで使用する変数を追加します。

```bash
$ vi site.yml
```

`vars:` ブロックを以下のように更新します。

```yml
  vars:
    nginx_test_message: This is a test message
    nginx_keep_alive_timeout: 65
    nginx_packages:
      - nginx
    nginx_service_name: nginx
    nginx_htmls:
      - index.html
      - info.html
```

新たに追加した変数は以下の通りです。

- `nginx_test_message`: index.htmlに表示するテストメッセージの文字列
- `nginx_keep_alive_timeout`: nginx.confの `keepalive_timeout` に設定する値
- `nginx_htmls`: nginxで公開するHTMLファイルのリスト

### Step 2: 設定ファイルを配置するタスクを追加する

`tasks:` セクションの `start nginx service` タスクの前に、以下のタスクを追加します。

```yml
    - name: create site-enabled directory
      file:
        name: /etc/nginx/sites-enabled
        state: directory

    - name: copy nginx.conf
      template:
        src: templates/nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify: restart nginx service

    - name: copy site.conf
      template:
        src: templates/site.conf.j2
        dest: /etc/nginx/sites-enabled/site.conf
      notify: restart nginx service

    - name: copy htmls
      template:
        src: "templates/{{ item }}.j2"
        dest: "/usr/share/nginx/html/{{ item }}"
      loop: "{{ nginx_htmls }}"
```

各タスクの内容は下記の通りです。

- **create site-enabled directory**: `file` モジュールを使ってバーチャルホスト定義用ディレクトリ `sites-enabled` を作成しています。`file` モジュールでは `state` の値によって、ディレクトリ作成、シムリンク作成、ファイル削除操作なども可能です。
- **copy nginx.conf**: `template` モジュールを使って、`nginx.conf.j2` テンプレートを変数展開した上で `/etc/nginx/nginx.conf` に配置しています。設定ファイルが変更された場合にnginxの再起動が必要なため、`notify` でハンドラを呼び出しています。
- **copy site.conf**: 同様に `template` モジュールでバーチャルホスト設定を配置しています。
- **copy htmls**: `loop` を使って `index.html` と `info.html` の2つのテンプレートをループで展開しています。
  - `loop` にループ対象となるリストを定義することでtaskをループ実行することが可能です。
  - task内でループされた各要素には `item` という変数名でアクセスできます。


## Section 4: Jinja2のファクトとマジック変数

### Step 1: ファクト（facts）について

`info.html.j2` テンプレート内で使用している以下の変数は、playbook内の `vars:` では定義していません。

```
{{ inventory_hostname }}
{{ ansible_default_ipv4.address }}
{{ ansible_distribution }}
{{ ansible_distribution_version }}
```

これらは以下のように分類されます。

#### マジック変数（Magic Variables）

- **`{{ inventory_hostname }}`**: [マジック変数](https://docs.ansible.com/ansible/latest/reference_appendices/special_variables.html#magic)と呼ばれるAnsibleが自動設定する変数のうちの一つです。Inventory上で定義されているホスト名（アクセス先の実ホスト名ではない）が展開されます。

#### ファクト（Facts）

- **`{{ ansible_default_ipv4.address }}`**: デフォルトのIPv4アドレス
- **`{{ ansible_distribution }}`**: OSのディストリビューション名（例: `RedHat`）
- **`{{ ansible_distribution_version }}`**: ディストリビューションのバージョン（例: `10.2`）

これらは `setup` モジュールが自動で収集する **ファクト（facts）** です。Ansibleはplayの実行時に最初のタスクとして `Gathering Facts` を実行し、対象ホストのシステム情報を自動的に収集します。収集されたファクトはplaybook内で変数として自由に使用できます。

### Step 2: ファクトの確認

対象ホストでどのようなファクトが収集されるか確認するには、以下のad-hocコマンドを実行します。

```bash
$ ansible node1 -m setup
```

大量の情報が出力されるため、特定の情報だけを確認したい場合は `filter` を使います。

```bash
$ ansible node1 -m setup -a "filter=ansible_default_ipv4"
```

```
node1 | SUCCESS =>
    ansible_facts:
        ansible_default_ipv4:
            address: 172.20.0.11
            alias: eth0
            broadcast: ''
            gateway: 172.20.0.1
            interface: eth0
            ...
    changed: false
```

**Note:** ここで表示される `172.20.0.11` はコンテナのIPアドレスです。コントローラーからはこのIPアドレスで直接アクセスできます。


## Section 5: Jinja2のfor/if制御構文

Jinja2テンプレートでは変数展開だけでなく、`{% %}` を使った制御構文も利用できます。ここではよく使われる `for` ループと `if` 条件分岐について紹介します。

### Step 1: forループ

`{% for %}` を使うと、リスト内の要素を繰り返し処理してテキストを生成できます。

例えば、webグループに属する全ホストの情報リストを生成するテンプレートは以下のように書けます。

```jinja2
# Web Server List
{% for host in groups['web'] %}
{{ host }} ({{ hostvars[host]['ansible_host'] }})
{% endfor %}
```

上記のテンプレートは以下のように展開されます。

```
# Web Server List
node1 (172.20.0.11)
node2 (172.20.0.12)
node3 (172.20.0.13)
```

- `groups['web']` : inventoryの `web` グループに属するホスト名のリスト
- `hostvars[host]['ansible_host']` : 各ホストの `ansible_host` 変数（IPアドレス）

### Step 2: if条件分岐

`{% if %}` を使うと、条件に応じた内容を出力できます。

```jinja2
{% for host in groups['web'] %}
{% if hostvars[host]['ansible_host'] == '172.20.0.11' %}
{{ host }} ({{ hostvars[host]['ansible_host'] }})  # primary
{% else %}
{{ host }} ({{ hostvars[host]['ansible_host'] }})
{% endif %}
{% endfor %}
```

---
**NOTE**

Jinja2の制御構文をまとめると以下の通りです。

| 構文 | 用途 | 例 |
|------|------|-----|
| `{{ }}` | 変数展開 | `{{ ansible_hostname }}` |
| `{% %}` | 制御構文（for, if等） | `{% for host in groups['web'] %}` |
| `{# #}` | コメント | `{# これはコメントです #}` |

---


## Section 6: 完成したPlaybookの実行と動作確認

### Step 1: 完成したPlaybook

テンプレート機能を追加した最終的なplaybookの全体像は以下の通りです。

```yml
---
- hosts: web
  name: This is a play within a playbook
  become: yes
  vars:
    nginx_test_message: This is a test message
    nginx_keep_alive_timeout: 65
    nginx_packages:
      - nginx
    nginx_service_name: nginx
    nginx_htmls:
      - index.html
      - info.html

  tasks:
    - name: install nginx packages
      package:
        name: "{{ nginx_packages }}"
        state: present
      notify: restart nginx service

    - name: create site-enabled directory
      file:
        name: /etc/nginx/sites-enabled
        state: directory

    - name: copy nginx.conf
      template:
        src: templates/nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify: restart nginx service

    - name: copy site.conf
      template:
        src: templates/site.conf.j2
        dest: /etc/nginx/sites-enabled/site.conf
      notify: restart nginx service

    - name: copy htmls
      template:
        src: "templates/{{ item }}.j2"
        dest: "/usr/share/nginx/html/{{ item }}"
      loop: "{{ nginx_htmls }}"

    - name: start nginx service
      service:
        name: "{{ nginx_service_name }}"
        state: started
        enabled: yes

  handlers:
    - name: restart nginx service
      service:
        name: "{{ nginx_service_name }}"
        state: restarted
```

### Step 2: 文法チェック

```bash
$ cd ~/basic-roles
$ ansible-playbook site.yml --syntax-check
```

```
playbook: site.yml
```

### Step 3: Playbookの実行

```bash
$ ansible-playbook site.yml
```

```
PLAY [This is a play within a playbook] ************************************************************

TASK [Gathering Facts] *****************************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [install nginx packages] **********************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [create site-enabled directory] ***************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [copy nginx.conf] *****************************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [copy site.conf] ******************************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [copy htmls] **********************************************************************************
changed: [node1] => (item=index.html)
changed: [node2] => (item=index.html)
changed: [node3] => (item=index.html)
changed: [node1] => (item=info.html)
changed: [node2] => (item=info.html)
changed: [node3] => (item=info.html)

TASK [start nginx service] *************************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

RUNNING HANDLER [restart nginx service] ************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

PLAY RECAP *****************************************************************************************
node1                      : ok=8    changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=8    changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=8    changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`install nginx packages` は前演習で既にインストール済みのため `ok` ですが、テンプレートによる設定ファイルの配置タスクは初回実行のため `changed` になっています。nginx.confが変更されたため、ハンドラ `restart nginx service` も実行されています。

### Step 4: 動作確認

デプロイが完了したら、コントローラーからターゲットノードに直接curlでアクセスし、テストメッセージとシステム情報が正しく展開されているか確認してみましょう。

```bash
$ curl http://172.20.0.11
```

```html
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>Ansible: Automation for Everyone</title>
  <style>
    body {
      font-family: sans-serif;
      text-align: center;
      font-size: 150%;
    }
  </style>
</head>
<body>
  <p>This is a test message</p>
  <p><a href=info.html>System Info</a></p>
</body>
</html>
```

```bash
$ curl http://172.20.0.11/info.html
```

```html
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>Ansible: Automation for Everyone</title>
  <style>
    body {
      font-family: sans-serif;
      text-align: center;
      font-size: 150%;
    }
  </style>
</head>
<body>
  <p>
    Hostname: node1<br />
    IP Address: 172.20.0.11<br />
    OS: RedHat 10.2<br />
  </p>
</body>
</html>
```

テンプレート内の変数が、各ホストの実際の値に正しく展開されていることが確認できます。
`node2` や `node3` に対して同様にcurl（`curl http://172.20.0.12` 等）を実行すると、それぞれのホスト名やIPアドレスが表示されるはずです。

------

[次へ進む](./ex6.md)
