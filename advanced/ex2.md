# 応用演習 2 - ファイル操作と秘密情報管理

この演習では、Ansibleによるファイル操作と秘密情報管理を学びます。
`lineinfile`/`blockinfile`モジュールによる部分的なファイル編集、`include_vars`によるOS別変数の管理、そして`ansible-vault`による秘密情報の暗号化を実践します。

**前提条件:** 応用演習1を完了していること

[前に戻る](./ex1.md) | [次へ進む](./ex3.md)

---

## Section 1: lineinfile モジュール — 行単位のファイル編集

`lineinfile` モジュールは、ファイル内の特定の行を追加・変更・削除するためのモジュールです。設定ファイルの1行だけを変更したい場合に非常に便利です。

### Step 1: 行の追加

`/etc/motd` にウェルカムメッセージを追加します。

```bash
$ cd ~/advanced
```

```bash
$ vi lineinfile_add.yml
```

```yaml
---
- name: lineinfile - 行の追加
  hosts: web
  become: true

  tasks:
    - name: /etc/motd にウェルカムメッセージを追加
      lineinfile:
        path: /etc/motd
        line: "Welcome to Ansible Training - {{ inventory_hostname }}"
        state: present
        create: yes

    - name: /etc/motd の内容を確認
      command: cat /etc/motd
      register: motd_content
      changed_when: false

    - name: 内容を表示
      debug:
        msg: "{{ motd_content.stdout_lines }}"
```

```bash
$ ansible-playbook lineinfile_add.yml
```

```
PLAY [lineinfile - 行の追加] *****************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [/etc/motd にウェルカムメッセージを追加] **************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [/etc/motd の内容を確認] ****************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [内容を表示] *****************************************************************
ok: [node1] =>
  msg:
  - Welcome to Ansible Training - node1
ok: [node2] =>
  msg:
  - Welcome to Ansible Training - node2
ok: [node3] =>
  msg:
  - Welcome to Ansible Training - node3

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**Note:** `lineinfile` は冪等性があります。同じPlaybookを再度実行しても、行が重複して追加されることはありません。2回目の実行では `ok`（変更なし）と報告されます。

### Step 2: regexp を使った行の置換

既存の行をパターンマッチで検索し、置き換えます。

```bash
$ vi lineinfile_replace.yml
```

```yaml
---
- name: lineinfile - regexp による行の置換
  hosts: node1
  become: true

  tasks:
    - name: SSH 設定ファイルの内容を確認（変更前）
      command: grep -n "PermitRootLogin" /etc/ssh/sshd_config
      register: before_change
      changed_when: false
      ignore_errors: true

    - name: 変更前の内容を表示
      debug:
        msg: "{{ before_change.stdout_lines | default(['該当行なし']) }}"

    - name: PermitRootLogin の設定を変更
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: "^#?PermitRootLogin"
        line: "PermitRootLogin yes"
        state: present

    - name: SSH 設定ファイルの内容を確認（変更後）
      command: grep -n "PermitRootLogin" /etc/ssh/sshd_config
      register: after_change
      changed_when: false

    - name: 変更後の内容を表示
      debug:
        msg: "{{ after_change.stdout_lines }}"
```

```bash
$ ansible-playbook lineinfile_replace.yml
```

```
PLAY [lineinfile - regexp による行の置換] ****************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [SSH 設定ファイルの内容を確認（変更前）] **************************************
ok: [node1]

TASK [変更前の内容を表示] *********************************************************
ok: [node1] =>
  msg:
  - '40:PermitRootLogin yes'

TASK [PermitRootLogin の設定を変更] **********************************************
ok: [node1]

TASK [SSH 設定ファイルの内容を確認（変更後）] **************************************
ok: [node1]

TASK [変更後の内容を表示] *********************************************************
ok: [node1] =>
  msg:
  - '40:PermitRootLogin yes'

PLAY RECAP *********************************************************************
node1                      : ok=6    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

