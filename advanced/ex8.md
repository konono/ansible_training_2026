# 応用演習 8 - 変数の優先順位

[前に戻る](./ex7.md)

------

Ansibleを使いこなす上で、変数の優先順位を正しく理解することは非常に重要です。変数は20箇所以上の場所で定義でき、同じ名前の変数が複数の場所で定義されている場合、優先順位の高いものが最終的に使用されます。

この演習では、変数の優先順位を低い順から順に確認し、実際に上書きの動作を確かめながら理解を深めます。

[公式ドキュメント](https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)も併せて参照ください。

## Section 1: 演習の準備

### Step 1: 作業ディレクトリの作成

```bash
$ mkdir ~/variable-precedence-lab
$ cd ~/variable-precedence-lab
```

### Step 2: ディレクトリ構成の作成

変数の優先順位を検証するため、以下の構成を作成します。

```bash
$ mkdir -p group_vars host_vars inventory/group_vars inventory/host_vars roles/myrole/defaults roles/myrole/vars roles/myrole/tasks
```

最終的に以下のようなディレクトリ構成になります。

```
variable-precedence-lab/
├── ansible.cfg
├── group_vars/
│   ├── all.yml
│   └── web.yml
├── host_vars/
│   └── node1.yml
├── inventory/
│   ├── hosts
│   ├── group_vars/
│   │   ├── all.yml
│   │   └── web.yml
│   └── host_vars/
│       └── node1.yml
├── roles/
│   └── myrole/
│       ├── defaults/
│       │   └── main.yml
│       ├── vars/
│       │   └── main.yml
│       └── tasks/
│           └── main.yml
├── vars_file.yml
├── vars_include.yml
└── site.yml
```

### Step 3: ansible.cfg の作成

```bash
$ vi ansible.cfg
```

```ini
[defaults]
inventory = ./inventory/hosts
retry_files_enabled = False
host_key_checking = False
stdout_callback = ansible.builtin.default
callback_result_format = yaml

[ssh_connection]
pipelining = True
```

### Step 4: インベントリファイルの作成

```bash
$ vi inventory/hosts
```

```ini
[web]
node1 ansible_host=172.20.0.11 ansible_user=root ansible_ssh_pass=password

[web:vars]
my_var="03: inventory group_vars (inline)"
```

## Section 2: 優先順位 1〜6 — コマンドライン / Role Defaults / グループ変数

変数の優先順位を低い順から確認します。番号が大きいほど優先度が高くなります。

### Step 1: 優先順位 1 — コマンドラインのデフォルト値

コマンドラインオプションとして指定する変数です。例えば `-c local` は `ansible_connection=local` を意味します。

```bash
$ ansible-playbook site.yml -c local
```

上記では `ansible_connection` に `local` がセットされます。これは最も優先度が低い変数定義です。

### Step 2: 優先順位 2 — Role の defaults

Roleの `defaults/main.yml` で定義される変数です。最も上書きされやすく、「デフォルト値」として使うのに最適です。

```bash
$ vi roles/myrole/defaults/main.yml
```

```yaml
---
my_var: "02: role defaults"
```

```bash
$ vi roles/myrole/tasks/main.yml
```

```yaml
---
- name: roleのデフォルト変数を表示
  debug:
    var: my_var
```

### Step 3: 優先順位 3 — インベントリのグループ変数（インライン）

インベントリファイル内で直接定義されたグループ変数です。

`inventory/hosts` に既に `[web:vars]` セクションとして定義済みです。

```ini
[web:vars]
my_var="03: inventory group_vars (inline)"
```

### Step 4: 優先順位 4 — Playbook の group_vars/all

Playbookと同じディレクトリにある `group_vars/all.yml` です。

```bash
$ vi group_vars/all.yml
```

```yaml
---
my_var: "04: playbook group_vars/all"
```

### Step 5: 優先順位 5 — インベントリの group_vars/*

インベントリディレクトリ配下の `group_vars/` です。

```bash
$ vi inventory/group_vars/all.yml
```

```yaml
---
my_var: "05: inventory group_vars/all (directory)"
```

```bash
$ vi inventory/group_vars/web.yml
```

```yaml
---
my_var: "06-inv: inventory group_vars/web"
```

### Step 6: 優先順位 6 — Playbook の group_vars/*

Playbookディレクトリ配下の `group_vars/` です（allを除く特定グループ）。

```bash
$ vi group_vars/web.yml
```

```yaml
---
my_var: "06: playbook group_vars/web"
```

### Step 7: 動作確認 — グループ変数の上書き

まず、ここまでの定義で優先順位を確認するPlaybookを作成します。

```bash
$ vi site.yml
```

