# Ansible トレーニング環境構築

このドキュメントでは、Ansible ハンズオントレーニングに必要な環境を構築する手順を説明します。
Podman コンテナを使用して、コントローラーノードと複数のターゲットノードをローカル PC 上に構築します。

## アーキテクチャ

トレーニング環境は以下の構成です。受講者はホストPCからコントローラーコンテナにSSH接続し、コントローラー内からAnsibleを実行してターゲットノードを操作します。

```
[ホストPC] --SSH(localhost:2220)--> [controller 172.20.0.10] --172.20.0.x--> [node1-3, lb]
```

| コンテナ | IPアドレス | 役割 |
|---------|-----------|------|
| controller | 172.20.0.10 | Ansible実行環境（Ansible プリインストール済み） |
| node1 | 172.20.0.11 | Webサーバー |
| node2 | 172.20.0.12 | Webサーバー |
| node3 | 172.20.0.13 | Webサーバー |
| lb | 172.20.0.14 | ロードバランサー |

- コントローラーのSSHポートのみホストにマッピングされています（localhost:2220）
- ターゲットノード（node1-3, lb）にはコントローラーからコンテナネットワーク経由で直接アクセスします
- Ansible はコントローラーにプリインストールされているため、ホストPCへのインストールは不要です

## 前提条件

- Windows 10/11 または macOS (Intel/Apple Silicon)
- インターネット接続
- 最低 8GB RAM（Windows コンテナ使用時は 16GB 推奨）

---

## 1. Podman のインストール

### Windows の場合

PowerShell を管理者権限で開き、以下のコマンドを実行します。

```powershell
winget install RedHat.Podman
winget install RedHat.Podman-Desktop
```

次に、docker-compose をインストールします。

```powershell
New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\DockerCompose" | Out-Null
$url = "https://github.com/docker/compose/releases/latest/download/docker-compose-windows-x86_64.exe"
Invoke-WebRequest -Uri $url -OutFile "$env:LOCALAPPDATA\DockerCompose\docker-compose.exe"
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:LOCALAPPDATA\DockerCompose", "User")
```

PATH の変更を反映するため、PowerShell を一度閉じて再度開いてください。

```powershell
docker-compose version
```

インストール完了後、ターミナルを再起動してください。

### Mac の場合

```bash
$ brew install podman
$ brew install docker-compose
```

## 2. Podman Machine の初期化と起動

Podman Machine を初期化し、起動します。
初回のみ `init` が必要です。

```bash
$ podman machine init
Downloading VM image: fedora-coreos-41.20250101.2.0-qemu.aarch64.qcow2.xz
...
Extracting compressed file: fedora-coreos-41.20250101.2.0-qemu.aarch64.qcow2.xz
Image resized.
Machine init complete

$ podman machine start
Starting machine "podman-machine-default"
...
Machine "podman-machine-default" started successfully

$ podman machine list
NAME                     VM TYPE     CREATED        LAST UP            CPUS        MEMORY      DISK SIZE
podman-machine-default*  qemu        2 minutes ago  Currently running  2           2GiB        100GiB
```

## 3. トレーニング教材の取得

トレーニング教材を取得します。配布された方法に応じて、Git clone またはファイルのコピーを行ってください。

```bash
$ cd training/containers
$ ls
Dockerfile  docker-compose.yml  windows/
```

## 4. コンテナイメージのビルドと起動

`docker-compose` を使用して、コンテナイメージのビルドと起動を行います。
UBI 10 (ubi-init) ベースのイメージから、5 台のコンテナ（controller, node1, node2, node3, lb）を構築します。

```bash
$ docker-compose up -d --build
Building controller
STEP 1/10: FROM registry.access.redhat.com/ubi10/ubi-init:latest
Trying to pull registry.access.redhat.com/ubi10/ubi-init:latest...
Getting image source signatures
...
Building node1
...
Building node2
...
Building node3
...
Building lb
...
Creating container training_controller_1
Creating container training_node1_1
Creating container training_node2_1
Creating container training_node3_1
Creating container training_lb_1
```

コンテナが正しく起動しているか確認します。

