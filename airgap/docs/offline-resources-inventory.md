# オフライン持ち込みリソース一覧 — 検疫審査向け資料

## 本書の目的

本書は、Ansible トレーニング環境をインターネット非接続（エアギャップ）環境に構築するために持ち込むファイル群について、検疫審査時の判断材料として各ディレクトリの内容・用途・取得元・必要性を説明するものです。

すべてのファイルは公式配布元からダウンロードしたものであり、改変は行っていません。全ファイルの SHA-256 チェックサムを `checksums.sha256` に記録しており、持ち込み後に改ざんがないことを検証できます。

---

## 全体概要

| ディレクトリ | 概要 | 合計サイズ |
|---|---|---|
| `iso/` | RHEL DVD ISO イメージ | 約 21 GB |
| `container-images/` | トレーニング用コンテナイメージ | 約 1.8 GB |
| `binaries/` | 構築に必要なバイナリ・インストーラ | 約 561 MB |
| `packages/` | Windows 演習環境用アプリケーション | 約 255 MB |
| `pip-packages/` | Linux 向け Python パッケージ | 約 72 MB |
| `pip-packages-windows/` | Windows 向け Python パッケージ | 約 7.5 MB |
| `ansible-collections/` | Ansible 拡張モジュール集 | 約 4 MB |
| `training-materials/` | トレーニング教材アーカイブ | 約 168 KB |
| `checksums.sha256` | 全ファイルの整合性検証用チェックサム | — |

---

## 1. `iso/` — RHEL DVD ISO イメージ

### 含まれるファイル

| ファイル名 | 説明 |
|---|---|
| `rhel-10.2-x86_64-dvd.iso` | Red Hat Enterprise Linux 10.2 インストール DVD ISO |
| `rhel-9.4-x86_64-dvd.iso` | Red Hat Enterprise Linux 9.4 インストール DVD ISO |

### 用途

エアギャップ環境内でローカル RPM リポジトリサーバーを構築するために使用します。通常 Linux サーバーはインターネット上の Red Hat リポジトリからパッケージを取得しますが、オフライン環境ではそれができないため、DVD ISO に収録された RPM パッケージ群を HTTP サーバー (nginx) 経由でローカル配信し、`dnf` / `yum` の代替リポジトリとして機能させます。

### なぜ必要か

トレーニング環境の構築時に Linux サーバーへ必要なソフトウェア（podman、nginx、openssh-server 等）をインストールするために、RPM パッケージの供給源が必須です。インターネット接続がない環境では DVD ISO がその唯一の供給手段となります。

### 取得元

Red Hat カスタマーポータル（https://access.redhat.com/downloads）から、有効なサブスクリプションを用いてダウンロードしたものです。

### 検疫上の留意点

ISO ファイル内には OS を構成する数千の RPM パッケージが含まれます。Red Hat が署名・配布する公式メディアであり、改変は行っていません。

---

## 2. `container-images/` — トレーニング用コンテナイメージ

### 含まれるファイル

| ファイル名 | 説明 |
|---|---|
| `training-controller.tar` | Ansible コントローラ用コンテナイメージ |
| `training-linux-node.tar` | 管理対象 Linux ノード用コンテナイメージ |
| `dockurr-windows.tar` | Windows 演習用コンテナイメージ |

### 用途

各受講者に独立したトレーニング環境（Ansible コントローラ 1 台 + 管理対象ノード 3 台 + ロードバランサー 1 台）をコンテナとして提供するために使用します。`podman load` でイメージを読み込み、`docker-compose` で起動します。

### なぜ必要か

受講者ごとに隔離された演習環境を効率的に大量展開するため、コンテナ技術を採用しています。オフライン環境ではコンテナレジストリ（Docker Hub 等）にアクセスできないため、事前にビルド・保存した `.tar` ファイルとして持ち込みます。

### 取得元・ビルド方法

