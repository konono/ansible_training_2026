# 演習 1 - 環境セットアップと初めての接続

> **注意:** この演習のすべてのコマンドは、コントローラーコンテナ内（`ssh -p 2220 root@localhost` でログインした状態）で実行してください。

この演習では、Ansibleの環境セットアップを行い、管理対象ノードへの初めての接続を確認します。
Ansibleの設定ファイル（ansible.cfg）の作成、YAML形式のインベントリファイルの作成、そして接続確認までを行います。

## Section 1: Ansibleのバージョン確認と設定ファイルの優先順位

### Step 1: Ansibleのバージョン確認

まずは、Ansibleが正しくインストールされていることを確認しましょう。

```bash
$ ansible --version
```

以下のような出力が表示されます。

```
ansible [core 2.21.x]
  config file = None
  configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /path/to/lib/python3.x/site-packages/ansible
  executable location = /path/to/bin/ansible
  python version = 3.x.x
```

この出力から、Ansibleのバージョン、使用中の設定ファイルのパス、Pythonのバージョンなどを確認できます。
現時点では `config file = None` と表示され、設定ファイルがまだ読み込まれていない状態です。

### Step 2: 設定ファイルの優先順位

Ansibleの設定ファイル（`ansible.cfg`）は、以下の順序で検索されます。下にあるものほど優先度が高くなります。

1. `/etc/ansible/ansible.cfg` - システム全体のデフォルト設定
2. `~/.ansible.cfg` - ユーザーのホームディレクトリ内の設定
3. `./ansible.cfg` - カレントディレクトリ内の設定（**最も優先度が高い**）

また、環境変数 `ANSIBLE_CONFIG` で設定ファイルのパスを明示的に指定することも可能です。この場合、上記のいずれよりも優先されます。

**Note:** 複数の設定ファイルがマージされることはなく、最も優先度の高い1つのファイルのみが読み込まれます。

## Section 2: ansible.cfg の作成

### Step 1: 作業ディレクトリへの移動

ワークスペースが既にマウントされているので、移動するだけで準備完了です。

```bash
$ cd ~/basic-intro
```

### Step 2: ansible.cfg の作成

カレントディレクトリに `ansible.cfg` を作成します。このファイルがAnsibleの動作を制御する設定ファイルとなります。

```bash
$ vi ansible.cfg
```

以下の内容を記述してください。

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

各設定項目の説明は以下の通りです。

* **stdout_callback = ansible.builtin.default** / **callback_result_format = yaml** - デフォルトの出力コールバックを使用し、結果の表示形式をYAML形式にします。デフォルトのJSON形式よりも読みやすくなります。
* **host_key_checking = False** - SSH接続時のホストキーチェックを無効化します。初回接続時に確認プロンプトが表示されなくなるため、自動化に適しています。
* **inventory = ./inventory.yml** - デフォルトのインベントリファイルのパスを指定します。これにより、コマンド実行時に `-i` オプションでインベントリファイルを毎回指定する必要がなくなります。
* **pipelining = True** - SSH接続の効率を向上させます。

### Step 3: 設定ファイルの読み込み確認

設定ファイルが正しく読み込まれていることを確認します。

```bash
$ ansible --version
```

```
ansible [core 2.21.x]
  config file = /root/basic-intro/ansible.cfg
  ...
```

`config file` の行に、作成した `ansible.cfg` のパスが表示されていれば成功です。

## Section 3: YAML形式のインベントリ作成

### Step 1: インベントリファイルの概要

インベントリとは、Ansibleの管理対象ホストと各ホストが所属するグループを定義するものです。
インベントリにはINI形式とYAML形式がありますが、ここではYAML形式で作成します。YAML形式は階層構造を明確に表現でき、可読性にも優れています。

### Step 2: インベントリファイルの作成

```bash
$ vi inventory.yml
```

以下の内容を記述してください。

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

各項目の説明は以下の通りです。

* **all** - 全ホストが暗黙的に所属する特別なグループです。
* **vars** - グループに属する全ホストに適用される変数を定義します。
  * `ansible_user` - SSH接続に使用するユーザー名
  * `ansible_ssh_pass` - SSH接続に使用するパスワード
  * `ansible_port` - SSH接続に使用するポート番号（デフォルトの22番ポート）
* **children** - 子グループを定義します。
  * `web` - Webサーバーのグループ。`node1`、`node2`、`node3` が所属。
  * `loadbalancer` - ロードバランサーのグループ。`lb` が所属。
* **hosts** - グループに属するホストを定義します。
  * `ansible_host` - 実際の接続先IPアドレスを指定します。コントローラーからコンテナネットワーク経由で直接アクセスするため、各コンテナのIPアドレスを指定しています。

## Section 4: 接続確認

インベントリと設定ファイルが完成したので、実際にAnsibleから管理対象ノードへ接続できることを確認しましょう。

### Step 1: 全ホストへの接続確認

`ping` モジュールを使って、全ホストがAnsibleから操作可能であることを確認します。

```bash
$ ansible all -m ping
```

成功すると以下のような出力が表示されます。

```
node1 | SUCCESS =>
    changed: false
    ping: pong
node2 | SUCCESS =>
    changed: false
    ping: pong
node3 | SUCCESS =>
    changed: false
    ping: pong
lb | SUCCESS =>
    changed: false
    ping: pong
```

**Note:** `ping` モジュールは、通常のICMPプロトコルによる `ping` ではありません。Ansibleの `ping` はSSH接続とPythonの利用確認を行い、「Ansibleからホストが操作可能であること」を確認するためのモジュールです。

### Step 2: グループ別の接続確認

特定のグループのみを対象にして接続確認を行うこともできます。

```bash
$ ansible web -m ping
```

```
node1 | SUCCESS =>
    changed: false
    ping: pong
node2 | SUCCESS =>
    changed: false
    ping: pong
node3 | SUCCESS =>
    changed: false
    ping: pong
```

`web` グループの3台のノードのみが対象となっていることがわかります。

```bash
$ ansible loadbalancer -m ping
```

```
lb | SUCCESS =>
    changed: false
    ping: pong
```

> **Note:** `ANSIBLE_PYTHON_INTERPRETER` 環境変数がコンテナに設定済みのため、`discovered_interpreter_python` の表示は出ません。

`loadbalancer` グループのロードバランサーのみが対象となっていることを確認できます。

### Step 3: 接続エラー時のトラブルシューティング

もしエラーが発生する場合は、以下の点を確認してください。

* `inventory.yml` 内の `ansible_host`（IPアドレス）が正しいか
* `ansible_user` と `ansible_ssh_pass` が正しいか
* 対象ノードのSSHサービスが起動しているか
* `ansible.cfg` 内の `inventory` パスが正しいか

ここまでで、Ansibleの環境セットアップと接続確認が完了しました。次の演習では、ad-hocコマンドを使って様々なモジュールを実行してみましょう。

---

[次へ進む](./ex2.md)