**Note:** コンテナ環境では `PermitRootLogin yes` が Containerfile で設定済みのため、変更は発生しません（`changed=0`）。初めてのサーバーでは `#PermitRootLogin prohibit-password` がデフォルト値であり、`regexp` による置換で `changed=1` となります。
```

`regexp: "^#?PermitRootLogin"` は、`#PermitRootLogin` または `PermitRootLogin` で始まる行にマッチします。`#?` は `#` が0回または1回出現することを意味する正規表現です。

### Step 3: insertafter / insertbefore による挿入位置の制御

```bash
$ vi lineinfile_insert.yml
```

```yaml
---
- name: lineinfile - insertafter / insertbefore
  hosts: node1
  become: true

  tasks:
    - name: 特定の行の後に挿入（insertafter）
      lineinfile:
        path: /etc/ssh/sshd_config
        insertafter: "^#?MaxSessions"
        line: "# MaxSessions was modified by Ansible"
        state: present

    - name: 特定の行の前に挿入（insertbefore）
      lineinfile:
        path: /etc/ssh/sshd_config
        insertbefore: "^#?MaxSessions"
        line: "# --- Ansible Managed Settings ---"
        state: present

    - name: sshd_config の該当箇所を確認
      command: grep -n -A2 -B2 "MaxSessions" /etc/ssh/sshd_config
      register: sshd_content
      changed_when: false

    - name: 内容を表示
      debug:
        msg: "{{ sshd_content.stdout_lines }}"
```

```bash
$ ansible-playbook lineinfile_insert.yml
```

```
PLAY [lineinfile - insertafter / insertbefore] **********************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [特定の行の後に挿入（insertafter）] ******************************************
changed: [node1]

TASK [特定の行の前に挿入（insertbefore）] ******************************************
changed: [node1]

TASK [sshd_config の該当箇所を確認] **********************************************
ok: [node1]

TASK [内容を表示] *****************************************************************
ok: [node1] =>
  msg:
  - '-- '
  - '# --- Ansible Managed Settings ---'
  - '#MaxSessions 10'
  - '# MaxSessions was modified by Ansible'
  - '-- '

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 4: 行の削除

`state: absent` を使って行を削除します。

```bash
$ vi lineinfile_remove.yml
```

```yaml
---
- name: lineinfile - 行の削除
  hosts: web
  become: true

  tasks:
    - name: ウェルカムメッセージを削除
      lineinfile:
        path: /etc/motd
        line: "Welcome to Ansible Training - {{ inventory_hostname }}"
        state: absent

    - name: /etc/motd の内容を確認
      command: cat /etc/motd
      register: motd_content
      changed_when: false
      ignore_errors: true

    - name: 内容を表示
      debug:
        msg: "{{ motd_content.stdout_lines | default(['(empty)']) }}"
```

```bash
$ ansible-playbook lineinfile_remove.yml
```

```
PLAY [lineinfile - 行の削除] *****************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [ウェルカムメッセージを削除] *************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [/etc/motd の内容を確認] ****************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [内容を表示] *****************************************************************
ok: [node1] =>
  msg: []
ok: [node2] =>
  msg: []
ok: [node3] =>
  msg: []

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 5: lineinfile の総合例

ここまでの内容をまとめた完全なPlaybookです。

```bash
$ vi lineinfile_complete.yml
```

```yaml
---
- name: lineinfile 総合例 - /etc/motd の管理
  hosts: all
  become: true

  tasks:
    - name: 全ノードの情報を /etc/motd に追加
      lineinfile:
        path: /etc/motd
        line: "Node: {{ item }}"
        state: present
        create: yes
      loop:
        - "node1 (172.20.0.11)"
        - "node2 (172.20.0.12)"
        - "node3 (172.20.0.13)"
        - "lb (172.20.0.14)"

    - name: /etc/motd の最終確認
      command: cat /etc/motd
      register: final_motd
      changed_when: false

    - name: 結果を表示
      debug:
        msg: "{{ final_motd.stdout_lines }}"
```

```bash
$ ansible-playbook lineinfile_complete.yml
```