```bash
$ podman ps
CONTAINER ID  IMAGE                                 COMMAND         CREATED         STATUS             PORTS                  NAMES
e5f6a7b8c9d0  localhost/training_controller:latest  /sbin/init      32 seconds ago  Up 31 seconds ago  0.0.0.0:2220->22/tcp   training_controller_1
a1b2c3d4e5f6  localhost/training_node1:latest       /sbin/init      30 seconds ago  Up 29 seconds ago                         training_node1_1
b2c3d4e5f6a7  localhost/training_node2:latest       /sbin/init      28 seconds ago  Up 27 seconds ago                         training_node2_1
c3d4e5f6a7b8  localhost/training_node3:latest       /sbin/init      26 seconds ago  Up 25 seconds ago                         training_node3_1
d4e5f6a7b8c9  localhost/training_lb:latest          /sbin/init      24 seconds ago  Up 23 seconds ago                         training_lb_1
```

5 台すべてのコンテナが `Up` 状態であることを確認してください。

## 5. SSH 接続テスト

### Step 1: ホストからコントローラーへの接続

まず、ホストPCからコントローラーコンテナにSSH接続できることを確認します。

| コンテナ | SSHポート |
|---------|----------|
| controller | localhost:2220 |

```bash
$ ssh -p 2220 root@localhost
The authenticity of host '[localhost]:2220 ([127.0.0.1]:2220)' can't be established.
ED25519 key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '[localhost]:2220' (ED25519) to the list of known hosts.
root@localhost's password:
[root@controller ~]#
```

- パスワードは `password` です。
- 初回接続時にホストキーの確認メッセージが表示されます。`yes` と入力してください。

### Step 2: コントローラーからターゲットノードへの接続

コントローラーにログインした状態で、ターゲットノードにSSH接続できることを確認します。

```bash
[root@controller ~]# ssh root@172.20.0.11
The authenticity of host '172.20.0.11 (172.20.0.11)' can't be established.
ED25519 key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '172.20.0.11' (ED25519) to the list of known hosts.
root@172.20.0.11's password:
[root@node1 ~]#
```

- パスワードは `password` です。
- 確認後、`exit` でnode1から抜け、コントローラーに戻ってください。

> **注意:** 以降のトレーニングで使用する Ansible コマンドは、すべてコントローラーコンテナの中で実行します。Ansible はコントローラーにプリインストール済みのため、ホストPCへのインストールは不要です。

## 6. 作業ディレクトリの準備

コントローラーコンテナには、ホスト側の `workspace/` ディレクトリが自動的にマウントされています。

| ホスト側 | コンテナ内 | 用途 |
|---|---|---|
| `basic-intro/workspace/` | `/root/basic-intro/` | 基礎演習 ex1-3 |
| `basic-roles/workspace/` | `/root/basic-roles/` | 基礎演習 ex4-6 |
| `advanced/workspace/` | `/root/advanced/` | 応用演習 |
| `homework/workspace/` | `/root/homework/` | 宿題 |

ホスト側のエディタ（VS Code 等）で `workspace/` 内のファイルを編集すると、コンテナ内にリアルタイムで反映されます。
SSH 接続後にコンテナ内で直接 vim 等で編集することも可能です。

> **注意:** 以降の手順はコントローラーコンテナ内（`ssh -p 2220 root@localhost` でログインした状態）で実行するか、ホスト側で `workspace/` ディレクトリにファイルを作成してください。

```bash
[root@controller ~]# cd ~/basic-intro
```

### ansible.cfg の作成

```bash
$ cat << 'EOF' > ansible.cfg
[defaults]
stdout_callback = ansible.builtin.default
host_key_checking = False
retry_files_enabled = False
inventory = ./inventory.yml
callback_result_format = yaml

[ssh_connection]
pipelining = True
EOF
```

### inventory.yml の作成

```bash
$ cat << 'EOF' > inventory.yml
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
EOF
```

## 7. Ansible 接続テスト

すべてのホストに対して `ping` モジュールで接続テストを行います。