- **training-controller.tar / training-linux-node.tar**: Red Hat 公式のベースイメージ `registry.access.redhat.com/ubi10/ubi-init`（UBI 10 = Red Hat Universal Base Image 10）をベースに、オンライン環境でビルドしたものです。追加でインストールしているパッケージは `openssh-server`、`python3`、`ansible` 等、トレーニングに必要な標準的なソフトウェアのみです。
- **dockurr-windows.tar**: Docker Hub（`docker.io/dockurr/windows`）から取得した、Windows 演習用のオープンソースコンテナイメージです。

### 検疫上の留意点

`.tar` ファイルはコンテナイメージのアーカイブ形式（OCI/Docker 形式）であり、実行可能バイナリそのものではありません。`podman load` コマンドでコンテナランタイムに読み込んで初めてコンテナとして起動可能になります。ベースイメージは Red Hat 公式の UBI（Universal Base Image）であり、商用利用が許可された公式イメージです。

---

## 3. `binaries/` — 構築に必要なバイナリ・インストーラ

### 含まれるファイル

| ファイル名 | 説明 |
|---|---|
| `docker-compose-linux-x86_64` | Docker Compose CLI（Linux 版） |
| `docker-compose-windows-x86_64.exe` | Docker Compose CLI（Windows 版） |
| `sshpass-1.10.tar.gz` | sshpass ソースコード |
| `podman-setup.exe` | Podman Desktop インストーラ（Windows 版） |
| `wsl.msi` | WSL（Windows Subsystem for Linux）インストーラ |
| `podman-machine-wsl.ociarchive` | Podman Machine 用 WSL イメージ |

### 用途

| ファイル | 用途 |
|---|---|
| `docker-compose-*` | トレーニングサーバー上で受講者ごとのコンテナ群（controller + node1-3 + lb）を一括管理（起動・停止・削除）するために使用します |
| `sshpass-1.10.tar.gz` | Ansible がパスワード認証で SSH 接続する際に必要なツールです。ソースコードからコンパイルしてインストールします |
| `podman-setup.exe` | Windows クライアント上で Podman（コンテナランタイム）を利用する場合のインストーラです |
| `wsl.msi` | Windows 上で Podman を動作させるために必要な WSL 2 のインストーラです |
| `podman-machine-wsl.ociarchive` | Podman Machine が WSL 上で使用する Linux ディストリビューションイメージです |

### なぜ必要か

- **docker-compose**: 受講者 1 名あたり 5 つのコンテナで構成される演習環境を、YAML 定義に基づいて一括で起動・管理するためのオーケストレーションツールです。これがないと各コンテナを個別に手動で起動・ネットワーク設定する必要があり、運用が非現実的になります。
- **sshpass**: Ansible のパスワード認証 SSH 接続に必須のツールです。RHEL の標準リポジトリに含まれないため、ソースコードから個別にビルドします。
- **Podman / WSL 関連**: Windows クライアントからコンテナ操作を行う演習がある場合に使用します。

### 取得元

| ファイル | 取得元 |
|---|---|
| `docker-compose-*` | GitHub 公式リリース: `https://github.com/docker/compose/releases` (v2.36.1) |
| `sshpass-1.10.tar.gz` | SourceForge 公式プロジェクト: `https://sourceforge.net/projects/sshpass/` |
| `podman-setup.exe` | GitHub 公式リリース: `https://github.com/containers/podman/releases` (v5.5.0) |
| `wsl.msi` | GitHub 公式リリース: `https://github.com/microsoft/WSL/releases` (v2.4.13) |
| `podman-machine-wsl.ociarchive` | Quay.io 公式レジストリ: `quay.io/podman/machine-os-wsl` (tag 5.5) |

### 検疫上の留意点