```yaml
---
- name: 変数の優先順位を確認する
  hosts: web
  gather_facts: false
  roles:
    - myrole
  tasks:
    - name: 現在の my_var を表示
      debug:
        var: my_var
```

実行してみましょう。

```bash
$ ansible-playbook site.yml
```

```
PLAY [変数の優先順位を確認する] ************************************************************

TASK [myrole : roleのデフォルト変数を表示] *************************************************
ok: [node1] =>
    my_var: '06: playbook group_vars/web'

TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: '06: playbook group_vars/web'

PLAY RECAP *******************************************************************************
node1                      : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Playbook の `group_vars/web.yml`（優先順位6）が、Roleのdefaults（優先順位2）やインベントリのグループ変数（優先順位3）を上書きしていることが確認できます。

## Section 3: 優先順位 7〜8 — ホスト変数

### Step 1: 優先順位 7 — インベントリのホスト変数

インベントリファイル内でホストに直接定義された変数、またはインベントリの `host_vars/` ディレクトリ内の変数です。

```bash
$ vi inventory/host_vars/node1.yml
```

```yaml
---
my_var: "07: inventory host_vars/node1"
```

### Step 2: 優先順位 8 — Playbook の host_vars/*

Playbookディレクトリ配下の `host_vars/` に定義されたホスト変数です。

```bash
$ vi host_vars/node1.yml
```

```yaml
---
my_var: "08: playbook host_vars/node1"
```

### Step 3: 動作確認

```bash
$ ansible-playbook site.yml
```

```
TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: '08: playbook host_vars/node1'
```

ホスト変数（優先順位8）がグループ変数（優先順位6）を上書きしています。

---

**ポイント**: ホスト変数は常にグループ変数より優先されます。これは Ansible の重要な原則です。

---

## Section 4: 優先順位 9〜12 — Facts / Play変数

### Step 1: 優先順位 9 — Facts / Cached set_facts

`gather_facts: true` で自動収集されるファクト変数です。

```bash
$ ansible node1 -m setup -a "filter=ansible_hostname"
```

```
node1 | SUCCESS =>
    ansible_facts:
        ansible_hostname: node1
    changed: false
```

ファクト変数はhost_varsよりも上書きが難しく、`ansible_` プレフィックスの変数を静的に上書きすると予期せぬ動作を引き起こす場合があります。

### Step 2: 優先順位 10 — Play vars

Playbookの `vars:` ディレクティブで定義された変数です。

```bash
$ vi site.yml
```

```yaml
---
- name: 変数の優先順位を確認する
  hosts: web
  gather_facts: false
  vars:
    my_var: "10: play vars"
  roles:
    - myrole
  tasks:
    - name: 現在の my_var を表示
      debug:
        var: my_var
```

```bash
$ ansible-playbook site.yml
```

```
TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: '10: play vars'
```

Play vars がhost_vars（優先順位8）を上書きしています。

### Step 3: 優先順位 11 — Play vars_prompt

実行時にインタラクティブに入力される変数です。

```yaml
---
- name: vars_prompt の例
  hosts: web
  gather_facts: false
  vars:
    my_var: "10: play vars"
  vars_prompt:
    - name: my_var
      prompt: "my_var の値を入力してください"
      private: false
      default: "11: vars_prompt"
  tasks:
    - name: 現在の my_var を表示
      debug:
        var: my_var
```

実行すると入力プロンプトが表示されます。

```
my_var の値を入力してください [11: vars_prompt]: test_value

TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: test_value
```

### Step 4: 優先順位 12 — Play vars_files

外部ファイルから読み込む変数です。

```bash
$ vi vars_file.yml
```

```yaml
---
my_var: "12: vars_files"
```

```yaml
---
- name: vars_files の例
  hosts: web
  gather_facts: false
  vars:
    my_var: "10: play vars"
  vars_files:
    - vars_file.yml
  tasks:
    - name: 現在の my_var を表示
      debug:
        var: my_var
```

```bash
$ ansible-playbook site.yml
```

```
TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: '12: vars_files'
```

`vars_files` が `vars`（優先順位10）を上書きしました。

## Section 5: 優先順位 13〜16 — Role変数 / Block / Task / include_vars

### Step 1: 優先順位 13 — Role vars

Role内の `vars/main.yml` で定義される変数です。`defaults/main.yml` と異なり、上書きされにくい変数として扱われます。

```bash
$ vi roles/myrole/vars/main.yml
```

```yaml
---
my_var: "13: role vars"
```

---

**重要**: Role の `defaults/main.yml`（優先順位2）と `vars/main.yml`（優先順位13）は大きく優先順位が異なります。

- **defaults**: 利用者が自由に上書きすることを想定した「デフォルト値」
- **vars**: Roleの内部で使用し、上書きを想定しない「固定値」

---

### Step 2: 優先順位 14 — Block vars

`block` ディレクティブに付与された変数です。ブロック内のタスクにのみ適用されます。

```yaml
  tasks:
    - name: block外のタスク
      debug:
        var: my_var

    - block:
        - name: block内のタスク
          debug:
            var: my_var
      vars:
        my_var: "14: block vars"
