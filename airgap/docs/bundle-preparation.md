# バンドル作成ガイド

オンライン環境で airgap 用のオフラインバンドルを作成する手順です。

## 必要な環境

- RHEL 10 / CentOS 10 またはRHEL互換OS
- インターネット接続
- 以下のコマンド: `podman`, `python3`, `pip`, `git`, `curl`, `dnf`, `ansible`, `skopeo`
- ディスク空き: 50GB 以上

```bash
for cmd in podman python3 git curl dnf ansible skopeo; do
    printf "%-10s " "$cmd:"
    command -v $cmd >/dev/null 2>&1 && echo "OK" || echo "NOT FOUND"
done
```

## Step 1: バンドル作成スクリプトの実行

```bash
cd airgap/
./prepare-offline-bundle.sh
```

| Phase | 処理内容 | 生成先 |
|---|---|---|
| 1 | コンテナイメージのビルド・保存 | `container-images/` |
| 2 | DVD ISO の確認（案内のみ） | — |
| 3 | docker-compose, sshpass, Podman Windows 等のダウンロード | `binaries/` |
| 3.5 | 7-Zip MSI, Chocolatey nupkg のダウンロード | `packages/` |
| 4 | pip パッケージのダウンロード | `pip-packages/` |
| 5 | Ansible コレクションのダウンロード | `ansible-collections/` |
| 6 | 研修資材のアーカイブ | `training-materials/` |
| 7 | チェックサム生成 | `checksums.sha256` |

Windows が不要な場合:

```bash
SKIP_WINDOWS=true ./prepare-offline-bundle.sh
```

## Step 2: RHEL 10 DVD ISO の入手

Red Hat カスタマーポータルから RHEL 10 DVD ISO をダウンロードし、`offline-resources/iso/` に配置します。

```bash
mkdir -p offline-resources/iso/
cp /path/to/rhel-10.2-x86_64-dvd.iso offline-resources/iso/
```

- URL: https://access.redhat.com/downloads/content/rhel
- サイズ: 約 11GB
- 必須: BaseOS と AppStream の両方が含まれる DVD ISO（Boot ISO は不可）

## Step 3: KVM ゲストイメージの入手

Red Hat カスタマーポータルから RHEL 10 KVM Guest Image をダウンロードし、`offline-resources/vm-images/` に配置します。

```bash
mkdir -p offline-resources/vm-images/
cp /path/to/rhel-10.2-x86_64-kvm.qcow2 offline-resources/vm-images/
```

- URL: https://access.redhat.com/downloads/content/rhel （Cloud and Container Images セクション）
- サイズ: 約 1.1GB

## Step 4: Windows 11 qcow2 イメージの入手（オプション）

[cocoonstack/windows](https://github.com/cocoonstack/windows) リポジトリが、WinRM/SSH 設定済みの Windows 11 VM イメージを GitHub Container Registry (ghcr.io) に公開しています。

このイメージは通常のコンテナイメージではなく、qcow2 ディスクイメージを OCI アーティファクトとして格納したものです。14GB のファイルを約 1.9GB × 8 パーツに分割して保存されており、ダウンロード後に結合する必要があります。

### oras CLI のインストール

`oras` (OCI Registry As Storage) は、コンテナレジストリから任意のファイル（コンテナイメージ以外も含む）を取得するための CLI ツールです。

```bash
curl -fsSL https://github.com/oras-project/oras/releases/download/v1.2.2/oras_1.2.2_linux_amd64.tar.gz \
  | tar xz -C /usr/local/bin/ oras
oras version  # 動作確認
```

### イメージのダウンロードと結合

```bash
# 作業ディレクトリを作成
mkdir -p offline-resources/vm-images/win11-parts/
cd offline-resources/vm-images/win11-parts/

# ダウンロード（9ファイル: 8パーツ + SHA256SUMS, 計 約14GB）
oras pull ghcr.io/cocoonstack/windows/win11:25h2

# ダウンロードされるファイル:
#   windows-11-25h2.qcow2.00.qcow2.part  (1.9GB)
#   windows-11-25h2.qcow2.01.qcow2.part  (1.9GB)
#   ...
#   windows-11-25h2.qcow2.07.qcow2.part  (756MB)
#   SHA256SUMS

# チェックサム検証
sha256sum -c SHA256SUMS

# パーツを結合して 1 つの qcow2 ファイルにする
cat *.part > ../windows-11-25h2.qcow2

# 作業ディレクトリを削除
cd ..
rm -rf win11-parts/

# 結果を確認（約 14GB の qcow2 ファイル）
ls -lh windows-11-25h2.qcow2
```

### cocoonstack イメージの仕様

このイメージには以下が事前設定されています:

| 項目 | 値 |
|---|---|
| OS | Windows 11 Pro (Build 26200) |
| ユーザー | `cocoon` |
| パスワード | `C@c#on160` |
| WinRM | Basic 認証, ポート 5985, AllowUnencrypted=True |
| OpenSSH | ポート 22（デフォルトシェル: cmd.exe） |
| AutoLogon | 有効（cocoon ユーザー） |
| 仮想ディスク | 40GB (シンプロビジョニング) |

> **注意**: Ansible から SSH 接続する場合、デフォルトシェルを PowerShell に変更する必要があります。
> これは `win_podman` ロールの事前チェックタスクで自動設定されます。

## Step 5: バンドルの確認

```bash
# 全ファイルの一覧とサイズ
du -sh offline-resources/*/

# 期待される構成:
# iso/              ~11GB   RHEL 10 DVD ISO
# vm-images/        ~24GB   KVM ゲストイメージ + Windows qcow2
# container-images/ ~1.7GB  training-controller.tar + training-linux-node.tar
# binaries/         ~560MB  docker-compose, sshpass, WSL, Podman 等
# packages/         ~7MB    7-Zip MSI, Chocolatey nupkg
# pip-packages/     ~62MB   ansible, pywinrm 等
# ansible-collections/ ~4MB ansible.windows 等
# training-materials/  ~114KB 研修資材アーカイブ

# チェックサム検証
cd offline-resources/
sha256sum -c checksums.sha256
```

## Step 6: 持ち込み

`airgap/` ディレクトリ全体を USB ドライブ等にコピーしてお客様環境に転送します。

```bash
# USB ドライブにコピー
cp -r /path/to/ansible_training_2026/airgap/ /mnt/usb/
sync
umount /mnt/usb
```

持ち込み後の構築手順は [構築ガイド](deployment-guide.md) を参照してください。