```
PLAY [lineinfile 総合例 - /etc/motd の管理] **************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

TASK [全ノードの情報を /etc/motd に追加] ******************************************
changed: [node1] => (item=node1 (172.20.0.11))
changed: [node1] => (item=node2 (172.20.0.12))
changed: [node1] => (item=node3 (172.20.0.13))
changed: [node1] => (item=lb (172.20.0.14))
changed: [node2] => (item=node1 (172.20.0.11))
changed: [node2] => (item=node2 (172.20.0.12))
changed: [node2] => (item=node3 (172.20.0.13))
changed: [node2] => (item=lb (172.20.0.14))
changed: [node3] => (item=node1 (172.20.0.11))
changed: [node3] => (item=node2 (172.20.0.12))
changed: [node3] => (item=node3 (172.20.0.13))
changed: [node3] => (item=lb (172.20.0.14))
changed: [lb] => (item=node1 (172.20.0.11))
changed: [lb] => (item=node2 (172.20.0.12))
changed: [lb] => (item=node3 (172.20.0.13))
changed: [lb] => (item=lb (172.20.0.14))

TASK [/etc/motd の最終確認] ******************************************************
ok: [node1]
ok: [node2]
ok: [node3]
ok: [lb]

TASK [結果を表示] *****************************************************************
ok: [node1] =>
  msg:
  - 'Node: node1 (172.20.0.11)'
  - 'Node: node2 (172.20.0.12)'
  - 'Node: node3 (172.20.0.13)'
  - 'Node: lb (172.20.0.14)'

PLAY RECAP *********************************************************************
lb                         : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node1                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 2: blockinfile モジュール — ブロック単位のファイル編集

`blockinfile` モジュールは、複数行のテキストブロックをファイルに挿入・更新・削除します。マーカー行で囲まれたブロックとして管理されるため、再実行時にはブロック全体が更新されます。

### Step 1: blockinfile の基本的な使い方

```bash
$ vi blockinfile_demo.yml
```

```yaml
---
- name: blockinfile デモ
  hosts: node1
  become: true

  tasks:
    - name: nginx がインストール済みであることを確認
      package:
        name: nginx
        state: present

    - name: nginx のサーバーブロックを追加
      blockinfile:
        path: /etc/nginx/sites-enabled/training.conf
        create: true
        marker: "# {mark} ANSIBLE MANAGED BLOCK - training app"
        block: |
          server {
              listen 8080;
              server_name training.local;

              location / {
                  root /usr/share/nginx/html;
                  index index.html;
              }

              location /health {
                  access_log off;
                  return 200 'OK';
                  add_header Content-Type text/plain;
              }
          }

    - name: 設定ファイルの内容を確認
      command: cat /etc/nginx/sites-enabled/training.conf
      register: conf_content
      changed_when: false

    - name: 内容を表示
      debug:
        msg: "{{ conf_content.stdout_lines }}"
```

```bash
$ ansible-playbook blockinfile_demo.yml
```

```
PLAY [blockinfile デモ] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [nginx がインストール済みであることを確認] ************************************
ok: [node1]

TASK [nginx のサーバーブロックを追加] **********************************************
changed: [node1]

TASK [設定ファイルの内容を確認] ****************************************************
ok: [node1]

TASK [内容を表示] *****************************************************************
ok: [node1] =>
  msg:
  - '# BEGIN ANSIBLE MANAGED BLOCK - training app'
  - 'server {'
  - '    listen 8080;'
  - '    server_name training.local;'
  - ''
  - '    location / {'
  - '        root /usr/share/nginx/html;'
  - '        index index.html;'
  - '    }'
  - ''
  - '    location /health {'
  - '        access_log off;'
  - "        return 200 'OK';"
  - '        add_header Content-Type text/plain;'
  - '    }'
  - '}'
  - '# END ANSIBLE MANAGED BLOCK - training app'

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**blockinfile と template の違い:**

| 特性 | blockinfile | template |
|------|------------|----------|
| 編集方式 | ファイル内の一部分を編集 | ファイル全体を置き換え |
| 既存内容 | マーカーブロック以外は保持 | すべて上書き |
| 用途 | 設定ファイルにブロックを追加 | ファイル全体を管理 |
| マーカー | マーカー行で管理範囲を識別 | 不要 |