```

### Step 3: 優先順位 15 — Task vars

個々のタスクに直接定義された変数です。そのタスクのみに適用されます。

```yaml
  tasks:
    - name: task vars のテスト
      debug:
        var: my_var
      vars:
        my_var: "15: task vars"
```

### Step 4: 優先順位 16 — include_vars（重要！）

`include_vars` モジュールで読み込まれた変数は **非常に高い優先順位** を持ちます。

```bash
$ vi vars_include.yml
```

```yaml
---
my_var: "16: include_vars"
```

```bash
$ vi site.yml
```

```yaml
---
- name: include_vars の優先順位を確認
  hosts: web
  gather_facts: false
  vars:
    my_var: "10: play vars"
  vars_files:
    - vars_file.yml
  roles:
    - myrole
  tasks:
    - name: include_vars で変数を読み込み
      include_vars: vars_include.yml

    - name: 現在の my_var を表示
      debug:
        var: my_var

    - name: task vars で上書きを試みる
      debug:
        var: my_var
      vars:
        my_var: "15: task vars"
```

```bash
$ ansible-playbook site.yml
```

```
TASK [include_vars で変数を読み込み] ******************************************************
ok: [node1]

TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: '16: include_vars'

TASK [task vars で上書きを試みる] *********************************************************
ok: [node1] =>
    my_var: '16: include_vars'
```

---

**重要**: `include_vars`（優先順位16）は `vars_files`（優先順位12）、`role vars`（優先順位13）、task vars（優先順位15）よりも優先順位が高いです。実行時に動的にファイルを読み込むため、task vars では上書きできません。`include_vars` を上書きできるのは `set_fact`（優先順位17）以上のみです。

環境ごとに変数ファイルを切り替えたい場合に `include_vars` は非常に有用ですが、この高い優先順位を理解していないと予期せぬ上書きが発生する可能性があります。

---

## Section 6: 優先順位 17〜20 — set_fact / Role Params / Extra Vars

### Step 1: 優先順位 17 — set_fact / register

`set_fact` モジュールまたは `register` ディレクティブで設定された変数です。

```yaml
  tasks:
    - name: set_fact で変数を設定
      set_fact:
        my_var: "17: set_fact"

    - name: 現在の my_var を表示
      debug:
        var: my_var
```

```
TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: '17: set_fact'
```

`register` も同じ優先順位です。

```yaml
    - name: コマンド結果をregisterで保存
      command: hostname
      register: hostname_result

    - name: register変数を表示
      debug:
        var: hostname_result.stdout
```

### Step 2: 優先順位 18 — Role params

Roleの呼び出し時にパラメータとして渡す変数です。

```yaml
---
- name: role params の例
  hosts: web
  gather_facts: false
  roles:
    - role: myrole
      my_var: "18: role params"
```

```
TASK [myrole : roleのデフォルト変数を表示] *************************************************
ok: [node1] =>
    my_var: '18: role params'
```

Role params は Role 内の `vars/main.yml`（優先順位13）すら上書きします。

### Step 3: 優先順位 19 — Include params

`include_tasks` や `import_tasks` 実行時に渡すパラメータです。

```bash
$ vi included_task.yml
```

```yaml
---
- name: included task内の変数を表示
  debug:
    var: my_var
```

```yaml
  tasks:
    - name: タスクをincludeする
      include_tasks:
        file: included_task.yml
      vars:
        my_var: "19: include params"
```

### Step 4: 優先順位 20 — Extra vars（最高優先度）

コマンドラインで `-e`（`--extra-vars`）オプションにより渡される変数です。**全ての変数定義を上書きする最高優先度** を持ちます。

```bash
$ ansible-playbook site.yml -e "my_var='20: extra vars'"
```

```
TASK [現在の my_var を表示] ***************************************************************
ok: [node1] =>
    my_var: '20: extra vars'
```

Extra vars は他のどの変数定義よりも常に優先されます。デバッグ時や一時的な値の変更に非常に便利です。

```bash
# ファイルから渡すことも可能
$ echo '{"my_var": "20: extra vars from file"}' > extra.json
$ ansible-playbook site.yml -e @extra.json
```

## Section 7: Play間での変数共有

### Step 1: set_fact を使った Play 間の変数共有

通常、`vars:` で定義した変数は同じPlay内でのみ有効です。しかし、`set_fact` で設定した変数は、同じPlaybook内の後続のPlayからも `hostvars` 経由でアクセスできます。

```bash
$ vi share_vars.yml
```

```yaml
---
- name: Play 1 - 変数を設定する
  hosts: node1
  gather_facts: false
  tasks:
    - name: set_fact で変数を設定
      set_fact:
        shared_value: "Play 1 で設定した値"