```bash
$ ansible all -m ping
node1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
node2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
node3 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
lb | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

4 台すべてのホストが `SUCCESS` と表示されれば、環境構築は完了です。

## 8. [オプション] Windows コンテナのセットアップ

> **注意:** このセクションは Windows 11 ラップトップをお使いの方のみ対象です。

Windows ターゲットノードを追加する場合は、以下の手順で行います。
詳細は `containers/windows/README.md` を参照してください。

1. `docker-compose.yml` 内の `winnode` セクションのコメントアウトを解除します。
2. Windows コンテナを起動します。
   ```bash
   $ docker-compose up -d winnode
   ```
3. Windows のセットアップが完了するまで数分待ちます（初回は時間がかかります）。
4. `win_ping` モジュールで接続テストを行います。
   ```bash
   $ ansible winnode -m win_ping
   winnode | SUCCESS => {
       "changed": false,
       "ping": "pong"
   }
   ```

## 9. 環境の停止と再開

> **注意:** 環境の停止・再開はホストPC上で実行します。コントローラーコンテナからは `exit` で抜けてから実行してください。

### 環境の停止

トレーニング終了時やPC をシャットダウンする前に、コンテナを停止します。

```bash
$ cd training/containers
$ podman compose down
Stopping training_controller_1 ... done
Stopping training_node1_1      ... done
Stopping training_node2_1      ... done
Stopping training_node3_1      ... done
Stopping training_lb_1         ... done
Removing training_controller_1 ... done
Removing training_node1_1      ... done
Removing training_node2_1      ... done
Removing training_node3_1      ... done
Removing training_lb_1         ... done
```

### 環境の再開

次回のトレーニング時にコンテナを再起動します。

```bash
$ cd training/containers
$ podman compose up -d
Creating container training_controller_1
Creating container training_node1_1
Creating container training_node2_1
Creating container training_node3_1
Creating container training_lb_1
```

> **注意:** 再開後はコントローラーにSSH接続（`ssh -p 2220 root@localhost`）し、作業ディレクトリに移動してから `ansible all -m ping` で接続確認を行い、トレーニングを再開してください。

---

## トラブルシューティング

### Podman Machine が起動しない

**Windows の場合:**
- WSL2 が有効になっているか確認してください。
  ```powershell
  PS> wsl --status
  ```
- WSL2 が無効の場合は、以下のコマンドで有効化してください。
  ```powershell
  PS> wsl --install
  ```
- PC を再起動後、再度 `podman machine start` を実行してください。

**Mac の場合:**
- Homebrew が最新であることを確認してください。
  ```bash
  $ brew update && brew upgrade podman
  ```
- それでも起動しない場合は、既存の Machine を削除して再作成してください。
  ```bash
  $ podman machine rm
  $ podman machine init
  $ podman machine start
  ```

### コントローラーに SSH できない

1. Podman Machine が起動しているか確認してください。
   ```bash
   $ podman machine list
   ```
2. コンテナが Running 状態であることを確認してください。
   ```bash
   $ podman compose ps
   ```
3. コントローラーのポートマッピングが正しく設定されているか確認してください。
   ```bash
   $ podman compose ps
   ```
   controller コンテナの PORTS 列に `0.0.0.0:2220->22/tcp` のマッピングが表示されていることを確認してください。

### コントローラーからターゲットノードに SSH できない

1. コントローラーコンテナ内からターゲットノードへの疎通を確認してください。
   ```bash
   [root@controller ~]# ping -c 1 172.20.0.11
   ```
2. ターゲットノードのコンテナが Running 状態であることをホストPCから確認してください。
   ```bash
   $ podman compose ps
   ```

### UBI 10 のパッケージインストールエラー

- `registry.access.redhat.com` への接続を確認してください。
  ```bash
  $ curl -s https://registry.access.redhat.com/v2/ | head
  ```
- プロキシ環境の場合は、Podman にプロキシ設定を追加してください。
  ```bash
  $ podman machine ssh
  $ sudo vi /etc/systemd/system/podman.service.d/proxy.conf
  [Service]
  Environment="HTTP_PROXY=http://proxy.example.com:8080"
  Environment="HTTPS_PROXY=http://proxy.example.com:8080"
  Environment="NO_PROXY=localhost,127.0.0.1"
  ```

### Ansible コマンドが見つからない

コントローラーコンテナ内で `ansible` コマンドが見つからない場合は、コントローラーコンテナが正しくビルドされているか確認してください。

```bash
[root@controller ~]# which ansible
/usr/bin/ansible
```

上記のようにパスが表示されれば正常です。表示されない場合は、コンテナイメージを再ビルドしてください。

```bash
$ cd training/containers
$ podman compose down
$ podman compose up -d --build
```