- `docker-compose-linux-x86_64` は実行可能バイナリ（Go 言語で静的リンクされたシングルバイナリ）です。Docker/Moby プロジェクト（CNCF 関連の OSS）の公式リリースです。
- `docker-compose-windows-x86_64.exe` は上記の Windows 版です。
- `sshpass-1.10.tar.gz` は C 言語のソースコードアーカイブであり、実行可能バイナリではありません。持ち込み先でコンパイルして使用します。
- `podman-setup.exe` は Red Hat がスポンサーする OSS プロジェクト Podman の公式 Windows インストーラです。
- `wsl.msi` は Microsoft 公式の WSL インストーラです。
- `podman-machine-wsl.ociarchive` はコンテナイメージアーカイブ（OCI 形式）で、Podman 公式が配布する Linux ディストリビューションイメージです。

---

## 4. `packages/` — Windows 演習環境用アプリケーション

### 含まれるファイル

| ファイル名 | 説明 |
|---|---|
| `7z2301-x64.msi` | 7-Zip ファイルアーカイバ（MSI インストーラ） |
| `VSCodeSetup-x64.exe` | Visual Studio Code エディタ（System Installer） |
| `ms-vscode-remote.remote-ssh.vsix` | VSCode Remote-SSH 拡張機能 |
| `python-3.12.10-amd64.exe` | Python 3.12.10 インストーラ（Windows 版） |
| `chocolatey.nupkg` | Chocolatey パッケージマネージャ |

### 用途

受講者が使用する Windows クライアント PC にトレーニングに必要なソフトウェアをインストールするために使用します。

| ファイル | 用途 |
|---|---|
| `7z2301-x64.msi` | アーカイブファイルの展開に使用します |
| `VSCodeSetup-x64.exe` | 受講者がコードエディタとして使用します。Ansible Playbook の編集に利用します |
| `ms-vscode-remote.remote-ssh.vsix` | VSCode からトレーニングサーバーに SSH 接続し、リモートで Playbook を編集するための拡張機能です |
| `python-3.12.10-amd64.exe` | Windows 上で Ansible を実行するために必要な Python ランタイムです |
| `chocolatey.nupkg` | Ansible の `win_chocolatey` モジュールによるパッケージ管理演習で使用する Windows 用パッケージマネージャです |

### なぜ必要か

受講者の Windows PC はインターネットに接続できないため、必要なソフトウェアを事前にダウンロードして持ち込む必要があります。これらはすべてトレーニング演習の遂行に直接必要なツールです。

### 取得元

| ファイル | 取得元 |
|---|---|
| `7z2301-x64.msi` | 7-Zip 公式サイト: `https://www.7-zip.org/` (v23.01) |
| `VSCodeSetup-x64.exe` | Microsoft 公式: `https://code.visualstudio.com/` (最新安定版) |
| `ms-vscode-remote.remote-ssh.vsix` | VSCode Marketplace: `https://marketplace.visualstudio.com/` (最新版) |
| `python-3.12.10-amd64.exe` | Python 公式サイト: `https://www.python.org/` (v3.12.10) |
| `chocolatey.nupkg` | Chocolatey 公式: `https://packages.chocolatey.org/` (v2.7.3) |

### 検疫上の留意点

いずれも広く利用されている一般的なソフトウェアの公式インストーラです。`.exe` や `.msi` は Windows インストーラ形式のファイルであり、各ベンダーが署名済みで配布しているものです。`.vsix` は VSCode 拡張機能のパッケージ形式（実体は ZIP アーカイブ）です。`.nupkg` は NuGet パッケージ形式（同じく ZIP アーカイブ）です。

---

## 5. `pip-packages/` — Linux 向け Python パッケージ

### 含まれるファイル（主要パッケージ）

| パッケージ名 | バージョン | 説明 |
|---|---|---|
| `ansible` | 14.3.1 | Ansible 自動化ツール本体（メタパッケージ） |
| `ansible_core` | 2.21.3 / 2.15.13 | Ansible エンジン本体 |
| `ansible_lint` | 26.8.0 | Ansible Playbook の品質チェックツール |
| `pywinrm` | 0.5.0 | Windows リモート管理 (WinRM) 接続ライブラリ |
| `jmespath` | 1.1.0 | JSON クエリ言語ライブラリ |
| `cryptography` | 50.0.0 / 43.0.3 | 暗号化ライブラリ（SSH/TLS 接続に使用） |
| その他 | — | 上記パッケージの依存関係（requests, pyyaml, jinja2, cffi 等） |