既存の設定ファイルに一部分だけ追記したい場合は `blockinfile`、ファイル全体をテンプレートから生成する場合は `template` を使います。

---

## Section 3: include_vars / vars_files — 変数ファイルの管理

異なるOS（RedHat/Debian）やEnvironment（本番/開発）で異なる変数を使いたい場合、変数ファイルを分割して条件に応じて読み込めます。

### Step 1: OS別の変数ファイルを作成

```bash
$ mkdir -p ~/advanced/vars
```

RedHat系（UBI 10を含む）用の変数ファイルを作成します。

```bash
$ vi ~/advanced/vars/RedHat.yml
```

```yaml
---
web_package: nginx
web_service: nginx
web_config_path: /etc/nginx/nginx.conf
web_docroot: /usr/share/nginx/html
firewall_package: firewalld
package_manager: dnf
```

Debian系用の変数ファイルも参考として作成します。

```bash
$ vi ~/advanced/vars/Debian.yml
```

```yaml
---
web_package: nginx
web_service: nginx
web_config_path: /etc/nginx/nginx.conf
web_docroot: /var/www/html
firewall_package: ufw
package_manager: apt
```

### Step 2: include_vars で動的に読み込み

```bash
$ vi include_vars_demo.yml
```

```yaml
---
- name: include_vars デモ - OS 別変数の読み込み
  hosts: web
  become: true

  tasks:
    - name: OS ファミリーに応じた変数ファイルを読み込み
      include_vars: "vars/{{ ansible_os_family }}.yml"

    - name: 読み込まれた変数を表示
      debug:
        msg:
          - "パッケージ名: {{ web_package }}"
          - "サービス名: {{ web_service }}"
          - "設定ファイル: {{ web_config_path }}"
          - "ドキュメントルート: {{ web_docroot }}"
          - "パッケージマネージャー: {{ package_manager }}"

    - name: Web サーバーをインストール
      package:
        name: "{{ web_package }}"
        state: present

    - name: Web サーバーを起動
      service:
        name: "{{ web_service }}"
        state: started
        enabled: true
```

```bash
$ ansible-playbook include_vars_demo.yml
```

```
PLAY [include_vars デモ - OS 別変数の読み込み] *************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [OS ファミリーに応じた変数ファイルを読み込み] **********************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [読み込まれた変数を表示] ******************************************************
ok: [node1] =>
  msg:
  - 'パッケージ名: nginx'
  - 'サービス名: nginx'
  - '設定ファイル: /etc/nginx/nginx.conf'
  - 'ドキュメントルート: /usr/share/nginx/html'
  - 'パッケージマネージャー: dnf'
ok: [node2] =>
  msg:
  - 'パッケージ名: nginx'
  - 'サービス名: nginx'
  - '設定ファイル: /etc/nginx/nginx.conf'
  - 'ドキュメントルート: /usr/share/nginx/html'
  - 'パッケージマネージャー: dnf'
ok: [node3] =>
  msg:
  - 'パッケージ名: nginx'
  - 'サービス名: nginx'
  - '設定ファイル: /etc/nginx/nginx.conf'
  - 'ドキュメントルート: /usr/share/nginx/html'
  - 'パッケージマネージャー: dnf'

TASK [Web サーバーをインストール] **************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [Web サーバーを起動] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 3: vars_files によるプレイレベルでの読み込み

`vars_files` はプレイレベルで変数ファイルを読み込む方法です。`include_vars` がタスクレベルで動的に読み込むのに対し、`vars_files` はプレイの開始時に読み込まれます。

```bash
$ vi ~/advanced/vars/common.yml
```

```yaml
---
app_name: training-app
app_version: "1.0.0"
app_port: 8080
app_environment: development
```

```bash
$ vi vars_files_demo.yml
```

```yaml
---
- name: vars_files デモ
  hosts: web
  become: true
  vars_files:
    - vars/common.yml

  tasks:
    - name: アプリケーション設定を表示
      debug:
        msg:
          - "アプリ名: {{ app_name }}"
          - "バージョン: {{ app_version }}"
          - "ポート: {{ app_port }}"
          - "環境: {{ app_environment }}"

    - name: OS 別変数を動的に読み込み
      include_vars: "vars/{{ ansible_os_family }}.yml"

    - name: 全変数を表示
      debug:
        msg:
          - "アプリ名: {{ app_name }}"
          - "Web サーバー: {{ web_package }}"
          - "ドキュメントルート: {{ web_docroot }}"
