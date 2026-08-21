# Airgap Ansible 研修環境 アーキテクチャ設計書

| 項目 | 内容 |
|------|------|
| プロジェクト名 | Airgap 環境対応 Ansible 研修環境 |
| 対象OS | RHEL 10, Windows 11 |
| 最終更新 | 2026-08-18 |

---

## 目次

1. [システム概要](#1-システム概要)
2. [全体アーキテクチャ図](#2-全体アーキテクチャ図)
3. [コンポーネント構成](#3-コンポーネント構成)
4. [ネットワークアーキテクチャ](#4-ネットワークアーキテクチャ)
5. [データフロー](#5-データフロー)
6. [セキュリティ設計](#6-セキュリティ設計)
7. [デプロイメントシーケンス](#7-デプロイメントシーケンス)
8. [変数・設定一覧](#8-変数設定一覧)
9. [ディレクトリ構成詳細](#9-ディレクトリ構成詳細)

---

## 1. システム概要

本システムは、インターネット接続のないエアギャップ（Air-Gapped）環境において Ansible 研修を実施するための完全自己完結型ツールキットである。

### 1.1 設計思想

- **完全オフライン動作**: ランタイムで外部ネットワークへの依存を一切持たない
- **ワンコマンドデプロイ**: Ansible Playbook 一回の実行で研修環境全体を構築する
- **マルチOS対応**: RHEL 10（podman ネイティブ）と Windows 11（WSL2 + Podman）の双方をサポートする
- **再現性**: チェックサム検証とコンテナイメージの事前ビルドにより、環境差異を排除する
- **KVM 検証環境**: libvirt の隔離ネットワークを用いてエアギャップ環境を忠実に再現できる

### 1.2 動作フロー概略

```
[オンライン準備] --> [物理メディア転送] --> [エアギャップ環境デプロイ] --> [研修実施]
```

1. インターネット接続のある RHEL 10 マシンで `prepare-offline-bundle.sh` を実行し、全リソースを収集する
2. 生成された `airgap/` ディレクトリを USB ドライブ等でエアギャップ環境に持ち込む
3. Ansible Playbook を実行し、ターゲットマシン上にコンテナ化された研修環境を構築する
4. 受講者は SSH 経由でコントローラコンテナに接続し、Ansible 演習を行う

---

## 2. 全体アーキテクチャ図

### 2.1 システム全体構成

```
+===================================================================+
|                     オンライン準備環境                               |
|                   (RHEL 10 / CentOS 10)                           |
|                                                                   |
|  +-------------------------------------------------------------+ |
|  |  prepare-offline-bundle.sh                                   | |
|  |                                                               | |
|  |  Phase 1: コンテナイメージビルド・保存                          | |
|  |    podman build --> podman save --> .tar                      | |
|  |                                                               | |
|  |  Phase 2: RPM パッケージダウンロード                            | |
|  |    dnf download --resolve --> .rpm                            | |
|  |                                                               | |
|  |  Phase 3: スタンドアロンバイナリダウンロード                      | |
|  |    curl --> docker-compose, sshpass, podman-setup.exe         | |
|  |                                                               | |
|  |  Phase 4: pip パッケージダウンロード                             | |
|  |    pip download --> .whl                                      | |
|  |                                                               | |
|  |  Phase 5: Ansible コレクションダウンロード                       | |
|  |    ansible-galaxy collection download --> .tar.gz             | |
|  |                                                               | |
|  |  Phase 6: 研修資材アーカイブ                                    | |
|  |    git archive / tar --> .tar.gz                              | |
|  |                                                               | |
|  |  Phase 7: チェックサム生成                                      | |
|  |    sha256sum --> checksums.sha256                             | |
|  +-------------------------------------------------------------+ |
|                          |                                        |
|                   offline-resources/                              |
+==========================|========================================+
                           |
                    USB / ISO メディア
                           |
+==========================================================================+
|                        エアギャップ環境                                     |
|                                                                          |
|  +-------------------------------------------------------------------+  |
|  |  KVM ホスト (192.168.100.1)       隔離ネットワーク: airgap-training |  |
|  |  virbr-airgap (192.168.100.0/24)  forward なし = 完全隔離           |  |
|  |                                                                    |  |
|  |  Ansible Controller (KVM ホスト自身 または別マシン)                   |  |
|  |    |                                                               |  |
|  |    |--- SSH (192.168.100.10) ---+                                  |  |
|  |    |                            |                                  |  |
|  |    |                   +--------v---------------------------------+|  |
|  |    |                   | RHEL 10 VM (192.168.100.10)              ||  |
|  |    |                   |   podman + docker-compose                ||  |
|  |    |                   |                                          ||  |
|  |    |                   |   +-- ansible_net (172.20.0.0/24) -----+ ||  |
|  |    |                   |   |                                    | ||  |
|  |    |                   |   |  controller  172.20.0.10 :2220/SSH | ||  |
|  |    |                   |   |  node1       172.20.0.11           | ||  |
|  |    |                   |   |  node2       172.20.0.12           | ||  |
|  |    |                   |   |  node3       172.20.0.13           | ||  |
|  |    |                   |   |  lb          172.20.0.14           | ||  |
|  |    |                   |   |  (winnode    172.20.0.20)          | ||  |
|  |    |                   |   +------------------------------------+ ||  |
|  |    |                   +------------------------------------------+|  |
|  |    |                                                               |  |
|  |    |--- WinRM (192.168.100.20) --+                                 |  |
|  |    |                             |                                 |  |
|  |    |                   +---------v--------------------------------+|  |
|  |    |                   | Windows 11 VM (192.168.100.20)           ||  |
|  |    |                   |   WSL2 + Podman + docker-compose         ||  |
|  |    |                   |                                          ||  |
|  |    |                   |   +-- ansible_net (172.20.0.0/24) -----+ ||  |
|  |    |                   |   |                                    | ||  |
|  |    |                   |   |  controller  172.20.0.10 :2220/SSH | ||  |
|  |    |                   |   |  node1       172.20.0.11           | ||  |
|  |    |                   |   |  node2       172.20.0.12           | ||  |
|  |    |                   |   |  node3       172.20.0.13           | ||  |
|  |    |                   |   |  lb          172.20.0.14           | ||  |
|  |    |                   |   +------------------------------------+ ||  |
|  |    |                   +------------------------------------------+|  |
|  +-------------------------------------------------------------------+  |
+==========================================================================+
```

### 2.2 研修受講者の接続経路

```
受講者 PC
    |
    | ssh -p 2220 root@<ターゲットIP>
    | パスワード: password
    |
    v
+-------------------+
| controller        |        ansible_net (172.20.0.0/24)
| 172.20.0.10       |---------------------------------------------+
| Ansible 実行環境  |        |          |          |              |
+-------------------+   +---------+ +---------+ +---------+ +---------+
                        | node1   | | node2   | | node3   | | lb      |
                        | .0.11   | | .0.12   | | .0.13   | | .0.14   |
                        | Web     | | Web     | | Web     | | LB      |
                        +---------+ +---------+ +---------+ +---------+
```

---

## 3. コンポーネント構成

### 3.1 prepare-offline-bundle.sh の処理フロー

```
prepare-offline-bundle.sh
    |
    +-- check_prerequisites()
    |       podman, python3, git, curl の存在確認
    |       pip が無ければ ensurepip で自動インストール
    |
    +-- create_directories()
    |       offline-resources/ 配下のディレクトリ構造を作成
    |
    +-- build_and_save_images()         [Phase 1]
    |       podman build: training-controller, training-linux-node
    |       podman save: .tar ファイルとして保存
    |       (オプション) dockurr/windows イメージの pull & save
    |
    +-- download_rpm_packages()         [Phase 2]
    |       dnf download --resolve: podman + 全依存パッケージ
    |       dnf download --resolve: createrepo_c + 依存
    |
    +-- download_binaries()             [Phase 3]
    |       docker-compose (Linux x86_64) v2.36.1
    |       docker-compose (Windows x86_64)
    |       sshpass 1.10 ソース
    |       Podman Windows インストーラ v5.5.0
    |
    +-- download_pip_packages()         [Phase 4]
    |       ansible, pywinrm, jmespath, ansible-lint + 全依存
    |
    +-- download_ansible_collections()  [Phase 5]
    |       ansible.windows, community.windows
    |       ansible.posix, community.general
    |
    +-- archive_training_materials()    [Phase 6]
    |       git archive または tar で研修資材をアーカイブ
    |
    +-- generate_checksums()            [Phase 7]
    |       全ファイルの SHA256 チェックサムを生成
    |
    +-- print_summary()
            バンドルサイズと次のステップを表示
```

### 3.2 Ansible Playbook 実行フロー

```
site.yml (マスター Playbook)
    |
    +-- rhel-setup.yml (hosts: rhel)
    |       |
    |       +-- pre_tasks: OS が RedHat 系であることを確認
    |       |
    |       +-- role: common
    |       |       バンドルステージングディレクトリの作成
    |       |       checksums.sha256 による整合性検証
    |       |
    |       +-- role: rhel_podman
    |       |       podman インストール状況の確認
    |       |       createrepo_c のインストール (RPM直接)
    |       |       ローカル yum リポジトリの構築・設定
    |       |       podman のローカルリポジトリからのインストール
    |       |       podman.socket の有効化
    |       |       docker-compose バイナリの配置 (/usr/local/bin/)
    |       |
    |       +-- role: rhel_training
    |       |       研修資材アーカイブの展開
    |       |       コンテナイメージのロード (podman load)
    |       |       docker-compose.yml の Jinja2 テンプレート展開
    |       |       workspace ディレクトリの作成
    |       |       docker-compose up -d による全コンテナ起動
    |       |       SSH ポート (2220) の待機確認
    |       |       コントローラ内の ansible バージョン確認
    |       |
    |       +-- post_tasks: セットアップ完了メッセージの表示
    |
    +-- windows-setup.yml (hosts: windows)
            |
            +-- pre_tasks: OS が Windows であることを確認
            |
            +-- role: win_podman
            |       WSL オプション機能の有効化
            |       仮想マシンプラットフォームの有効化
            |       必要に応じた再起動
            |       WSL デフォルトバージョンを 2 に設定
            |       Podman インストーラの実行 (/quiet /norestart)
            |       docker-compose.exe の配置と PATH 追加
            |       podman machine の初期化・起動
            |
            +-- role: win_training
                    研修資材アーカイブの展開
                    コンテナイメージのロード
                    docker-compose.yml の配置
                    workspace ディレクトリの作成
                    docker-compose up -d
                    SSH ポート (2220) の待機確認
```

### 3.3 ロール依存関係

```
+----------+       +-------------+       +--------------+
|  common  | ----> | rhel_podman | ----> | rhel_training|
+----------+       +-------------+       +--------------+
  チェックサム         podman               イメージロード
  検証                docker-compose       コンテナ起動
                      配置

+------------+       +--------------+
| win_podman | ----> | win_training |
+------------+       +--------------+
  WSL2 有効化           イメージロード
  Podman install       コンテナ起動
  docker-compose
```

注: Windows 向け Playbook では `common` ロールは使用していない。これは Windows 環境でのチェックサム検証コマンド (`sha256sum`) が標準で利用できないためである。

### 3.4 コンテナ構成

| コンテナ名 | イメージ | IP アドレス | ポート | 役割 |
|-----------|---------|------------|--------|------|
| controller | training-controller:latest | 172.20.0.10 | 2220:22 (SSH) | Ansible 実行環境 |
| node1 | training-linux-node:latest | 172.20.0.11 | - | Web サーバ (演習対象) |
| node2 | training-linux-node:latest | 172.20.0.12 | - | Web サーバ (演習対象) |
| node3 | training-linux-node:latest | 172.20.0.13 | - | Web サーバ (演習対象) |
| lb | training-linux-node:latest | 172.20.0.14 | - | ロードバランサ (演習対象) |
| winnode (オプション) | dockurr/windows:latest | 172.20.0.20 | 8006, 13389, 5985, 5986 | Windows 演習対象 |

#### controller コンテナのボリュームマウント

```
ホスト (ターゲットVM)                        コンテナ内
training_dir/basic-intro/workspace  --> /root/basic-intro
training_dir/basic-roles/workspace  --> /root/basic-roles
training_dir/advanced/workspace     --> /root/advanced
training_dir/homework/workspace     --> /root/homework
```

---

## 4. ネットワークアーキテクチャ

### 4.1 ネットワーク階層

本システムは3層のネットワークを使用する。

```
+================================================================+
|  Layer 1: KVM 隔離ネットワーク (airgap-training)                 |
|  192.168.100.0/24                                              |
|  virbr-airgap ブリッジ                                          |
|  forward なし = インターネット接続完全不可                         |
|                                                                |
|    +----------------------------------------------------------+|
|    | Layer 2: VM 内部ネットワーク (ターゲットOS)                  ||
|    |                                                          ||
|    |   +----------------------------------------------------+ ||
|    |   | Layer 3: コンテナネットワーク (ansible_net)            | ||
|    |   | 172.20.0.0/24                                      | ||
|    |   | bridge ドライバ                                     | ||
|    |   |                                                    | ||
|    |   | controller(.10) -- node1(.11)  -- node2(.12)       | ||
|    |   |                 -- node3(.13)  -- lb(.14)          | ||
|    |   |                 -- winnode(.20) [オプション]         | ||
|    |   +----------------------------------------------------+ ||
|    +----------------------------------------------------------+||
+================================================================+
```

### 4.2 KVM airgap-training ネットワーク

```xml
<network>
  <name>airgap-training</name>
  <bridge name="virbr-airgap"/>
  <!-- forward 要素なし = 完全隔離 -->
  <ip address="192.168.100.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.100.10" end="192.168.100.50"/>
      <host mac="52:54:00:AA:BB:10" name="rhel-target"        ip="192.168.100.10"/>
      <host mac="52:54:00:AA:BB:20" name="win-target"         ip="192.168.100.20"/>
      <host mac="52:54:00:AA:BB:01" name="ansible-controller" ip="192.168.100.1"/>
    </dhcp>
  </ip>
</network>
```

**設計上のポイント:**

- `<forward>` 要素を意図的に省略することで、NAT/ルーティングを無効化している
- VM はこのネットワーク上のホスト同士でのみ通信可能であり、外部への経路は存在しない
- DHCP による固定 IP 割り当て（MAC アドレスベース）を使用し、手動設定の手間を削減している
- DHCP レンジは `.10` - `.50` の 41 アドレスを確保しており、テスト用に追加 VM を接続可能である

### 4.3 コンテナネットワーク (ansible_net)

```
ドライバ:   bridge
サブネット:  172.20.0.0/24
IPAM:       固定 IP 割り当て (docker-compose.yml 内で指定)
```

**ポートフォワーディング:**

| ホスト側ポート | コンテナ | コンテナ側ポート | プロトコル | 用途 |
|--------------|---------|----------------|-----------|------|
| 2220 | controller | 22 | TCP | SSH (研修受講者接続用) |
| 8006 | winnode | 8006 | TCP | noVNC (Windows コンソール) |
| 13389 | winnode | 3389 | TCP/UDP | RDP (Windows リモートデスクトップ) |
| 5985 | winnode | 5985 | TCP | WinRM HTTP |
| 5986 | winnode | 5986 | TCP | WinRM HTTPS |

### 4.4 通信マトリクス

```
                   KVM ホスト  RHEL VM    Win VM    controller  node1-3,lb
KVM ホスト          -          SSH        WinRM     -           -
RHEL VM            応答       -          -         podman      podman
Win VM             応答       -          -         podman      podman
controller         -          -          -         -           SSH
node1-3,lb         -          -          -         SSH応答      相互SSH
外部ネットワーク     不可        不可        不可       不可         不可
```

---

## 5. データフロー

### 5.1 オンラインビルドからエアギャップデプロイまでの全体フロー

```
Phase A: オンライン準備
=======================

   インターネット
       |
       v
+------------------+     +------------------+     +------------------+
| コンテナレジストリ  | --> | podman build     | --> | podman save      |
| (Containerfile)  |     | (イメージ構築)     |     | (.tar 保存)      |
+------------------+     +------------------+     +------------------+
                                                         |
   インターネット                                          |
       |                                                  |
       v                                                  v
+------------------+     +------------------+     +------------------+
| RHEL リポジトリ    | --> | dnf download     | --> | offline-resources|
| PyPI             |     | pip download     |     |  /               |
| GitHub Releases  |     | curl             |     |  container-images|
| Ansible Galaxy   |     | galaxy download  |     |  rpm-packages    |
+------------------+     +------------------+     |  pip-packages    |
                                                  |  binaries        |
                                                  |  ansible-        |
                                                  |   collections    |
                                                  |  training-       |
                                                  |   materials      |
                                                  +------------------+
                                                         |
                                                  sha256sum -c 生成
                                                         |
                                                  checksums.sha256


Phase B: 物理転送
=================

offline-resources/ + playbooks/ + inventory/ + ...
         |
         | USB ドライブ / ISO イメージ
         v
  エアギャップ環境に持ち込み


Phase C: エアギャップデプロイ (RHEL)
====================================

+------------------+     +------------------+     +------------------+
| ISO マウント /    | --> | /opt/airgap-     | --> | sha256sum -c     |
| USB コピー        |     | bundle/          |     | (整合性検証)      |
+------------------+     +------------------+     +------------------+
                                |
                                v
+------------------+     +------------------+     +------------------+
| createrepo_c     | --> | dnf install      | --> | podman           |
| (RPM直接install) |     | podman           |     | (インストール完了) |
+------------------+     | (ローカルrepo)    |     +------------------+
                         +------------------+            |
                                                         v
+------------------+     +------------------+     +------------------+
| docker-compose   | --> | podman load      | --> | docker-compose   |
| バイナリ配置      |     | (イメージロード)   |     | up -d            |
+------------------+     +------------------+     +------------------+
                                                         |
                                                         v
                                                  研修コンテナ起動
                                                  (5台: controller,
                                                   node1-3, lb)
```

### 5.2 コンテナイメージのライフサイクル

```
[オンライン環境]                    [物理転送]           [エアギャップ環境]
                                     
Containerfile                                           
    |                                                   
    v                                                   
podman build                                            
    |                                                   
    v                                                   
ローカルイメージ                                          
(training-controller:latest)                            
(training-linux-node:latest)                            
    |                                                   
    v                                                   
podman save -o .tar         USB/ISO             podman load -i .tar
    |                    ------------->              |
    v                                               v
.tar ファイル                                   ローカルイメージ
(training-controller.tar)                      (training-controller:latest)
(training-linux-node.tar)                      (training-linux-node:latest)
                                                    |
                                                    v
                                               docker-compose up -d
                                                    |
                                                    v
                                               コンテナ起動
                                               (controller, node1-3, lb)
```

### 5.3 RPM パッケージのデプロイフロー (RHEL)

```
[エアギャップ環境 RHEL 10 VM 内]

/opt/airgap-bundle/
    |
    +-- rpm-packages/
    |       +-- createrepo/       <-- createrepo_c の RPM
    |       +-- podman/           <-- podman + 全依存 RPM
    |
    v
1. rpm -ivh createrepo_c*.rpm     (直接インストール、依存なし想定)
    |
    v
2. createrepo_c /opt/airgap-bundle/rpm-packages/podman/
    |                              (yum リポジトリメタデータ生成)
    v
3. /etc/yum.repos.d/airgap-local.repo 作成
    |   [airgap-podman]
    |   baseurl=file:///opt/airgap-bundle/rpm-packages/podman/
    |   gpgcheck=0
    v
4. dnf install podman --disablerepo='*' --enablerepo=airgap-podman
    |
    v
5. podman 利用可能
```

---

## 6. セキュリティ設計

### 6.1 ネットワーク隔離

| 層 | 隔離メカニズム | 説明 |
|----|-------------|------|
| KVM ネットワーク | forward 要素なし | VM から外部への経路が物理的に存在しない |
| コンテナネットワーク | bridge (内部) | コンテナ間のみ通信可能。ホストの外部 NIC には接続しない |
| ポートフォワーディング | 最小限公開 | SSH (2220) のみがホスト上で公開される |

### 6.2 整合性検証

- `prepare-offline-bundle.sh` の Phase 7 で全ファイルの SHA256 チェックサムを生成する
- デプロイ時に `common` ロールが `sha256sum -c checksums.sha256` で整合性を検証する
- 転送中の破損や改ざんを検出できる

```
[生成] prepare-offline-bundle.sh
        find . -type f ! -name 'checksums.sha256' -exec sha256sum {} \;
            > checksums.sha256

[検証] common ロール (RHEL デプロイ時)
        sha256sum -c checksums.sha256
```

### 6.3 ランタイム外部依存の排除

本システムはデプロイ時に以下の外部リソースを一切参照しない。

| リソース種別 | オフライン対応方法 |
|------------|-----------------|
| コンテナイメージ | `podman save/load` で tar ファイル経由 |
| RPM パッケージ | `dnf download --resolve` で全依存を事前取得 |
| pip パッケージ | `pip download` で wheel を事前取得 |
| Ansible コレクション | `ansible-galaxy collection download` で事前取得 |
| docker-compose | スタンドアロンバイナリを直接配置 |
| sshpass | ソースアーカイブを同梱 |

### 6.4 認証情報

| 項目 | 値 | 用途 | リスク評価 |
|------|-----|------|----------|
| controller SSH | root / password | 研修受講者ログイン | 研修環境限定・隔離ネットワーク内 |
| Windows WinRM | ansible / AnsiblePass123! | Ansible 接続 | 隔離ネットワーク内・Basic認証 |
| WinRM 暗号化 | 無効 (AllowUnencrypted) | 隔離環境のため許容 | エアギャップ内のみ使用 |

**注意**: これらの認証情報はエアギャップの隔離ネットワーク内でのみ使用される前提で設計されている。外部ネットワークに接続された環境での使用は想定しておらず、推奨しない。

### 6.5 特権コンテナ

全研修コンテナは `privileged: true` で実行される。これは以下の理由による。

- controller コンテナ内で systemd ベースのサービス管理演習を行うため
- node コンテナ内で SSH デーモンを稼働させるため
- 研修目的の一時的な環境であり、永続的な本番運用は想定していない

---

## 7. デプロイメントシーケンス

### 7.1 RHEL 10 デプロイシーケンス

```
Ansible          common          rhel_podman         rhel_training
Controller       ロール           ロール               ロール
   |                |                |                    |
   |-- gather_facts -->              |                    |
   |<-- facts ------                 |                    |
   |                                 |                    |
   |-- assert: RedHat系 -->          |                    |
   |                                 |                    |
   |== common ロール開始 ============|                    |
   |                |                |                    |
   |  bundle_staging_dir 作成        |                    |
   |  checksums.sha256 存在確認      |                    |
   |  sha256sum -c 検証              |                    |
   |  検証結果表示                    |                    |
   |                |                |                    |
   |== rhel_podman ロール開始 =======|==                  |
   |                                 |                    |
   |                podman --version 確認                  |
   |                (未インストールの場合:)                  |
   |                  createrepo_c RPM インストール         |
   |                  createrepo_c 実行 (メタデータ生成)     |
   |                  airgap-local.repo 配置               |
   |                  dnf install podman (ローカルrepo)     |
   |                podman.socket 有効化・起動              |
   |                docker-compose バイナリ配置             |
   |                                 |                    |
   |== rhel_training ロール開始 =====|====================|==
   |                                                      |
   |                                 研修ディレクトリ作成    |
   |                                 アーカイブ展開         |
   |                                 controller イメージ load|
   |                                 node イメージ load     |
   |                                 (Windows イメージ load)|
   |                                 compose.yml テンプレート|
   |                                 workspace 作成        |
   |                                 docker-compose up -d  |
   |                                 SSH ポート 2220 待機   |
   |                                 コンテナ状態確認       |
   |                                 ansible バージョン確認 |
   |                                                      |
   |<- セットアップ完了メッセージ -----------------------------|
   |
```

### 7.2 Windows 11 デプロイシーケンス

```
Ansible          win_podman          win_training
Controller       ロール               ロール
   |                |                    |
   |-- gather_facts -->                  |
   |<-- facts ------                     |
   |                                     |
   |-- assert: Windows -->               |
   |                                     |
   |== win_podman ロール開始 ============|
   |                |                    |
   |  bundle_dir 作成                    |
   |  WSL 機能有効化                     |
   |  仮想マシンプラットフォーム有効化      |
   |  (再起動: WSL/VMP 有効化後)          |
   |  WSL バージョン 2 設定               |
   |  Podman インストーラ実行             |
   |  (再起動: 必要な場合)                |
   |  docker-compose.exe 配置            |
   |  PATH 追加                          |
   |  podman machine init                |
   |  podman machine start               |
   |                |                    |
   |== win_training ロール開始 ==========|==
   |                                     |
   |                研修ディレクトリ作成    |
   |                アーカイブ展開         |
   |                controller イメージ load|
   |                node イメージ load     |
   |                compose.yml 配置      |
   |                workspace 作成        |
   |                docker-compose up -d  |
   |                SSH ポート 2220 待機   |
   |                コンテナ状態確認       |
   |                                     |
   |<- セットアップ完了メッセージ ----------|
   |
```

### 7.3 検証 Playbook (verify.yml) シーケンス

```
[RHEL 検証]
    1. podman --version             --> podman が動作していること
    2. podman ps --format json      --> JSON 形式でコンテナ一覧取得
    3. assert: コンテナ数 >= 5       --> 5台全て起動していること
    4. wait_for: localhost:2220     --> SSH ポートが応答すること
    5. podman exec controller       --> コントローラからノードへの
       ssh root@172.20.0.{11-14}       SSH 疎通確認 (4台)
    6. 検証完了メッセージ

[Windows 検証]
    1. podman --version             --> podman が動作していること
    2. podman ps                    --> コンテナ一覧表示
    3. wait_for: localhost:2220     --> SSH ポートが応答すること
    4. 検証完了メッセージ
```

---

## 8. 変数・設定一覧

### 8.1 共通変数 (group_vars/all.yml)

| 変数名 | デフォルト値 | 説明 |
|--------|------------|------|
| `bundle_staging_dir` | `/opt/airgap-bundle` | バンドル配置先ディレクトリ |
| `training_base_dir` | `/opt/training` | 研修資材展開先の親ディレクトリ |
| `training_dir` | `/opt/training/ansible_training_2026` | 研修資材ディレクトリ |
| `controller_image` | `training-controller:latest` | コントローラコンテナイメージ |
| `node_image` | `training-linux-node:latest` | ノードコンテナイメージ |
| `windows_image` | `dockurr/windows:latest` | Windows コンテナイメージ |
| `enable_windows` | `false` | Windows コンテナの有効/無効 |
| `container_network_subnet` | `172.20.0.0/24` | コンテナネットワークサブネット |
| `controller_ip` | `172.20.0.10` | コントローラの固定 IP |
| `controller_ssh_port` | `2220` | コントローラ SSH ポート (ホスト側) |

### 8.2 RHEL 固有変数 (group_vars/rhel.yml)

| 変数名 | デフォルト値 | 説明 |
|--------|------------|------|
| `ansible_user` | `root` | SSH 接続ユーザ |
| `ansible_become` | `true` | 特権昇格の有効化 |
| `podman_rpm_dir` | `{{ bundle_staging_dir }}/rpm-packages/podman` | podman RPM 格納パス |
| `createrepo_rpm_dir` | `{{ bundle_staging_dir }}/rpm-packages/createrepo` | createrepo RPM 格納パス |
| `docker_compose_binary` | `{{ bundle_staging_dir }}/binaries/docker-compose-linux-x86_64` | docker-compose バイナリパス |
| `container_images_dir` | `{{ bundle_staging_dir }}/container-images` | コンテナイメージ格納パス |
| `training_archive` | `{{ bundle_staging_dir }}/training-materials/ansible_training_2026.tar.gz` | 研修資材アーカイブパス |

### 8.3 Windows 固有変数 (group_vars/windows.yml)

| 変数名 | デフォルト値 | 説明 |
|--------|------------|------|
| `ansible_user` | `ansible` | WinRM 接続ユーザ |
| `ansible_password` | `AnsiblePass123!` | WinRM 接続パスワード |
| `ansible_connection` | `winrm` | 接続方式 |
| `ansible_winrm_transport` | `basic` | WinRM 認証方式 |
| `ansible_port` | `5985` | WinRM ポート (HTTP) |
| `win_bundle_dir` | `C:\airgap-bundle` | バンドル配置先 |
| `win_training_dir` | `C:\training` | 研修資材展開先 |
| `win_compose_dir` | `C:\training\ansible_training_2026\containers` | docker-compose 実行ディレクトリ |
| `win_podman_installer` | `{{ win_bundle_dir }}\podman-setup.exe` | Podman インストーラパス |
| `win_compose_binary` | `{{ win_bundle_dir }}\docker-compose-windows-x86_64.exe` | docker-compose バイナリパス |
| `win_compose_install_dir` | `C:\ProgramData\DockerCompose` | docker-compose インストール先 |

### 8.4 環境変数 (prepare-offline-bundle.sh)

| 変数名 | デフォルト値 | 説明 |
|--------|------------|------|
| `COMPOSE_VERSION` | `v2.36.1` | docker-compose バージョン |
| `PODMAN_WIN_VERSION` | `5.5.0` | Podman Windows インストーラバージョン |
| `SKIP_WINDOWS` | `false` | Windows 関連リソースのスキップ |

### 8.5 Ansible 設定 (ansible.cfg)

| セクション | 設定 | 値 | 説明 |
|-----------|------|-----|------|
| defaults | host_key_checking | False | SSH ホストキー確認を無効化 |
| defaults | timeout | 60 | 接続タイムアウト (秒) |
| defaults | forks | 10 | 並列実行数 |
| defaults | interpreter_python | auto_silent | Python インタプリタ自動検出 |
| privilege_escalation | become | True | デフォルトで sudo を使用 |
| ssh_connection | pipelining | True | SSH パイプライニング有効化 |
| ssh_connection | ssh_args | ControlMaster=auto, ControlPersist=60s | SSH 多重化 |

---

## 9. ディレクトリ構成詳細

```
airgap/
|
+-- README.md                                  本プロジェクトの概要と使用手順
+-- prepare-offline-bundle.sh                  オフラインバンドル作成スクリプト (7フェーズ)
+-- ansible.cfg                                Ansible 設定ファイル
|
+-- docs/                                      ドキュメント
|   +-- architecture.md                        本アーキテクチャ設計書
|   +-- operations-guide.md                    運用手順書
|
+-- inventory/                                 インベントリ (ターゲットホスト定義)
|   +-- rhel-hosts.yml                         RHEL ターゲット (192.168.100.10)
|   +-- windows-hosts.yml                      Windows ターゲット (192.168.100.20)
|
+-- group_vars/                                グループ変数
|   +-- all.yml                                全OS共通変数
|   +-- rhel.yml                               RHEL 固有変数
|   +-- windows.yml                            Windows 固有変数
|
+-- playbooks/                                 Playbook 群
|   +-- site.yml                               マスター Playbook (全OS統合)
|   +-- rhel-setup.yml                         RHEL 10 セットアップ
|   +-- windows-setup.yml                      Windows 11 セットアップ
|   +-- verify.yml                             デプロイ後検証
|   |
|   +-- roles/                                 ロール群
|       +-- common/                            共通ロール (チェックサム検証)
|       |   +-- tasks/main.yml
|       |   +-- vars/main.yml
|       |
|       +-- rhel_podman/                       RHEL: podman + docker-compose セットアップ
|       |   +-- tasks/main.yml
|       |   +-- handlers/main.yml              podman 再起動ハンドラ
|       |   +-- vars/main.yml
|       |
|       +-- rhel_training/                     RHEL: イメージロード・コンテナ起動
|       |   +-- tasks/main.yml
|       |   +-- handlers/main.yml              コンテナ再起動ハンドラ
|       |   +-- templates/
|       |   |   +-- docker-compose-airgap.yml.j2
|       |   +-- vars/main.yml
|       |
|       +-- win_podman/                        Windows: WSL2 + Podman セットアップ
|       |   +-- tasks/main.yml
|       |   +-- vars/main.yml
|       |
|       +-- win_training/                      Windows: イメージロード・コンテナ起動
|           +-- tasks/main.yml
|           +-- templates/
|           |   +-- docker-compose-airgap.yml.j2
|           +-- vars/main.yml
|
+-- templates/                                 スタンドアロンテンプレート
|   +-- docker-compose-airgap.yml.j2           Airgap 版 compose テンプレート (参照用)
|   +-- enable-winrm.ps1                       WinRM 有効化スクリプト (Windows 事前準備)
|
+-- offline-resources/                         オフラインリソース (自動生成)
|   +-- checksums.sha256                       全ファイルの SHA256 チェックサム
|   +-- container-images/
|   |   +-- training-controller.tar            コントローライメージ
|   |   +-- training-linux-node.tar            Linux ノードイメージ
|   |   +-- (dockurr-windows.tar)              Windows イメージ (オプション)
|   +-- rpm-packages/
|   |   +-- podman/                            podman + 依存 RPM 群
|   |   +-- createrepo/                        createrepo_c RPM 群
|   +-- pip-packages/                          Python パッケージ (.whl)
|   |   +-- ansible-14.3.1-py3-none-any.whl
|   |   +-- pywinrm-0.5.0-py3-none-any.whl
|   |   +-- jmespath-1.1.0-py3-none-any.whl
|   |   +-- ansible_lint-26.8.0-py3-none-any.whl
|   |   +-- ... (その他依存パッケージ)
|   +-- binaries/
|   |   +-- docker-compose-linux-x86_64        docker-compose (Linux)
|   |   +-- (docker-compose-windows-x86_64.exe) docker-compose (Windows)
|   |   +-- sshpass-1.10.tar.gz                sshpass ソース
|   |   +-- (podman-setup.exe)                 Podman Windows インストーラ
|   +-- ansible-collections/
|   |   +-- requirements.yml                   コレクション依存定義
|   |   +-- ansible-windows-3.7.0.tar.gz
|   |   +-- community-windows-3.3.0.tar.gz
|   |   +-- ansible-posix-2.2.2.tar.gz
|   |   +-- community-general-13.3.0.tar.gz
|   |   +-- community-library_inventory_filtering_v1-1.1.5.tar.gz
|   +-- training-materials/
|       +-- ansible_training_2026.tar.gz       研修資材アーカイブ
|
+-- kvm/                                       KVM テスト環境構築
    +-- README.md                              KVM 環境構築ガイド
    +-- create-airgap-network.xml              隔離ネットワーク定義 (libvirt)
    +-- prepare-kvm-host.sh                    KVM ホスト準備スクリプト
    +-- create-rhel-vm.sh                      RHEL 10 VM 作成スクリプト
    +-- create-windows-vm.sh                   Windows 11 VM 作成スクリプト
    +-- vms/
        +-- rhel-airgap.qcow2                  RHEL VM ディスクイメージ
```

---

## 付録

### A. 使用ソフトウェアバージョン一覧

| ソフトウェア | バージョン | 用途 |
|------------|----------|------|
| Ansible (ansible パッケージ) | 14.3.1 | 自動化フレームワーク |
| Ansible Core | 2.21.3 | Ansible エンジン |
| ansible-lint | 26.8.0 | Playbook 静的解析 |
| pywinrm | 0.5.0 | Windows リモート管理 |
| docker-compose | v2.36.1 | コンテナオーケストレーション |
| Podman (Windows) | 5.5.0 | Windows コンテナランタイム |
| sshpass | 1.10 | SSH パスワード認証ヘルパー |

### B. Ansible コレクション一覧

| コレクション | バージョン | 用途 |
|------------|----------|------|
| ansible.windows | 3.7.0 | Windows モジュール群 |
| community.windows | 3.3.0 | Windows 拡張モジュール群 |
| ansible.posix | 2.2.2 | POSIX モジュール群 |
| community.general | 13.3.0 | 汎用モジュール群 |
| community.library_inventory_filtering_v1 | 1.1.5 | インベントリフィルタリング (依存) |

### C. KVM VM スペック一覧

| 項目 | RHEL 10 VM | Windows 11 VM |
|------|-----------|---------------|
| VM名 (デフォルト) | rhel10-airgap-target | win11-airgap-target |
| メモリ | 4096 MB | 8192 MB |
| vCPU | 4 | 4 |
| ディスク | 100 GB | 120 GB (SATA) |
| ネットワーク | airgap-training | airgap-training |
| MAC アドレス | 52:54:00:AA:BB:10 | 52:54:00:AA:BB:20 |
| 固定 IP | 192.168.100.10 | 192.168.100.20 |
| ブート方式 | BIOS (デフォルト) | UEFI |
| TPM | 不要 | TPM 2.0 (swtpm エミュレーション) |
| Graphics | VNC | VNC |
| OS Variant | rhel10-unknown | win11 |
