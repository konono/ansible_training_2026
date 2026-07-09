# 演習 2 - ad-hocコマンドの実行

[前に戻る](./ex1.md)

---

Playbookの実装を始める前に、Ansibleの動きを確かめるために、`ansible` コマンド経由でいくつかの**モジュール**を直接実行してみましょう。`ansible` コマンドはソフトウェアとしてのAnsibleと区別するために別名ad-hocコマンドとも呼ばれ、ここでもその呼び名を使っていきます。

モジュールは「よくあるIT運用作業」を部品化したもので、Ansibleからの自動操作は全てこのモジュールを介して行われます。Ansibleには数千のモジュールが組み込みで備わっており、Linux系マシン内の操作のみならず、Windowsやネットワーク機器、クラウドインフラに至るまで、広範囲の操作をモジュールを使って便利に自動化することができます。目的に合ったモジュールの探し方や、モジュールの配布単位である **Collection** については、Section 6 で詳しく説明します。

## Section 1: ping

まずはホストへのping実行から始めましょう。
`ping` モジュールを利用してwebグループのホストがAnsibleに応答可能であることを確認します。

```bash
$ ansible web -m ping
```

- `web` は操作対象とするグループ/ホストの指定、`-m` は使用モジュールを指定するオプションですので、このコマンドは「`web` グループに対して `ping` モジュールを実行」という意味になります。

成功時の実行結果は下記のようになります。

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

なお、`ping` モジュールは、通常のICMPプロトコルによる接続確認を行う `ping` ではなく、「Ansibleからホストが操作可能であることを確認する」という意味合いでの `ping` であり、対象へのSSHログインとPython利用確認までを行なっています。このモジュールを用いて対象ホストがAnsibleから操作可能な状態になっていることを確認することができます。

## Section 2: command

次に、`command` モジュールを実行してみます。`command` はホストに対して任意のコマンドを実行して、その結果を回収するモジュールになります。

```bash
$ ansible web -m command -a "uptime"
```

- `-a` オプションはモジュールに対する引数を指定するもので、ここでは `uptime` コマンドでシステムの稼働時間を確認しています。

実行結果は以下のようになります。

```
node1 | CHANGED | rc=0 >>
 12:34:56 up 1 day,  3:45,  0 users,  load average: 0.00, 0.01, 0.05
node2 | CHANGED | rc=0 >>
 12:34:56 up 1 day,  3:45,  0 users,  load average: 0.00, 0.01, 0.05
node3 | CHANGED | rc=0 >>
 12:34:56 up 1 day,  3:45,  0 users,  load average: 0.00, 0.01, 0.05
```

各モジュールに与えられる引数はAnsible公式サイトのモジュールドキュメント（[commandのドキュメント](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html)）か `ansible-doc` コマンドで `ansible-doc command` のようにして確認することができます。

`web` グループへの `uptime` が成功したら、次に以下のように実行対象を変えてみましょう。

```bash
$ ansible loadbalancer -m command -a "uptime"

$ ansible all -m command -a "uptime"
```

それぞれ、実行対象が変わることが確認できると思います。

**Note:** `all` は定義しなくても使える特別なグループ名で、インベントリに記載されたすべてのホストを対象とします。

## Section 3: setup

次にwebグループの内部情報を確認してみましょう。
`setup` モジュールを利用してホスト内の *facts* 情報を収集します。*facts* とはAnsible用語でホスト内のOSやハードウェア、ネットワークに関係する情報をまとめたもののことです。

```bash
$ ansible node1 -m setup
```

実行結果にはかなり長いJSONが出力されますが、一部を取り出してみると、例えば下記のようにLinux Distributionに関する情報が取得できていることがわかります。

```
node1 | SUCCESS =>
    ansible_facts:
        ...
        ansible_distribution: RedHat
        ansible_distribution_file_parsed: true
        ansible_distribution_file_path: /etc/redhat-release
        ansible_distribution_file_variety: RedHat
        ansible_distribution_major_version: '10'
        ansible_distribution_version: '10.2'
        ...
    changed: false
```

`setup` モジュールで収集されたfactsは、後ほど学習するplaybookの中で変数として活用することができます。例えばOSの種類に応じて処理を分岐させたい場合などに非常に便利です。

特定の情報だけを取得したい場合は、`filter` 引数を使用します。

```bash
$ ansible node1 -m setup -a "filter=ansible_distribution*"
```

```
node1 | SUCCESS =>
    ansible_facts:
        ansible_distribution: RedHat
        ansible_distribution_file_parsed: true
        ansible_distribution_file_path: /etc/redhat-release
        ansible_distribution_file_variety: RedHat
        ansible_distribution_major_version: '10'
        ansible_distribution_version: '10.2'
    changed: false
```

## Section 4: packageによるパッケージインストール

次に副作用を伴う操作として、[`package` モジュール](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/package_module.html)を利用してNginxをインストールしてみましょう。