※ Python 3.12（RHEL 10）用と Python 3.9（RHEL 9）用の両バージョンが含まれます。

### 用途

トレーニングサーバー上の Ansible コントローラコンテナ内に Ansible およびその依存パッケージをインストールするために使用します。`pip install --no-index` で、インターネットアクセスなしにローカルファイルからインストールします。

### なぜ必要か

Ansible は Python で書かれた自動化ツールであり、pip（Python パッケージマネージャ）経由でインストールします。オフライン環境では PyPI（Python Package Index）にアクセスできないため、必要なパッケージを `.whl`（Wheel）ファイルとして事前にダウンロードして持ち込みます。

### 取得元

Python Package Index (PyPI): `https://pypi.org/` から `pip download` コマンドで取得しました。すべてのパッケージは PyPI 上で公開されているオープンソースソフトウェアです。

### 検疫上の留意点

`.whl` ファイルは Python Wheel 形式のパッケージアーカイブ（実体は ZIP ファイル）です。実行可能バイナリではなく、`pip install` コマンドで展開・インストールして初めて機能します。一部のパッケージ（cryptography, cffi, pyyaml 等）にはプラットフォーム固有のコンパイル済みバイナリ（`.so` 共有ライブラリ）が含まれますが、これらは PyPI 公式が配布するビルド済みパッケージです。

---

## 6. `pip-packages-windows/` — Windows 向け Python パッケージ

### 含まれるファイル（主要パッケージ）

| パッケージ名 | バージョン | 説明 |
|---|---|---|
| `ansible_core` | 2.21.3 | Ansible エンジン本体 |
| `pywinrm` | 0.5.0 | Windows リモート管理 (WinRM) 接続ライブラリ |
| `cryptography` | 50.0.0 | 暗号化ライブラリ |
| その他 | — | 依存パッケージ（requests, pyyaml, jinja2 等） |

### 用途

Windows クライアント上で Ansible を実行するための Python パッケージです。`pip-packages/`（Linux 版）とは異なり、Windows (win_amd64) 向けにビルドされた `.whl` ファイルです。

### なぜ必要か

受講者が Windows PC から直接 Ansible を実行する演習で使用します。Windows 版 Python 環境に対応したパッケージが必要です。

### 取得元

Python Package Index (PyPI): `https://pypi.org/` から、`--platform win_amd64 --python-version 3.12` を指定して `pip download` で取得しました。

### 検疫上の留意点

`pip-packages/` と同様、Python Wheel 形式のパッケージです。Windows 向けのコンパイル済みバイナリ（`.pyd` / `.dll`）を含むパッケージがありますが、PyPI 公式配布のものです。

---

## 7. `ansible-collections/` — Ansible 拡張モジュール集

### 含まれるファイル

| ファイル名 | 説明 |
|---|---|
| `ansible-windows-3.7.0.tar.gz` | Windows 管理用 Ansible モジュール集 |
| `community-windows-3.3.0.tar.gz` | Windows 管理用コミュニティモジュール集 |
| `ansible-posix-2.2.2.tar.gz` | POSIX (Linux/Unix) 管理用モジュール集 |
| `community-general-13.3.0.tar.gz` | 汎用コミュニティモジュール集 |
| `community-library_inventory_filtering_v1-1.1.5.tar.gz` | インベントリフィルタリング用ライブラリ（依存関係） |
| `requirements.yml` | コレクションの依存関係定義ファイル |

### 用途

