# 演習 4 - 変数、ループ、ハンドラを使う

[前に戻る](../basic-intro/ex3.md)

------

前演習で作ったplaybookは、単純にad-hocで実行した内容を繋げてみた状態でした。
これだけでも十分自動化の恩恵は受けられるでしょうが、ここからは playbook をより柔軟かつパワフルに使用できる、より高度なスキルを学びたいと思います。

例えば、システム運用の現場では、環境や作業内容ごとに「操作する内容は同じだが値が違う」というパターンが数多く存在するでしょう。そのような場合のためにAnsibleでは変数を使用できます。
変数はシステム毎の違う部分の扱い、例えば port番号、IPアドレス、ディレクトリなどの違いの部分を吸収してくれます。

ループは task を繰り返し実行する場合に使います。例えば10個のファイルを同じディレクトリに展開したいというような場合、ループを使うことにより1つの task として実現できます。

ハンドラはサービス再起動が必要な場合に使います。サービスの設定ファイルの登録/編集や、新規パッケージの導入が行われる際に、最後にサービスの再起動が必要になる場合はよくあります。
ハンドラを使うと、特定の task で変更が生じた場合に限って「最後に1回だけ」再起動を実行することができます。
例えば、変更発生時にnginxの再起動処理が必要になる task が2つあったとして、ハンドラを使えば、変更タスク実行ごとにnginxを複数回再起動する必要も、再起動が必要な変更がないのにplaybook実行のたびに再起動が実行されてしまうこともありません。

変数、ループ、ハンドラの十分な理解のためには、Ansibleドキュメントの以下部分を確認してください。

