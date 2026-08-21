# バンドル作成ガイド

オンライン環境で airgap 用のオフラインバンドルを作成する手順です。

## 必要な環境

- RHEL 10 / CentOS 10 または RHEL 互換 OS
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

## Step 3: バンドルの確認

```bash
# 全ファイルの一覧とサイズ
du -sh offline-resources/*/

# 期待される構成:
# iso/               ~11GB   RHEL 10 DVD ISO
# container-images/  ~1.7GB  training-controller.tar + training-linux-node.tar
# binaries/          ~560MB  docker-compose, sshpass, WSL, Podman 等
# packages/          ~7MB    7-Zip MSI, Chocolatey nupkg
# pip-packages/      ~62MB   ansible, pywinrm 等
# ansible-collections/ ~4MB  ansible.windows 等
# training-materials/  ~114KB 研修資材アーカイブ

# チェックサム検証
cd offline-resources/
sha256sum -c checksums.sha256
```

> **注意**: VM イメージ（KVM ゲストイメージ、Windows qcow2）はこのバンドルに**含まれません**。
> お客様環境の VM は VMware, Hyper-V, 物理マシン等で個別に用意します。
> 開発テスト用の KVM VM イメージの入手方法は [開発者ガイド](development-guide.md) を参照してください。

## Step 4: 持ち込み

`airgap/` ディレクトリ全体を USB ドライブ等にコピーしてお客様環境に転送します。

```bash
cp -r /path/to/ansible_training_2026/airgap/ /mnt/usb/
sync
umount /mnt/usb
```

持ち込み後の構築手順は [構築ガイド](deployment-guide.md) を参照してください。