Ansible の標準モジュールを拡張し、Windows の管理（`win_copy`, `win_chocolatey`, `win_service` 等）や Linux の高度な操作（`firewalld`, `seboolean` 等）を可能にするモジュール集です。`ansible-galaxy collection install` でオフラインインストールします。

### なぜ必要か

Ansible のコアには Windows 管理用のモジュールが含まれていません。Windows ノードの管理演習を行うためには `ansible.windows` コレクションが必須です。また、`community.general` には多くの実務で使われるモジュール（`firewalld`, `nmcli` 等）が含まれており、トレーニングの演習で使用します。

### 取得元

Ansible Galaxy（`https://galaxy.ansible.com/`）から `ansible-galaxy collection download` コマンドで取得しました。Ansible Galaxy は Red Hat が運営する Ansible コレクションの公式配布プラットフォームです。

### 検疫上の留意点

`.tar.gz` ファイルは Ansible コレクションのパッケージ形式であり、中身は YAML ファイル、Python スクリプト（Ansible モジュール/プラグイン）、およびドキュメントです。実行可能バイナリは含まれていません。

---

## 8. `training-materials/` — トレーニング教材アーカイブ

### 含まれるファイル

| ファイル名 | 説明 |
|---|---|
| `ansible_training_2026.tar.gz` | トレーニング教材一式（Playbook, 演習問題, ドキュメント） |

### 用途

受講者が演習で使用する Ansible Playbook のサンプルコード、演習問題、解説ドキュメントなどの教材一式です。各受講者のコンテナ環境に配布されます。

### なぜ必要か

トレーニングの主要コンテンツであり、受講者が実際にハンズオンで使用する資料です。

### 取得元

弊社が作成したトレーニング教材を `git archive` でアーカイブしたものです。

### 検疫上の留意点

中身はテキストファイル（YAML, Markdown, シェルスクリプト等）のみです。実行可能バイナリは含まれていません。

---

## 9. `checksums.sha256` — 整合性検証用チェックサム

### 用途

上記すべてのファイルの SHA-256 ハッシュ値を記録したファイルです。持ち込み後に `sha256sum -c checksums.sha256` を実行することで、すべてのファイルが転送中に改ざん・破損されていないことを検証できます。

### 検証方法

```bash
cd offline-resources/
sha256sum -c checksums.sha256
```

すべてのファイルで `OK` が表示されれば、取得時と同一のファイルであることが確認できます。

---

## 補足: ファイル形式の分類

検疫審査の参考として、持ち込みファイルをファイル形式別に分類します。

| 形式 | 該当ファイル | 性質 |
|---|---|---|
| **ISO ディスクイメージ** | `rhel-*.iso` | OS インストールメディアの標準形式。内部に RPM パッケージ群を含む |
| **コンテナイメージ (.tar)** | `training-*.tar`, `dockurr-*.tar` | コンテナランタイム用のイメージアーカイブ。`podman load` で読み込む |
| **OCI アーカイブ** | `podman-machine-wsl.ociarchive` | OCI 規格のコンテナイメージアーカイブ |
| **実行可能バイナリ (Linux)** | `docker-compose-linux-x86_64` | Go 言語の静的リンクバイナリ（1 ファイル） |
| **Windows インストーラ (.exe)** | `VSCodeSetup-*.exe`, `python-*.exe`, `podman-setup.exe`, `docker-compose-*.exe` | 各ベンダー署名済みのインストーラ |
| **Windows インストーラ (.msi)** | `7z*.msi`, `wsl.msi` | Microsoft Installer 形式 |
| **Python Wheel (.whl)** | `pip-packages/` 内全ファイル, `pip-packages-windows/` 内全ファイル | Python パッケージの ZIP アーカイブ |
| **Ansible Collection (.tar.gz)** | `ansible-collections/` 内の tar.gz | YAML + Python スクリプトのアーカイブ |
| **ソースコード (.tar.gz)** | `sshpass-1.10.tar.gz` | C 言語ソースコード（バイナリなし） |
| **VSCode 拡張 (.vsix)** | `ms-vscode-remote.remote-ssh.vsix` | VSCode 拡張機能（ZIP アーカイブ） |
| **NuGet パッケージ (.nupkg)** | `chocolatey.nupkg` | .NET パッケージ（ZIP アーカイブ） |
| **教材 (.tar.gz)** | `ansible_training_2026.tar.gz` | テキストファイルのみのアーカイブ |

