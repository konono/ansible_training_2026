# 演習 3 - 初めてのPlaybook作成

[前に戻る](./ex2.md)

---

この演習では **playbook** を作成してみましょう。
playbookは先程ad-hocコマンドで実行したモジュール呼び出しを組み合わせてYAML形式のファイルでまとめたものです。

## Section 1: YAMLの文法

YAMLは以下のような特徴をもったファイル形式です。

* 表現できる内容はJSONと同等

* 先頭行は `---` （必須ではないが慣習として推奨）

* インデント（字下げ）を使い階層構造を表現する

  * インデントはスペースのみ。タブ文字は使用できない。
  * インデント幅は通常スペース2つ

* `#` 始まりでコメントを記述できる

* 以下はいずれも真偽値(True/False)となる

  * `true/false`
  * `yes/no`
  * `on/off`

* 文字列はクオートなしでもクオートありでもOK

  ```yaml
  # いずれも同じ文字列となる
  My favorite book
  'My favorite book'
  "My favorite book"
  ```

* ハイフン区切りでリストを表現

  ```yaml
  # 以下は [blue, yellow, red] 3つの要素を持つリストとなる
  - blue
  - yellow
  - red
  ```

* 辞書は `key: value` の形式で表現

  ```yaml
  book: 'My favorite book'
  colors:
    - 'blue'
    - 'yellow'
    - 'red'
  # 入れ子構造も可能
  nested:
    key: 'value'
    items:
      - name: 'apple'
        kind: 'fruit'
      - name: 'carrot'
        kind: 'vegetable'
  ```

