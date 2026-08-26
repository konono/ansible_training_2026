# バンドル作成ガイド

オンライン環境でオフラインバンドルを作成する手順です。

## 必要な環境

- RHEL 9 以降（RHEL 10 でも動作可）
- インターネット接続
- 必須コマンド: `podman`, `python3`, `pip`, `git`, `curl`, `dnf`
- Windows バンドルも作成する場合: `skopeo`, `ansible-galaxy`
- ディスク空き: 50GB 以上（UBI 10 ミラー ~2.8GB + コンテナイメージ + ISO）

```bash
for cmd in podman python3 git curl dnf skopeo; do
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
| 1 | コンテナイメージのビルド・保存 (UBI 10 ベース) | `container-images/` |
| 2 | DVD ISO の確認（案内のみ、手動配置が必要） | — |
| 2.5 | UBI 10 リポジトリのミラー（コンテナ内 dnf install 用） | `ubi10-repos/` |
| 3 | docker-compose, sshpass, Podman Windows 等のダウンロード | `binaries/` |
| 3.5 | 7-Zip MSI, Chocolatey nupkg のダウンロード | `packages/` |
| 4 | pip パッケージのダウンロード (Python 3.12 + 3.9 両対応) | `pip-packages/` |
| 5 | Ansible コレクションのダウンロード | `ansible-collections/` |
| 6 | トレーニング資材のアーカイブ | `training-materials/` |
| 7 | チェックサム生成 | `checksums.sha256` |

Windows が不要な場合:

```bash
SKIP_WINDOWS=true ./prepare-offline-bundle.sh
```

## Step 2: RHEL DVD ISO の入手

Red Hat カスタマーポータルから `rhel-version.conf` に設定したバージョンの DVD ISO をダウンロードし、`offline-resources/iso/` に配置します。

```bash
mkdir -p offline-resources/iso/
# rhel-version.conf の RHEL_VERSION に合わせた ISO を配置
cp /path/to/rhel-9.4-x86_64-dvd.iso offline-resources/iso/
```

- URL: https://access.redhat.com/downloads/content/rhel
- サイズ: 約 11GB
- 必須: BaseOS と AppStream の両方が含まれる DVD ISO（Boot ISO は不可）
- 用途: リポジトリサーバーでの HTTP 配信 **および** コントローラノードのセットアップ（`setup-controller.sh` が ISO をマウントして前提パッケージをインストール）

## Step 3: バンドルの確認

```bash
# 全ファイルの一覧とサイズ
du -sh offline-resources/*/

# 期待される構成:
# iso/               ~11GB   RHEL DVD ISO
# ubi10-repos/       ~2.8GB  UBI 10 BaseOS + AppStream ミラー
# container-images/  ~1.7GB  training-controller.tar + training-linux-node.tar
# binaries/          ~560MB  docker-compose, sshpass, WSL, Podman 等
# packages/          ~255MB  7-Zip MSI, Chocolatey, VSCode, Python 等
# pip-packages/      ~120MB  ansible, pywinrm 等 (Python 3.12 + 3.9)
# ansible-collections/ ~4MB  ansible.windows 等
# training-materials/  ~164KB トレーニング資材アーカイブ

# チェックサム検証
cd offline-resources/
sha256sum -c checksums.sha256
```

> **注意**: VM イメージ（KVM ゲストイメージ、Windows qcow2）はこのバンドルに**含まれません**。
> デプロイ先の VM は VMware, Hyper-V, 物理マシン等で個別に用意します。
> 開発テスト用の KVM VM イメージの入手方法は [開発者ガイド](development-guide.md) を参照してください。

## Step 4: 持ち込み用に固める

バイナリ資材を tar で固め、Playbook コードと合わせて USB にコピーします。

```bash
cd /path/to/ansible_training_2026

# バイナリ資材を tar.gz に（vm-images は開発用なので除外）
tar czf airgap-offline-resources.tar.gz \
  -C airgap \
  --exclude='offline-resources/vm-images' \
  offline-resources/

ls -lh airgap-offline-resources.tar.gz
# → 約 13GB（ISO 11GB + その他 2GB）

# USB にコピー
cp airgap-offline-resources.tar.gz /mnt/usb/
cp -r airgap/ /mnt/usb/airgap/   # Playbook・スクリプト・ドキュメント
sync
umount /mnt/usb
```

USB の内容:
```
/mnt/usb/
├── airgap/                         # Playbook・スクリプト（git リポジトリの内容）
│   ├── setup-controller.sh
│   ├── deploy-training.sh
│   ├── playbooks/
│   ├── docs/
│   └── ...（offline-resources/ は空）
└── airgap-offline-resources.tar.gz # バイナリ資材（tar 圧縮）
```

持ち込み後の構築手順は [構築ガイド](deployment-guide.md) を参照してください。