```bash
$ ansible web -m package -a "name=nginx state=present" -b
```

- `-b` は `--become` の省略形で、Ansibleがリモートノードで処理を行う際に権限昇格を行う場合に必要となるオプションです。
  - デフォルトの権限昇格方法は `sudo` ですが、`su` なども選択可能です。

引数については以下のようになっています。

* **name** - 操作対象パッケージ名。複数パッケージをリストで渡すことも可能。
* **state** - パッケージのインストール状態。`present` は「存在する」=インストール済みの意味。
  * 一方、削除状態を示すのが `absent`
  * 他のモジュールでも状態を指定する `present/absent` は頻出

実行結果は以下のようになります。

```
node1 | CHANGED =>
    changed: true
    msg: ''
    rc: 0
    results:
    - 'Installed: nginx-2:1.26.3-x.el10.aarch64'
    - ...
node2 | CHANGED =>
    ...
node3 | CHANGED =>
    ...
```

一行目には **CHANGED** と表示され、端末の設定にもよりますが実行結果が黄色くハイライトされているかと思います。これはモジュール実行の結果、状態が変更された（Changed）ことを示しています。

それでは、Changedとそうではない時での出力の違いを確認するために、もう一度同じように `nginx` インストールを実行してみましょう。

```bash
$ ansible web -m package -a "name=nginx state=present" -b
```

```
node1 | SUCCESS =>
    changed: false
    msg: Nothing to do
    rc: 0
    results: []
node2 | SUCCESS =>
    ...
node3 | SUCCESS =>
    ...
```

今度は上記のように `SUCCESS` と表示が変わり、色も緑色になっています。
これは、`package` モジュールがホストの内部状態を確認し、`nginx` がインストール済みであったため何も実行しなかったことを表しています。このように操作対象を目的の状態にするために変更が必要ない場合は何もしないという特徴が多くのAnsibleモジュールに備わっています。これが「Ansibleには冪等性がある」と呼ばれる所以です。

**Note:** 全てのモジュールに冪等性がある訳ではないことに注意が必要です。例えば `command` モジュールは任意のコマンドを実行できるため、冪等性の有無は実行内容次第です。そのため `command` モジュールでは全ての実行結果がChanged扱いとなっています。

## Section 5: serviceによるサービス起動

Nginxのインストールが完了したら、[`service` モジュール](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)を利用してサービスを起動してみましょう。`service` モジュールはOSのサービスを操作するモジュールで、Systemd以外にも対応した汎用的なサービス管理モジュールです。

```bash
$ ansible web -m service -a "name=nginx state=started" -b
```

実行結果は以下のようになります。

```
node1 | CHANGED =>
    changed: true
    name: nginx
    state: started
    ...
node2 | CHANGED =>
    ...
node3 | CHANGED =>
    ...
```

引数の説明は以下の通りです。

* **name** - 操作対象サービス名
* **state** - サービス起動状態。`started` は「開始済み」=起動状態のこと。
  * 停止状態: `stopped`、再起動実施: `restarted`
  * `started` と過去分詞になっているのは、「開始する」という操作ではなく「開始済みである」という状態を宣言的に定義しているから

## Section 6: モジュールの探し方とCollection

ここまでの演習で `ping`、`command`、`setup`、`package`、`service` という5つのモジュールを使ってきました。しかし、Ansibleには数千ものモジュールが存在します。ここでは、目的に合ったモジュールを効率的に見つける方法と、モジュールを束ねる仕組みである **Collection** について学びましょう。

### Step 1: ansible-doc でモジュールを探す

`ansible-doc` コマンドはモジュールのドキュメントをターミナル上で参照するためのツールです。Section 2 で少し触れましたが、ここで改めて使い方を整理します。

**利用可能なモジュールの一覧を表示する:**

```bash
$ ansible-doc -l
```

大量のモジュールが表示されますので、キーワードで絞り込むと便利です。例えば「ファイル操作に使えるモジュールを探したい」という場合は以下のようにします。

```bash
$ ansible-doc -l | grep file
```

```
ansible.builtin.file          Manage files and file properties
ansible.builtin.find          Return a list of files based on specific criteria
ansible.builtin.lineinfile    Manage lines in text files
ansible.builtin.blockinfile   Insert/update/remove a text block surrounded by marker lines in a file
...
```

**特定のモジュールの詳細なドキュメントを表示する:**

```bash
$ ansible-doc file
```

ドキュメントにはモジュールの説明、使用可能なパラメータ、使用例などが記載されています。「このモジュールにはどんなオプションがあるのか？」を確認したい場合に非常に便利です。

### Step 2: 公式ドキュメントで探す

Webブラウザで探す場合は、Ansibleの公式ドキュメントにあるモジュール一覧が便利です。