```

```bash
$ ansible-playbook vars_files_demo.yml
```

```
PLAY [vars_files デモ] ***********************************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [アプリケーション設定を表示] **************************************************
ok: [node1] =>
  msg:
  - 'アプリ名: training-app'
  - 'バージョン: 1.0.0'
  - 'ポート: 8080'
  - '環境: development'

TASK [OS 別変数を動的に読み込み] ****************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [全変数を表示] ***************************************************************
ok: [node1] =>
  msg:
  - 'アプリ名: training-app'
  - 'Web サーバー: nginx'
  - 'ドキュメントルート: /usr/share/nginx/html'

PLAY RECAP *********************************************************************
node1                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Section 4: ansible-vault — 秘密情報の暗号化

`ansible-vault` は、パスワード、APIキー、証明書などの秘密情報を暗号化して管理するためのツールです。暗号化されたファイルは安全にバージョン管理システム（Git等）に保存できます。

### Step 1: 暗号化ファイルの作成

```bash
$ ansible-vault create secrets.yml
```

コマンドを実行すると、まずVaultパスワードの入力を求められます。

```
New Vault password: （パスワードを入力、例: training123）
Confirm New Vault password: （同じパスワードを再入力）
```

エディタが開くので、以下の内容を入力して保存します。

```yaml
---
db_password: "S3cureP@ssw0rd!"
api_key: "sk-abc123def456ghi789"
admin_email: "admin@training.local"
```

保存すると、ファイルは自動的に暗号化されます。

### Step 2: 暗号化されたファイルの確認

暗号化されたファイルの内容を直接見ると、以下のように表示されます。

```bash
$ cat secrets.yml
```

```
$ANSIBLE_VAULT;1.1;AES256
33393438623665623864336234636430356330636336343932313631353762396534343438653932
65363533623637393232306466376265653262643839326233350a373161383831323666643933346
...
```

### Step 3: vault の基本操作

暗号化されたファイルの内容を確認（復号表示）するには `view` を使います。

```bash
$ ansible-vault view secrets.yml
```

```
Vault password: （パスワードを入力）
---
db_password: "S3cureP@ssw0rd!"
api_key: "sk-abc123def456ghi789"
admin_email: "admin@training.local"
```

暗号化されたファイルを編集するには `edit` を使います。

```bash
$ ansible-vault edit secrets.yml
```

```
Vault password: （パスワードを入力）
```

エディタが開き、復号化された状態で編集できます。保存すると自動的に再暗号化されます。

既存の平文ファイルを暗号化するには `encrypt` を使います。

```bash
$ echo "secret_data: very_secret" > plain_secrets.yml
$ ansible-vault encrypt plain_secrets.yml
```

```
New Vault password: （パスワードを入力）
Confirm New Vault password: （同じパスワードを再入力）
Encryption successful
```

暗号化されたファイルを恒久的に復号化するには `decrypt` を使います。

```bash
$ ansible-vault decrypt plain_secrets.yml
```

```
Vault password: （パスワードを入力）
Decryption successful
```

### Step 4: Playbook で vault ファイルを使用

```bash
$ vi vault_playbook.yml
```

```yaml
---
- name: Vault で管理された秘密情報を使用
  hosts: node1
  become: true
  vars_files:
    - secrets.yml

  tasks:
    - name: 設定ファイルのディレクトリを作成
      file:
        path: /etc/app
        state: directory
        mode: '0755'

    - name: 秘密情報を使って設定ファイルを作成
      copy:
        dest: /etc/app/config.ini
        content: |
          [database]
          password={{ db_password }}

          [api]
          key={{ api_key }}

          [admin]
          email={{ admin_email }}
        mode: '0600'

    - name: 設定ファイルが作成されたことを確認
      stat:
        path: /etc/app/config.ini
      register: config_stat

    - name: 結果を表示
      debug:
        msg: "設定ファイル作成: {{ config_stat.stat.exists }}, パーミッション: {{ config_stat.stat.mode }}"
```

