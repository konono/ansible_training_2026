# 演習 6 - Role: Playbookを再利用可能にする

[前に戻る](./ex5.md)

------

先の演習では、1ファイルでplaybookを作成して、全ての要素をそのファイルの中に定義してきました。もちろん、1ファイル構成のplaybookでも実用的なものを作ることは可能ですが、実際の運用で色々なplaybookを実装し活用するようになると以下のようなことをしたくなってくるでしょう。

* 作業工程を適切に分割して管理したい
* playbook間で共通で実施する作業を再利用可能にしたい
* 組織内で使用されているplaybookをコモディティ化したい

このようなニーズに応えてくれるのがroleです。
roleを作成する事でplaybookをパーツとして分解し、構造化されたディレクトリに格納し、role単位で独立して管理することができるようになります。

この演習では、まずAnsible Galaxyで共有されている公開Roleについて紹介した後で、実際に演習5で実装したPlaybookのrole化を進めていきます。


## Section 1: Ansible Galaxyで公開Roleを見つける

Ansibleは公式に[Ansible Galaxy](https://galaxy.ansible.com/)というrole共有のためのプラットフォームを提供しており、世界中の人が作ったroleを手軽に検索し、自由に使用することができます。

並べてみてみると、メジャー所のミドルウェア導入や設定管理（SSL証明書、hosts）のroleが広く使われているようです。もちろん、他にもたくさんのroleが揃っていますので、何かのplaybookを作成する際にそのまま使えたり、実装のベースにできそうなroleがないか、まずはAnsible Galaxyで探してみるというのは良い手でしょう。

特に人気上位roleをほぼ独占している[geerlingguy](https://galaxy.ansible.com/geerlingguy)氏はクオリティの高いroleを幅広く提供しており、roleの作りとしても参考になるものが多いです。

注意点としては、いずれのroleも動作保証がされている訳ではなく、また同種のロールを色々な人が提供しているため、使用に際してはそのroleが安心して使えるものかどうかの見極めが必要となります。DL数やユーザースコアも大きな指標になりますが、実際のroleの中を見てどのような実装になっているかを直接確認することが重要です。


## Section 2: `nginx-simple` roleの雛形を作成する

ここからは実際に手を動かして、先ほど実装したplaybookをrole化してみましょう。roleは[ベストプラクティス・レイアウト](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html#directory-layout)にある通り、役割ごとに分割されたいくつかのディレクトリで構成されています。

```
roles/
    common/               # this hierarchy represents a "role"
        tasks/            #
            main.yml      #  <-- tasks file can include smaller files if warranted
        handlers/         #
            main.yml      #  <-- handlers file
        templates/        #  <-- files for use with the template resource
            ntp.conf.j2   #  <------- templates end in .j2
        files/            #
            bar.txt       #  <-- files for use with the copy resource
            foo.sh        #  <-- script files for use with the script resource
        vars/             #
            main.yml      #  <-- variables associated with this role
        defaults/         #
            main.yml      #  <-- default lower priority variables for this role
        meta/             #
            main.yml      #  <-- role dependencies
```

上記のようなroleのディレクトリ構成を全てそのまま手で作ろうとするとある程度の手間がかかりますが、Ansible Galaxyのコマンドである `ansible-galaxy` を使用すると、自作roleの初期化も簡単に実施できます。


### Step 1:

プロジェクトディレクトリへ移動します。

```bash
$ cd ~/basic-roles
```

### Step 2:

`roles` と命名したディレクトリを作成し `cd` で作成したディレクトリへ移動します。

```bash
$ mkdir roles
$ cd roles
```

### Step 3:

`ansible-galaxy` コマンドで `nginx-simple` という名前の新たなroleを作成しましょう。

```bash
$ ansible-galaxy init nginx-simple
```

```
- Role nginx-simple was created successfully
```

すると、下記のような構造でroleが初期化されます。

```bash
$ ls -R nginx-simple/
```

```
nginx-simple/:
README.md  defaults  files  handlers  meta  tasks  templates  tests  vars

nginx-simple/defaults:
main.yml

nginx-simple/files:

nginx-simple/handlers:
main.yml

nginx-simple/meta:
main.yml

nginx-simple/tasks:
main.yml

nginx-simple/templates:

nginx-simple/tests:
inventory  test.yml

nginx-simple/vars:
main.yml
```

ベストプラクティスにあったものとよく似た構造で `nginx-simple` roleが初期化されています。

### Step 4:

今回は使用しない `files`（コピー対象となるファイルを配置）と `tests`（role動作テスト用playbookを配置）ディレクトリを削除しておきましょう。

```bash
$ cd ~/basic-roles/roles/nginx-simple/
$ rm -rf files tests
```


## Section 3: Playbookの内容をroleに移植する

このセクションでは、演習5で作成したPlaybookに含まれている `vars:`、`tasks:`、`handlers:`、そして `templates/` をそれぞれrole内に移植していきます。

### Step 1: defaults/main.yml - 外部から上書き可能な変数

環境によって書き換える想定のある変数のデフォルト値を `roles/nginx-simple/defaults/main.yml` に定義します。

```bash
$ vi ~/basic-roles/roles/nginx-simple/defaults/main.yml
```

```yml
---
# defaults file for nginx-simple
nginx_test_message: This is a test message
nginx_keep_alive_timeout: 65
```

### Step 2: vars/main.yml - role内で固定の変数

role内で固定の値として使用する変数を `roles/nginx-simple/vars/main.yml` に定義します。

```bash
$ vi ~/basic-roles/roles/nginx-simple/vars/main.yml
```

```yml
---
# vars file for nginx-simple
nginx_packages:
  - nginx
nginx_service_name: nginx
nginx_htmls:
  - index.html
  - info.html
```

### Step 3: defaults と vars の優先度の違いを理解する

上記で変数を `defaults` と `vars` の二箇所に分けて定義しました。これはAnsibleの変数読み込みの優先度の違いによるものです。

Ansibleにおける変数の優先順位は、優先度の低いものから以下のようになっています。

- role の **defaults** (最も低い)
- inventoryで定義されたgroup変数
- playbookで定義されたgroup変数
- inventoryで定義されたhost変数
- playbookで定義されたhost変数
- playで定義された変数
- role の **vars** (高い)
- playbook実行時のパラメータで与えられた変数（`-e` オプション）(最も高い)

---
**NOTE**

上記の通り、role内の `defaults` で定義されたものはInventory変数やplay変数でオーバーライドされるのに対して、`vars` は優先度が高く、Inventory変数などで簡単に書き換えることはできません。

そのため、**外から書き換えるものは `defaults`、role内で固定値として使うものは `vars`** に定義するというのが基本ルールとなります。

例えば、`nginx_test_message` は環境ごとに異なるメッセージを表示したいかもしれないので `defaults` に配置し、`nginx_packages` はこのroleで必ずインストールするパッケージなので `vars` に配置しています。

---

### Step 4: handlers/main.yml - ハンドラの定義

`roles/nginx-simple/handlers/main.yml` にroleのハンドラを作成します。

```bash
$ vi ~/basic-roles/roles/nginx-simple/handlers/main.yml
```

```yml
---
# handlers file for nginx-simple
- name: restart nginx service
  service:
    name: "{{ nginx_service_name }}"
    state: restarted
```

### Step 5: tasks/main.yml - タスクの定義

`roles/nginx-simple/tasks/main.yml` にタスクを追加します。

```bash
$ vi ~/basic-roles/roles/nginx-simple/tasks/main.yml
```

```yml
---
# tasks file for nginx-simple
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
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: restart nginx service

- name: copy site.conf
  template:
    src: site.conf.j2
    dest: /etc/nginx/sites-enabled/site.conf
  notify: restart nginx service

- name: copy htmls
  template:
    src: "{{ item }}.j2"
    dest: "/usr/share/nginx/html/{{ item }}"
  loop: "{{ nginx_htmls }}"

- name: start nginx
  service:
    name: "{{ nginx_service_name }}"
    state: started
    enabled: yes
```

---
**NOTE**

`copy nginx.conf` や `copy htmls` タスクの `src` の値が、元のplaybookでは `templates/nginx.conf.j2` だったのに対して、ここでは `nginx.conf.j2` のように **`templates/` プレフィックスがなくなっている**ことに注意してください！

roleの場合、Jinja2テンプレートファイルはrole内の `templates` ディレクトリから自動的に探索されるようになっているため、テンプレートファイル名を指定するだけでOKです。

---

### Step 6: テンプレートファイルの移動

演習5で作成した `templates/` ディレクトリ内のテンプレートファイルを、role内の `templates/` ディレクトリに移動します。

```bash
$ mv ~/basic-roles/templates/* ~/basic-roles/roles/nginx-simple/templates/
$ rm -r ~/basic-roles/templates/
```

移動後のroleのディレクトリ構造を確認してみましょう。

```bash
$ find ~/basic-roles/roles/nginx-simple/ -type f | sort
```

```
/root/basic-roles/roles/nginx-simple/README.md
/root/basic-roles/roles/nginx-simple/defaults/main.yml
/root/basic-roles/roles/nginx-simple/handlers/main.yml
/root/basic-roles/roles/nginx-simple/meta/main.yml
/root/basic-roles/roles/nginx-simple/tasks/main.yml
/root/basic-roles/roles/nginx-simple/templates/index.html.j2
/root/basic-roles/roles/nginx-simple/templates/info.html.j2
/root/basic-roles/roles/nginx-simple/templates/nginx.conf.j2
/root/basic-roles/roles/nginx-simple/templates/site.conf.j2
/root/basic-roles/roles/nginx-simple/vars/main.yml
```


## Section 4: 新しいsite.ymlを作成する

roleへの移植が完了したら、roleを呼び出す新しい `site.yml` を作成します。

### Step 1:

既存の `site.yml` のバックアップを作成し、新しい `site.yml` を作成します。

```bash
$ cd ~/basic-roles
$ mv site.yml site.yml.bkup
$ vi site.yml
```

### Step 2:

play の定義と role の呼び出しを追加します。

```yml
---
- hosts: web
  name: This is my role-based playbook
  become: yes
  tasks:
    - import_role:
        name: nginx-simple
```

roleの呼び出しには [`import_role` モジュール](https://docs.ansible.com/ansible/latest/modules/import_role_module.html) を使用しています。

元のplaybookと比較すると、`vars:`、`tasks:` の詳細、`handlers:` が全てrole内に移動したため、playbookは非常にシンプルになっています。変数やタスクの実装はrole側に隠蔽され、playbookからはrole名を指定して呼び出すだけで済むようになりました。


## Section 5: Role化したPlaybookを実行する

これでオリジナルのPlaybookをroleに切り分けることができました。では実際に実行してみましょう。

### Step 1: 文法チェック

```bash
$ cd ~/basic-roles
$ ansible-playbook site.yml --syntax-check
```

```
playbook: site.yml
```

### Step 2: Playbookの実行

```bash
$ ansible-playbook site.yml
```

もしも問題なく実行されれば、標準出力は以下のようになるでしょう。

```
PLAY [This is my role-based playbook] ************************************************************

TASK [Gathering Facts] ***************************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : install nginx packages] *****************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : create site-enabled directory] **********************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : copy nginx.conf] ************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : copy site.conf] *************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx-simple : copy htmls] *****************************************************************
ok: [node1] => (item=index.html)
ok: [node2] => (item=index.html)
ok: [node3] => (item=index.html)
ok: [node1] => (item=info.html)
ok: [node2] => (item=info.html)
ok: [node3] => (item=info.html)

TASK [nginx-simple : start nginx] ****************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

PLAY RECAP ***************************************************************************************
node1                      : ok=7    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=7    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=7    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

注目すべきポイントは以下の通りです。

- 各タスク名の前に **`nginx-simple :`** というrole名がプレフィックスとして表示されています。これにより、どのroleに属するタスクが実行されているかが一目でわかります。
- すでに演習5で実行済みの内容を再実行した状態ですので、タスクの実行結果は全て `ok` になっているはずです。変更がないため、ハンドラも実行されていません。

### Step 3: 変数の上書きを試す

roleの `defaults` に定義した変数は、playbook実行時に `-e` オプションで上書きすることができます。試してみましょう。

```bash
$ ansible-playbook site.yml -e "nginx_test_message='Hello from Role!'"
```

実行後、`curl` で確認すると、メッセージが変更されていることがわかります。

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
  <p>Hello from Role!</p>
  <p><a href=info.html>System Info</a></p>
</body>
</html>
```

`defaults` に定義した変数はこのように外部から柔軟に上書きでき、roleの再利用性を高めています。


## Section 6: 実用的なrole設計のベストプラクティス

最後に、実運用でroleを設計・実装する際に押さえておきたいポイントを紹介します。

### role化する適切な単位は？

基本的にはAnsible Galaxyの人気上位roleのように、**ミドルウェア単位** や **OS内の特定箇所の設定単位** など、そのrole単体で閉じたデプロイを実行できる単位でrole化を行うのが良いでしょう。

例えば以下のような単位が一般的です。

- `nginx` - Webサーバの導入と設定
- `postgresql` - データベースの導入と設定
- `common` - 全サーバ共通の基盤設定（NTP、ファイアウォール、ユーザ管理など）

### roleの依存関係

特定のroleに依存するroleについては、`meta/main.yml` で[依存関係を定義](https://docs.ansible.com/ansible/latest/user_guide/playbooks_reuse_roles.html#role-dependencies)することができます。

例えば、アプリケーションのroleがnginxのroleに依存する場合、以下のように定義できます。

```yml
# roles/my-app/meta/main.yml
---
dependencies:
  - role: nginx-simple
```

ただし、相互に依存しあうようなrole構成にするべきではありません。依存関係は一方向に保ちましょう。

### role内でのrole呼び出し

`import_role` を使えば、role内のタスクの途中で別のroleを実行するといったことも可能です。色々なrole内で共通して実施される複数ステップの作業を切り出してrole化することで、共通ユーティリティとして使うこともできます。

```yml
# roles/my-app/tasks/main.yml
---
- name: Setup common configuration
  import_role:
    name: common

- name: Deploy application
  template:
    src: app.conf.j2
    dest: /etc/my-app/app.conf
```

### roleのコモディティ化

roleは組織内でコモディティ化され、色々な人が作る複数のplaybookが共通のroleを参照しているというような状態になることで真価を発揮するものです。もちろん特定の一つのplaybookでしか使われないものであっても、コードの可読性/メンテナンス性向上に繋がりますので、積極的にrole化を進めるのが良いでしょう。

------

[応用演習へ進む](../advanced/ex1.md)