---

## 付録: 公式配布元ハッシュ値との照合結果

持ち込みファイルの真正性を確認するため、各ベンダーの公式配布元が公開しているハッシュ値と、本バンドルに含まれるファイルのハッシュ値を照合しました。以下の表に記載されたすべてのファイルについて、公式値と一致することを確認済みです。

### binaries/ — スタンドアロンバイナリ

| ファイル名 | ハッシュ種別 | 公式配布元のハッシュ値 | 照合結果 | 公式情報源 |
|---|---|---|---|---|
| `docker-compose-linux-x86_64` | SHA-256 | `8c410e789d3fa688201170a8efb52048ee0dcb0d4cde44ce92a1bb6949f49fcb` | **一致** | [GitHub docker/compose v2.36.1 checksums.txt](https://github.com/docker/compose/releases/tag/v2.36.1) |
| `docker-compose-windows-x86_64.exe` | SHA-256 | `0291c2f108655128dc36005d0c703869d9d98a1d403ed9bb8719356b9e5f2704` | **一致** | 同上 |
| `podman-setup.exe` | SHA-256 | `bae952594fb302c173a1deed5ad98fd11df9b50f8088c16ca4871be972e9496f` | **一致** | [GitHub containers/podman v5.5.0 shasums](https://github.com/containers/podman/releases/tag/v5.5.0) |
| `sshpass-1.10.tar.gz` | — | — | — | SourceForge にハッシュ値の公開なし |
| `wsl.msi` | — | — | — | Microsoft GitHub リリースにハッシュ値の公開なし |
| `podman-machine-wsl.ociarchive` | — | — | — | コンテナレジストリ (Quay.io) から `skopeo copy` で取得。レジストリのダイジェスト検証済み |

### packages/ — Windows アプリケーション

| ファイル名 | ハッシュ種別 | 公式配布元のハッシュ値 | 照合結果 | 公式情報源 |
|---|---|---|---|---|
| `python-3.12.10-amd64.exe` | MD5 | `5eddb0b6f12c852725de071ae681dde4` | **一致** | [python.org Downloads](https://www.python.org/downloads/release/python-31210/) |
| `7z2301-x64.msi` | — | — | — | 7-Zip 公式サイトにハッシュ値の公開なし |
| `VSCodeSetup-x64.exe` | — | — | — | Microsoft 公式。コード署名で真正性を担保（ハッシュ値の個別公開なし） |
| `ms-vscode-remote.remote-ssh.vsix` | — | — | — | VSCode Marketplace からダウンロード。署名検証済み |
| `chocolatey.nupkg` | — | — | — | Chocolatey 公式リポジトリ (NuGet 署名済みパッケージ) |

### pip-packages/ および pip-packages-windows/ — Python パッケージ（主要パッケージ抜粋）

すべてのパッケージは [PyPI (Python Package Index)](https://pypi.org/) から取得しており、PyPI が公開する SHA-256 ハッシュ値と照合済みです。主要パッケージの照合結果を以下に示します。

| パッケージ | バージョン | プラットフォーム | 公式 SHA-256 | 照合結果 | 公式情報源 |
|---|---|---|---|---|---|
| `ansible` | 14.3.1 | any | `efa64b9aa99549d5ad35fa4dadedc258371138db5dc174f47dc026630eda90c9` | **一致** | [PyPI ansible 14.3.1](https://pypi.org/project/ansible/14.3.1/#files) |
| `ansible-core` | 2.21.3 | any | `9e7dd367f7dc5d5e9fc5ae1baf8af9c4edc09e916a73a40108a3f32e3ad93f10` | **一致** | [PyPI ansible-core 2.21.3](https://pypi.org/project/ansible-core/2.21.3/#files) |
| `ansible-lint` | 26.8.0 | any | `94e58501cc7fafaa505dd9daea3bddb4affa6e8efe8217323c06d7194a312f57` | **一致** | [PyPI ansible-lint 26.8.0](https://pypi.org/project/ansible-lint/26.8.0/#files) |
| `pywinrm` | 0.5.0 | any | `c267046d281de613fc7c8a528cdd261564d9b99bdb7c2926221eff3263b700c8` | **一致** | [PyPI pywinrm 0.5.0](https://pypi.org/project/pywinrm/0.5.0/#files) |
| `jmespath` | 1.1.0 | any | `a5663118de4908c91729bea0acadca56526eb2698e83de10cd116ae0f4e97c64` | **一致** | [PyPI jmespath 1.1.0](https://pypi.org/project/jmespath/1.1.0/#files) |
| `cryptography` | 50.0.0 | manylinux_2_34_x86_64 | `82148ec5bddac30b51a5b3c1945075f896fa022cb93f8e4a01e9f6ee95292c5f` | **一致** | [PyPI cryptography 50.0.0](https://pypi.org/project/cryptography/50.0.0/#files) |
| `cryptography` | 50.0.0 | win_amd64 | `bd1c592e4d5974f0d08d4888e432157adba757c66da0246918e43677fafa2d30` | **一致** | 同上 |
| `requests` | 2.34.2 | any | `2a0d60c172f83ac6ab31e4554906c0f3b3588d37b5cb939b1c061f4907e278e0` | **一致** | [PyPI requests 2.34.2](https://pypi.org/project/requests/2.34.2/#files) |
| `pyyaml` | 6.0.3 | cp312 manylinux x86_64 | `ba1cc08a7ccde2d2ec775841541641e4548226580ab850948cbfda66a1befcdc` | **一致** | [PyPI pyyaml 6.0.3](https://pypi.org/project/pyyaml/6.0.3/#files) |
| `pyyaml` | 6.0.3 | cp312 win_amd64 | `5fcd34e47f6e0b794d17de1b4ff496c00986e1c83f7ab2fb8fcfe9616ff7477b` | **一致** | 同上 |
| `pyyaml` | 6.0.3 | cp39 manylinux x86_64 | `0150219816b6a1fa26fb4699fb7daa9caf09eb1999f3b70fb6e786805e80375a` | **一致** | 同上 |

> **注記**: 上記以外の pip パッケージ（依存ライブラリ）も同様に PyPI から取得しており、各パッケージの PyPI ページ (`https://pypi.org/project/<パッケージ名>/<バージョン>/#files`) で SHA-256 ハッシュ値を確認できます。本バンドルの `checksums.sha256` に記録されたハッシュ値はすべて PyPI 公式値と一致します。

### ansible-collections/ — Ansible コレクション

Ansible Galaxy（`https://galaxy.ansible.com/`）から `ansible-galaxy collection download` で取得しています。Ansible Galaxy はダウンロード時にサーバー側でチェックサム検証を行いますが、個別のハッシュ値は Web UI 上では公開されていません。

### 公式ハッシュ値が公開されていないファイルについて

一部のファイルについては配布元がハッシュ値を個別に公開していませんが、以下の方法で真正性が担保されています。

- **Windows インストーラ (.exe / .msi)**: Microsoft、7-Zip 等のベンダーによるコード署名（デジタル署名）が付与されており、Windows 上で署名の検証が可能です
- **コンテナイメージ (.tar)**: Red Hat UBI レジストリからのイメージ取得時にコンテナランタイム（podman）がダイジェスト検証を実施しています
- **sshpass ソースコード**: SourceForge の公式プロジェクトページからダウンロードした C 言語ソースコードであり、実行可能バイナリは含まれていません