- [Ansibleモジュール一覧（Collection Index）](https://docs.ansible.com/ansible/latest/collections/index_module.html)

カテゴリ別に整理されており、検索機能も備わっています。各モジュールのページには使用例も豊富に掲載されているため、初めて使うモジュールの場合は公式ドキュメントの使用例を参考にするのがおすすめです。

### Step 3: Collectionとは何か？

先ほどの `ansible-doc -l` の出力で、モジュール名の前に `ansible.builtin.` というプレフィックスが付いていたことに気づいたでしょうか。これは **Collection名** です。

**Collection** とは、モジュール・プラグイン・ロールなどをまとめてパッケージ化し、配布するための仕組みです。Ansible 2.9以前はほぼ全てのモジュールがAnsible本体に同梱されていましたが、現在はCollection単位で分離・配布される形になっています。

代表的なCollectionの例を挙げます。

| Collection名 | 内容 |
|---|---|
| `ansible.builtin` | Ansibleに組み込みのコアモジュール（`file`、`copy`、`command`、`service` など） |
| `ansible.posix` | POSIX系OS向けモジュール（`firewalld`、`sysctl` など） |
| `community.general` | コミュニティが提供する汎用モジュール群 |
| `amazon.aws` | AWS操作用モジュール（`ec2_instance`、`s3_bucket` など） |

### Step 4: FQCN（完全修飾コレクション名）

Collectionの導入に伴い、モジュールには **FQCN（Fully Qualified Collection Name）** という正式な名前が付けられています。

```
ansible.builtin.service
│              │
│              └─ モジュール名
└─ Collection名
```

この演習では短い名前（`service`、`package` など）を使ってきましたが、これは `ansible.builtin` コレクションのモジュールがデフォルトで省略可能だからです。しかし、`ansible.builtin` 以外のCollectionのモジュールを使う場合にはFQCNの指定が必要になります。

公式ドキュメントやroleの実装では、所属Collectionを明示するためにFQCNで記述することが推奨されています。

```yml
# 短い名前（ansible.builtin のモジュールでは動作する）
- name: install nginx
  package:
    name: nginx
    state: present

# FQCN（推奨される書き方）
- name: install nginx
  ansible.builtin.package:
    name: nginx
    state: present
```

### Step 5: 追加のCollectionをインストールする

Ansibleに同梱されていないCollectionは、`ansible-galaxy` コマンドでインストールすることができます。

```bash
$ ansible-galaxy collection install amazon.aws
```

インストール済みのCollectionは以下で確認できます。

```bash
$ ansible-galaxy collection list
```

Ansible Galaxyの[Collectionページ](https://galaxy.ansible.com/)でも、利用可能なCollectionを検索することができます。演習6で紹介するroleの共有と同様に、Collectionもコミュニティによって幅広く提供されています。

---
**NOTE**

「やりたいことがあるけど、どのモジュールを使えばいいかわからない」という場面は多いです。まずは `ansible-doc -l | grep <キーワード>` で心当たりのある単語で検索し、見つからなければ公式ドキュメントで探すという流れを覚えておくとよいでしょう。また、目的に合ったモジュールが `ansible.builtin` に見つからない場合は、追加のCollectionで提供されている可能性があります。

---


## Section 7: アクセス確認と環境クリーンアップ

### Step 1: curlによるアクセス確認

Nginxが起動できたら、実際にアクセスしてみましょう。コントローラーからターゲットノードのIPアドレスに直接curlでアクセスできます。

```bash
$ curl http://172.20.0.11
```

正常に設定が行われていれば、Red Hat Enterprise LinuxのHTTPテストページが表示されます。

```
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">

<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
	<head>
		<title>Test Page for the HTTP Server on Red Hat Enterprise Linux</title>
		...
	</head>
	<body>
		<h1>
            ...
            Red Hat Enterprise Linux <strong>Test Page</strong>
        </h1>
		...
	</body>
</html>
```

### Step 2: 環境クリーンアップ

最後に設定した情報をクリーンアップしていきます。
先ほどと逆の順番で、Nginxサービスの停止 → Nginxアンインストールを行います。

まず、Nginxサービスを停止します。

```bash
$ ansible web -m service -a "name=nginx state=stopped" -b
```

サービスが停止したことを確認するために、再度curlでアクセスしてみましょう。

```bash
$ curl http://172.20.0.11
```

今度はNginxが停止しているため、接続が拒否されエラーになるはずです。

次に、Nginxパッケージを削除します。

```bash
$ ansible web -m package -a "name=nginx state=absent" -b
```

```
node1 | CHANGED =>
    changed: true
    msg: ''
    rc: 0
    results:
    - 'Removed: nginx-2:1.26.3-x.el10.aarch64'
    - ...
```

これで環境のクリーンアップが完了しました。

この演習では、ad-hocコマンドを使ってAnsibleの基本的なモジュール操作を体験し、モジュールの探し方やCollectionの仕組みについても学びました。次の演習では、これらの操作をPlaybookとしてファイルにまとめて管理する方法を学びます。

---

[前に戻る](./ex1.md) | [次へ進む](./ex3.md)