YAMLの文法については、Ansibleドキュメント中にも[解説ドキュメント](https://docs.ansible.com/ansible/latest/reference_appendices/YAMLSyntax.html)があります。

## Section 2: Playbookの構成

Playbookの中では1つまたは複数の **play** に、1つまたは複数の **task** を定義するという構成となります。

- *play* は特定のグループ/ホストに対して実行する一連のtaskをまとめたもの
  - 例えば、dbグループとappグループで構成されるシステムをセットアップするplaybookであれば、`db` を操作するplayと `app` を操作するplayが組み合わさって1つのplaybookとなる
- *task* はad-hocコマンドで実行したのと同様の1つ1つのモジュール呼び出しの定義

この演習のplaybookでは、先ほどad-hocで実行したのと同内容の「webグループにNginxをデプロイする」作業を1つのplayとして実装していきます。

## Section 3: Playbookファイルの作成

### Step 1: ファイルの作成

エディタで `install_nginx.yml` ファイルを作成/編集します。

```bash
$ vi install_nginx.yml
```

### Step 2: Playの定義

まず、playの基本情報を定義します。

```yaml
---
- hosts: web
  name: Install the nginx web service
  become: yes
```

各項目の説明は以下の通りです。

- `---` YAML開始を定義
- `hosts: web` はこのPlaybookを実行する対象のグループを指定しています。グループ名はインベントリファイルで定義されています。
- `name: Install the nginx web service` playに名称を設定しています。任意の名称設定が可能です。名称は付けないこともできますが、基本的には何のplayかわかるような名前を付けるようにしましょう。
- `become: yes` リモートホストで権限昇格を行い管理者権限で操作を実行することを指定しています。ad-hocコマンドで使った `-b` オプションと同じ意味です。

### Step 3: Taskの追加

続けて実行する複数のtaskを追加しましょう。
このあとに記述する `tasks` の *t* と、先ほどのplayで記載した `become` の *b* が、インデントで同じ位置に来るように調整してください。
インデントでデータを表現するYAMLではこの記述の仕方がとても重要です。

```yaml
  tasks:
    - name: install nginx
      package:
        name: nginx
        state: present

    - name: start nginx
      service:
        name: nginx
        state: started
```

各項目の説明は以下の通りです。

- `tasks:` play内での実行タスクをここに定義する
- `- name:` playbookの実行時に標準出力されるそれぞれのtask名称です。簡潔かつ適切なtask名を記入します。

```yaml
    package:
      name: nginx
      state: present
```

- これらの3行はNginxをインストールするためAnsibleの *package* モジュールを呼び出しています。
  - `package` モジュールのドキュメントは[こちら](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/package_module.html)

```yaml
    service:
      name: nginx
      state: started
```

- 上記では、Nginxサービスを開始するため、*service* モジュールを呼び出しています。
  - `service` モジュールのドキュメントは[こちら](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/service_module.html)

### Step 4: Playbookの保存

playbookを書き終えたら、保存しましょう。
viエディタの場合は [Esc]キー押下で編集モードを終了し、`:wq` を入力して[Enter]押下でファイルを保存できます。

playbook YAMLは最終的に以下のような形になっているはずです。

```yaml
---
- hosts: web
  name: Install the nginx web service
  become: yes
  tasks:
    - name: install nginx
      package:
        name: nginx
        state: present

    - name: start nginx
      service:
        name: nginx
        state: started
```

## Section 4: 構文チェック

作成したplaybookの構文に誤りがないか確認しましょう。`--syntax-check` オプションを使います。

```bash
$ ansible-playbook install_nginx.yml --syntax-check
```

```
playbook: install_nginx.yml
```

上記のようにエラーなく表示されれば、YAMLの構文に問題はありません。
もしエラーが出る場合は、インデントの位置がずれていないかなどを確認してください。

## Section 5: チェックモードでの実行（ドライラン）

次にplaybookをチェックモード（ドライラン）で実行してみましょう。
チェックモードを利用することで、実際の変更操作をする前にplaybook実行後の状態を確認することができます。

```bash
$ ansible-playbook install_nginx.yml --check
```

実行結果は以下のようになります。

```
PLAY [Install the nginx web service] ******************************************

TASK [Gathering Facts] ********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [install nginx] **********************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [start nginx] ************************************************************
fatal: [node1]: FAILED! =>
    changed: false
    msg: 'Could not find the requested service nginx: host'
fatal: [node2]: FAILED! =>
    changed: false
    msg: 'Could not find the requested service nginx: host'
fatal: [node3]: FAILED! =>
    changed: false
    msg: 'Could not find the requested service nginx: host'

PLAY RECAP ********************************************************************
node1                      : ok=2    changed=1    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
node2                      : ok=2    changed=1    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
node3                      : ok=2    changed=1    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
```

*install nginx* タスクはchangedステータスになっていますが、*start nginx* タスクでエラーが発生しています。これはチェックモードの制限によるものです。チェックモードでは実際のパッケージインストールは行われないため、`service` モジュールがNginxサービスを見つけられずにエラーとなります。

このように、前のタスクの結果に依存するタスクがある場合、チェックモードでは正確な結果が得られないことがあります。これはplaybookの記述が間違っているわけではなく、チェックモードの既知の制限です。次のステップで実際に実行して確認しましょう。

上記の出力を見て、playbook中で定義を行なっていない *Gathering Facts* というタスクが最初に実行されていることが気になったかもしれません。
これはplay実行の最初にAnsibleが暗黙的に実行するタスクで、`setup` モジュールを使ってfactsの収集を行なっているものです。

## Section 6: Playbookの実行

構文チェックとチェックモードでの確認が終わったら、実際のデプロイを行いましょう。

```bash
$ ansible-playbook install_nginx.yml
```

```
PLAY [Install the nginx web service] ******************************************

TASK [Gathering Facts] ********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [install nginx] **********************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [start nginx] ************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

PLAY RECAP ********************************************************************
node1                      : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

今度は実際にデプロイが行われています。

また、再度playbookを実行してみると、全taskの実行結果が `ok` に変わっていることも確認できます。これがAnsibleの冪等性です。

```bash
$ ansible-playbook install_nginx.yml
```

```
PLAY [Install the nginx web service] ******************************************

TASK [Gathering Facts] ********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [install nginx] **********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [start nginx] ************************************************************
ok: [node1]
ok: [node2]
ok: [node3]

PLAY RECAP ********************************************************************
node1                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

## Section 7: curlによるアクセス確認

コントローラーからターゲットノードに直接curlでアクセスしてみましょう。正常に設定が行われていれば、Nginxの初期画面が表示されます。

```bash
$ curl http://172.20.0.11
```

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

		<div class="content">
			<div class="content-middle">
				<p>This page is used to test the proper operation of the HTTP server after it has been installed. If you can read this page, it means that the HTTP server installed at this site is working properly.</p>
			</div>
			...
		</div>
	</body>
</html>
```

NginxのデフォルトのHTTPテストページが表示され、正常にインストールされ起動していることが確認できました。

## Section 8: 演習 - アンインストール用Playbookの作成

先程作成した `install_nginx.yml` を参考にして `uninstall_nginx.yml` を作成して実行してください。以下にヒントを記載しますので、まずは自分で実装をしてみましょう。

- `package` モジュールでパッケージを削除するには `state: absent` とする。
- `service` モジュールでサービスを停止するには `state: stopped` とする。
- 実行する順番に気をつけてください。パッケージを削除する前にサービスを停止する必要があります。
- 一度Nginxを削除した後に再度playbookを実行すると、サービス停止タスクでエラーが発生します（既にNginxが存在しないため）。
- タスクに `ignore_errors: yes` オプションを追加するとエラー発生時でも無視してplaybook実行を先に進めることができます。これを使って冪等性のあるplaybookにしてみましょう。

実行方法は以下の通りです。

```bash
$ ansible-playbook uninstall_nginx.yml
```

```
PLAY [Uninstall the nginx web service] ****************************************

TASK [Gathering Facts] ********************************************************
ok: [node1]
ok: [node2]
ok: [node3]

TASK [stop nginx] *************************************************************
changed: [node1]
changed: [node2]
changed: [node3]

TASK [uninstall nginx] ********************************************************
changed: [node1]
changed: [node2]
changed: [node3]

PLAY RECAP ********************************************************************
node1                      : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node2                      : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
node3                      : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

最終的なplaybook例は[こちら](./ex3_answer.md)

---

[前に戻る](./ex2.md) | [次へ進む](../basic-roles/ex4.md)