`--ask-vault-pass` オプションを付けて実行します。

```bash
$ ansible-playbook vault_playbook.yml --ask-vault-pass
```

```
Vault password: （パスワードを入力）

PLAY [Vault で管理された秘密情報を使用] *******************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [設定ファイルのディレクトリを作成] ********************************************
changed: [node1]

TASK [秘密情報を使って設定ファイルを作成] ******************************************
changed: [node1]

TASK [設定ファイルが作成されたことを確認] ******************************************
ok: [node1]

TASK [結果を表示] *****************************************************************
ok: [node1] =>
  msg: '設定ファイル作成: True, パーミッション: 0600'

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Step 5: パスワードファイルによる自動化

毎回パスワードを手入力する代わりに、パスワードファイルを使うことで自動化できます。

```bash
$ echo "training123" > ~/.vault_password
$ chmod 600 ~/.vault_password
```

パスワードファイルを指定して実行します。

```bash
$ ansible-playbook vault_playbook.yml --vault-password-file ~/.vault_password
```

```
PLAY [Vault で管理された秘密情報を使用] *******************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]

TASK [設定ファイルのディレクトリを作成] ********************************************
ok: [node1]

TASK [秘密情報を使って設定ファイルを作成] ******************************************
ok: [node1]

TASK [設定ファイルが作成されたことを確認] ******************************************
ok: [node1]

TASK [結果を表示] *****************************************************************
ok: [node1] =>
  msg: '設定ファイル作成: True, パーミッション: 0600'

PLAY RECAP *********************************************************************
node1                      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`ansible.cfg` にデフォルトのパスワードファイルを設定することもできます。

```ini
[defaults]
vault_password_file = ~/.vault_password
```

**Note:** パスワードファイル（`~/.vault_password`）は `.gitignore` に追加し、バージョン管理に含めないでください。

---

## Section 5: 実践演習 — ファイル操作と秘密情報の統合

ここまで学んだ内容を組み合わせて、実践的なPlaybookを作成します。

### Step 1: 秘密情報を含む変数ファイルの作成

```bash
$ ansible-vault create ~/advanced/vars/credentials.yml
```

Vaultパスワード（例: `training123`）を入力後、以下を記述します。

```yaml
---
db_host: "172.20.0.20"
db_port: 5432
db_name: "training_db"
db_user: "app_user"
db_password: "Str0ngP@ssw0rd!"
```

### Step 2: 実践Playbookの作成

```bash
$ vi practice_ex2.yml
```

```yaml
---
- name: 実践演習 - ファイル操作と秘密情報管理
  hosts: web
  become: true
  vars_files:
    - vars/common.yml
    - vars/credentials.yml

  tasks:
    # --- OS 別変数の読み込み ---
    - name: OS 別変数を読み込み
      include_vars: "vars/{{ ansible_os_family }}.yml"

    - name: 使用する変数を確認
      debug:
        msg:
          - "OS: {{ ansible_os_family }}"
          - "Web サーバー: {{ web_package }}"
          - "アプリ名: {{ app_name }}"

    # --- /etc/motd の管理 ---
    - name: /etc/motd に全ノードの情報を登録
      lineinfile:
        path: /etc/motd
        line: "Node: {{ item }}"
        state: present
        create: yes
      loop:
        - "node1 (172.20.0.11)"
        - "node2 (172.20.0.12)"
        - "node3 (172.20.0.13)"
        - "lb (172.20.0.14)"

    # --- nginx の設定 ---
    - name: nginx をインストール
      package:
        name: "{{ web_package }}"
        state: present

    - name: アプリケーション設定を配置（blockinfile）
      blockinfile:
        path: /etc/nginx/sites-enabled/app.conf
        create: true
        marker: "# {mark} ANSIBLE MANAGED - {{ app_name }}"
        block: |
          server {
              listen {{ app_port }};
              server_name {{ inventory_hostname }}.training.local;

              location / {
                  root {{ web_docroot }};
                  index index.html;
              }
          }

    # --- 秘密情報を使った設定ファイル ---
    - name: データベース接続設定を作成（vault で暗号化された認証情報を使用）
      copy:
        dest: /etc/app-db.conf
        content: |
          [database]
          host={{ db_host }}
          port={{ db_port }}
          name={{ db_name }}
          user={{ db_user }}
          password={{ db_password }}
        mode: '0600'
        owner: root
        group: root

    # --- バリデーション ---
    - name: nginx の設定チェック
      command: nginx -t
      changed_when: false

    - name: nginx を再起動
      service:
        name: nginx
        state: restarted
        enabled: true

    - name: /etc/motd の最終確認
      command: cat /etc/motd
      register: motd_result
      changed_when: false

    - name: 最終結果を表示
      debug:
        msg:
          - "--- /etc/motd ---"
          - "{{ motd_result.stdout_lines }}"
```