- [Ansible 変数](http://docs.ansible.com/ansible/latest/playbooks_variables.html)
- [Ansible ループ](http://docs.ansible.com/ansible/latest/playbooks_loops.html)
- [Ansible ハンドラ](http://docs.ansible.com/ansible/latest/playbooks_intro.html#handlers-running-operations-on-change)

## 事前準備: プロジェクトのセットアップ

この演習からは新しいプロジェクトディレクトリ `~/basic-roles` で作業します。演習1と同様に、`ansible.cfg` と `inventory.yml` をこのディレクトリにも作成しておきましょう。

### Step 1: ansible.cfg の作成

```bash
$ cd ~/basic-roles
$ vi ansible.cfg
```

```ini
[defaults]
stdout_callback = ansible.builtin.default
host_key_checking = False
retry_files_enabled = False
inventory = ./inventory.yml
callback_result_format = yaml

[ssh_connection]
pipelining = True
```

### Step 2: inventory.yml の作成

```bash
$ vi inventory.yml
```

```yml
all:
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
  vars:
    ansible_user: root
    ansible_ssh_pass: password
    ansible_port: 22
```

### Step 3: 接続確認

```bash
$ ansible all -m ping
```

全てのノードから `SUCCESS` が返れば準備完了です。


## Section 1: Play定義と変数

まずは新しいplaybookを作成します。既に先の演習で作成していることもあり慣れた作業かと思います。

### Step 1:

playbookを作成します。

```bash
$ vi site.yml
```

`site.yml` は、特別な意味があるわけではありませんがplaybookの名前として最もよく使われる典型的なものです。

### Step 2:

playの定義といくつかの変数をPlaybookに追加します。このPlaybook中には、Webサーバへのパッケージのインストールとサービス管理が含まれています。

```yml
---
- hosts: web
  name: This is a play within a playbook
  become: yes
  vars:
    nginx_packages:
      - nginx
    nginx_service_name: nginx
```

### Step 3: 変数の種類を理解する

`vars:` ブロックでは、play内で使用する変数を定義しています。Ansibleの変数には主に以下の種類があります。

- **スカラー変数（scalar）**: 単一の値を持つ変数です。
  - `nginx_service_name: nginx` のように、一つの文字列や数値を格納します。
- **リスト変数（list）**: 複数の値をリストとして持つ変数です。
  - `nginx_packages` はリスト型の変数で、`- nginx` のようにハイフンで始まる各要素がリストの項目になります。
  - リストには複数の値を追加できます（例: `- nginx-mod-stream` を追加するなど）。

---
**NOTE**

変数名はアルファベット、数字、アンダースコアで構成し、必ずアルファベットで始める必要があります。`nginx_packages` や `nginx_service_name` のようにスネークケース（snake_case）で命名するのが一般的です。

---


## Section 2: 変数とループを使ったタスク

### Step 1:

*install nginx packages* と命名した新規taskを追加します。

```yml
  tasks:
    - name: install nginx packages
      package:
        name: "{{ nginx_packages }}"
        state: present
      notify: restart nginx service

    - name: start nginx service
      service:
        name: "{{ nginx_service_name }}"
        state: started
        enabled: yes
```

### Step 2: 変数展開の仕組みを理解する

- `name: "{{ nginx_packages }}"` : `package` モジュールで `nginx_packages` 変数で指定されたパッケージをインストールするようにしています。`package` モジュールの`name`はリストを受け取ることができるため、変数にリストを渡すことで複数パッケージを一度にインストールできます。
- `notify: restart nginx service` : この行がハンドラの呼び出しになります。詳細は Section 3 で触れます。

---
**NOTE**

`{{` `}}` で変数名をくくると変数が展開されます。これはAnsibleが使っているテンプレートエンジンである [Jinja2](http://docs.ansible.com/ansible/latest/playbooks_templating.html) の仕様です。

playbook中で変数展開を用いる際は、YAMLの文法上の制約から**常にクオートを入れなければならない**点に注意してください。

```yml
# 正しい書き方 - クオートで囲む
name: "{{ nginx_packages }}"

# 間違った書き方 - YAMLパーサーがエラーを出す
name: {{ nginx_packages }}
```

これは、YAMLが `{` で始まる値をディクショナリ（辞書型）として解釈しようとしてしまうためです。

---

### Step 3: ループの使い方を理解する

`package` モジュールのようにリストを直接受け取れるモジュールもありますが、多くのモジュールでは1つの値しか受け取れません。そのような場合には `loop` キーワードを使って繰り返し実行します。

例えば、`user` モジュールは1回の呼び出しで1ユーザーしか作成できません。複数ユーザーを作成するには `loop` が必要です。

```yml
    - name: create app users
      user:
        name: "{{ item }}"
        state: present
        shell: /bin/bash
      loop:
        - app_user1
        - app_user2
        - deploy_user
```

- **`loop`**: ループ対象となるリストを定義することで task をループ実行することが可能です。
  - 従来は `with_items` という記法が使われていましたが、Ansible 2.5以降はこちらの記法が推奨されています。
- **`item`**: task 内でループされた各要素には `item` という変数名でアクセスできます。上記の例では、リストの各ユーザー名が順番に `item` に代入されて3回実行されます。

**Note:** `package` モジュールは `name` にリストを直接渡せるため、`loop` を使う必要はありません（むしろ `loop` を使うと1パッケージずつ処理されるため遅くなります）。今回の playbook で `name: "{{ nginx_packages }}"` としているのは、この性質を活用しています。


## Section 3: ハンドラの定義

構成ファイルの変更や新しいパッケージのインストールなど、様々な理由でサービスやプロセスの再起動が必要になる場合にはハンドラを使います。
task中からのハンドラ呼び出しは既に登場していますが、ハンドラ自体がまだ存在しない状態ですので、playbookへのハンドラの追加を行なっていきましょう。

### Step 1:

ハンドラを定義します。

```yml
  handlers:
    - name: restart nginx service
      service:
        name: "{{ nginx_service_name }}"
        state: restarted
```

### Step 2: ハンドラの動作を理解する

ハンドラには以下の重要な特徴があります。

1. **変更があった場合のみ実行される**: ハンドラは `notify` で呼び出されますが、呼び出し元のtaskが `changed` 状態になった場合にのみ実行されます。taskの実行結果が `ok`（変更なし）であった場合、ハンドラは実行されません。

2. **playの最後に1回だけ実行される**: 同じハンドラが複数のtaskから `notify` されても、ハンドラはplayの全taskが完了した後に1回だけ実行されます。これにより、不要なサービス再起動を防ぐことができます。

3. **名前の一致で対応づけられる**: `notify` とハンドラの対応は、`name` で定義した名前の一致で判定されます。名前が一致しないとハンドラは呼び出されませんので、スペルミスに注意してください。

---
**NOTE**

`handlers:` は `tasks:` と同じインデントレベル（playレベル）で定義します。これで play に対して task の定義が終わり、ハンドラの定義が開始されたことをAnsibleに伝えています。

---


## Section 4: 完成したPlaybookの確認と実行

これで変数、ループ、ハンドラを活用したPlaybookの完成です！
実行する前に、最終的に完成したplaybookの内容を確認しておきましょう。

### Step 1: 完成したPlaybook

```yml
---
- hosts: web
  name: This is a play within a playbook
  become: yes
  vars:
    nginx_packages:
      - nginx
    nginx_service_name: nginx

  tasks:
    - name: install nginx packages
      package:
        name: "{{ nginx_packages }}"
        state: present
      notify: restart nginx service

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

まずは文法エラーが存在しないか確認します。

```bash
$ cd ~/basic-roles
$ ansible-playbook site.yml --syntax-check
```

```
playbook: site.yml
```

エラーが出なければ文法上の問題はありません。

### Step 3: Playbookの実行

それでは実際にplaybookを実行してみましょう。

```bash
$ ansible-playbook site.yml
```

もしも問題なく実行されれば、標準出力は以下のようになるでしょう。

```
PLAY [This is a play within a playbook] ************************************************************

TASK [Gathering Facts] *****************************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [install nginx packages] **********************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [start nginx service] *************************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

RUNNING HANDLER [restart nginx service] ************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

PLAY RECAP *****************************************************************************************
node1                      : ok=4    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

注目すべきポイントは以下の通りです。

- `install nginx packages` タスクが `changed` になっているため、`RUNNING HANDLER [restart nginx service]` が実行されています。
- もう一度同じplaybookを実行すると、パッケージは既にインストール済みのため `ok` になり、ハンドラは実行されません。

### Step 4: 冪等性の確認

もう一度playbookを実行して、冪等性を確認してみましょう。

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

TASK [start nginx service] *************************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

PLAY RECAP *****************************************************************************************
node1                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

2回目の実行では全てのタスクが `ok` となり、`changed` が `0` になっていることが確認できます。変更がなかったため、ハンドラも実行されていません。これがAnsibleの冪等性（何度実行しても同じ結果になる）の特徴です。

------

[次へ進む](./ex5.md)