- name: Play 2 - 別のPlayから変数を参照する
  hosts: node1
  gather_facts: false
  tasks:
    - name: set_fact で設定した変数はPlay間で共有される
      debug:
        var: shared_value
```

```bash
$ ansible-playbook share_vars.yml
```

```
PLAY [Play 1 - 変数を設定する] ************************************************************

TASK [set_fact で変数を設定] ***************************************************************
ok: [node1]

PLAY [Play 2 - 別のPlayから変数を参照する] *************************************************

TASK [set_fact で設定した変数はPlay間で共有される] ********************************************
ok: [node1] =>
    shared_value: Play 1 で設定した値
```

### Step 2: 異なるホスト間での変数共有

異なるホストの変数は `hostvars` を使ってアクセスします。

```yaml
---
- name: Play 1 - node1 で変数を設定
  hosts: node1
  gather_facts: false
  tasks:
    - name: node1 で set_fact
      set_fact:
        app_version: "2.1.0"

- name: Play 2 - node2 から node1 の変数を参照
  hosts: node2
  gather_facts: false
  tasks:
    - name: hostvars 経由で node1 の変数を取得
      debug:
        msg: "node1 の app_version は {{ hostvars['node1']['app_version'] }}"
```

---

**ポイント**: `set_fact` はホスト単位のファクトとして保存されるため、他のホストから参照するには `hostvars[ホスト名][変数名]` を使います。Roleを跨いで変数を共有したい場合にも有効です。

---

## Section 8: まとめ — 変数の優先順位一覧表

以下の表は、変数の優先順位を低い順（1）から高い順（20）にまとめたものです。

| 順位 | 変数の種類 | 定義場所 | 用途 |
|:---:|---|---|---|
| 1 | コマンドラインのデフォルト値 | `-c local` 等のオプション | 接続方式などのデフォルト |
| 2 | Role の defaults | `roles/xxx/defaults/main.yml` | Role利用者が上書き前提のデフォルト値 |
| 3 | インベントリのグループ変数 | `inventory/hosts` 内 `[group:vars]` | グループ共通の基本設定 |
| 4 | Playbook の group_vars/all | `group_vars/all.yml` | 全ホスト共通設定 |
| 5 | インベントリの group_vars/* | `inventory/group_vars/*.yml` | インベントリ側のグループ設定 |
| 6 | Playbook の group_vars/* | `group_vars/*.yml` | Playbook側のグループ設定 |
| 7 | インベントリのホスト変数 | `inventory/host_vars/*.yml` | インベントリ側のホスト固有設定 |
| 8 | Playbook の host_vars/* | `host_vars/*.yml` | Playbook側のホスト固有設定 |
| 9 | Facts / Cached set_facts | `gather_facts` / `ansible_facts` | 自動収集されたシステム情報 |
| 10 | Play vars | Playbook内 `vars:` | Play全体に適用される変数 |
| 11 | Play vars_prompt | Playbook内 `vars_prompt:` | 実行時にユーザーが入力 |
| 12 | Play vars_files | Playbook内 `vars_files:` | 外部ファイルから読み込む変数 |
| 13 | Role vars | `roles/xxx/vars/main.yml` | Roleの内部変数（上書き非推奨） |
| 14 | Block vars | `block:` の `vars:` | ブロック内タスクに限定 |
| 15 | Task vars | タスクの `vars:` | 単一タスクに限定 |
| 16 | include_vars | `include_vars` モジュール | 動的な変数ファイル読み込み |
| 17 | set_fact / register | `set_fact` / `register` | 実行時に動的に設定 |
| 18 | Role params | `roles: - role: xxx var: val` | Role呼び出し時のパラメータ |
| 19 | Include params | `include_tasks` の `vars:` | include時のパラメータ |
| 20 | Extra vars (`-e`) | `-e "var=value"` | **最高優先度** — 全てを上書き |

---

**設計の指針**:

- **Role の defaults** に「利用者が自由に変更できるデフォルト値」を置く
- **group_vars / host_vars** に「環境固有の設定」を置く
- **Role の vars** に「Role内部で固定すべき値」を置く
- **extra vars** は「一時的な上書き」やデバッグに使う
- **include_vars** は「環境ごとの設定切り替え」に使う（高い優先順位に注意）

---

------

[次へ進む](./ex9.md)