### Step 3: 実行

```bash
$ ansible-playbook practice_ex2.yml --vault-password-file ~/.vault_password
```

```
PLAY [実践演習 - ファイル操作と秘密情報管理] **************************************

TASK [Gathering Facts] *********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [OS 別変数を読み込み] ********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [使用する変数を確認] *********************************************************
ok: [node1] =>
  msg:
  - 'OS: RedHat'
  - 'Web サーバー: nginx'
  - 'アプリ名: training-app'

TASK [/etc/motd に全ノードの情報を登録] ********************************************
changed: [node1] => (item=node1 (172.20.0.11))
changed: [node1] => (item=node2 (172.20.0.12))
changed: [node1] => (item=node3 (172.20.0.13))
changed: [node1] => (item=lb (172.20.0.14))
changed: [node2] => (item=node1 (172.20.0.11))
changed: [node2] => (item=node2 (172.20.0.12))
changed: [node2] => (item=node3 (172.20.0.13))
changed: [node2] => (item=lb (172.20.0.14))
changed: [node3] => (item=node1 (172.20.0.11))
changed: [node3] => (item=node2 (172.20.0.12))
changed: [node3] => (item=node3 (172.20.0.13))
changed: [node3] => (item=lb (172.20.0.14))

TASK [nginx をインストール] *******************************************************
ok: [node1]
changed: [node2]
changed: [node3]

TASK [アプリケーション設定を配置（blockinfile）] ************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [データベース接続設定を作成（vault で暗号化された認証情報を使用）] ****************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [nginx の設定チェック] *******************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [nginx を再起動] ************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [/etc/motd の最終確認] ******************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [最終結果を表示] *************************************************************
ok: [node1] =>
  msg:
  - '--- /etc/motd ---'
  - - 'Node: node1 (172.20.0.11)'
    - 'Node: node2 (172.20.0.12)'
    - 'Node: node3 (172.20.0.13)'
    - 'Node: lb (172.20.0.14)'

PLAY RECAP *********************************************************************
node1                      : ok=11   changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=11   changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=11   changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## まとめ

この演習で学んだ内容:

| 機能 | 用途 |
|------|------|
| `lineinfile` | ファイル内の特定の1行を追加・変更・削除する |
| `blockinfile` | ファイル内にマーカー付きのテキストブロックを管理する |
| `include_vars` | タスクレベルで条件に応じた変数ファイルを読み込む |
| `vars_files` | プレイレベルで変数ファイルを読み込む |
| `ansible-vault create` | 暗号化された変数ファイルを新規作成する |
| `ansible-vault encrypt/decrypt` | 既存ファイルの暗号化/復号化を行う |
| `ansible-vault view/edit` | 暗号化ファイルの閲覧/編集を行う |
| `--ask-vault-pass` | 実行時にVaultパスワードを対話的に入力する |
| `--vault-password-file` | パスワードファイルを指定して自動化する |

---

[前に戻る](./ex1.md) | [次へ進む](./ex3.md)
