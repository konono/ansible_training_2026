# 引き継ぎプロンプト: Airgap Windows 11 VM 検証

## 背景

Ansible研修資材をairgap環境で実行可能にするプロジェクトで、以下が完了済み:

1. **RHEL 10 VM**: CentOS Stream 9 VM(QEMU TCGモード)で検証済み
   - `ansible-playbook playbooks/rhel-setup.yml` → ok=31 failed=0
   - `ansible-playbook playbooks/verify.yml` → ok=7 failed=0
   - controller→node1-3,lb への ansible ping 全成功

2. **Windows 11 VM**: qcow2イメージ取得済みだがTCGモードでは起動が遅すぎて中断

3. **ドキュメント**: `docs/architecture.md`, `docs/operations-guide.md` 作成済み

## 残タスク: Windows 11 VMの検証

### 前提条件

- `virsh` が使える KVM 対応ホスト（`/dev/kvm` 有り）
- このリポジトリが `/home/kono/ansible_training_2026/` にある

### Windows 11 qcow2 イメージ

既にダウンロード済み:
```
airgap/kvm/vms/win11/windows-11-25h2.qcow2  (14GB, 仮想40GB)
```

ソース: `ghcr.io/cocoonstack/windows/win11:25h2` (cocoonstack/windows リポジトリ)

### クレデンシャル

| 項目 | 値 |
|------|-----|
| ユーザー名 | `cocoon` |
| パスワード | `C@c#on160` |
| WinRM | Basic認証, ポート5985, AllowUnencrypted=True |
| RDP | ポート3389 |
| AutoLogon | 有効（cocoonユーザー） |

### 実行手順

#### 1. KVM で Windows 11 VM を起動

```bash
# OVMF VARS ファイルをコピー（VM個別の書き込み可能コピーが必要）
cp /usr/share/edk2/ovmf/OVMF_VARS.secboot.fd /tmp/win11-OVMF_VARS.fd

# VM起動（KVMアクセラレーション有効）
sudo /usr/libexec/qemu-kvm \
    -name win11-airgap \
    -machine q35,smm=on \
    -accel kvm \
    -cpu host,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time,hv_vpindex,hv_runtime,hv_synic,hv_stimer,hv_reset,hv_frequencies,hv_reenlightenment,hv_tlbflush,hv_ipi \
    -m 4096 \
    -smp 4 \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,unit=0,file=/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=/tmp/win11-OVMF_VARS.fd \
    -drive file=airgap/kvm/vms/win11/windows-11-25h2.qcow2,format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::3389-:3389,hostfwd=tcp::5985-:5985,restrict=on \
    -device virtio-net-pci,netdev=net0 \
    -device qemu-xhci \
    -device usb-tablet \
    -display none \
    -daemonize \
    -pidfile /tmp/qemu-win11.pid
```

KVMモードなら1-3分で起動完了する見込み。

**注意**: `hv_*` フラグは Hyper-V エンライトメントで、Windows VM 内で
WSL2/Podman が使用するネスト仮想化を可能にします。これらがないと
`podman machine init/start` が失敗します。

#### 2. WinRM 接続確認

```bash
# WinRM 応答確認（HTTP 200が返るまで待機）
curl -s -o /dev/null -w "%{http_code}" \
    -u "cocoon:C@c#on160" \
    -H "Content-Type: application/soap+xml;charset=UTF-8" \
    -d '<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:wsmid="http://schemas.dmtf.org/wbem/wsman/identity/1/wsmanidentity.xsd"><s:Header/><s:Body><wsmid:Identify/></s:Body></s:Envelope>' \
    "http://localhost:5985/wsman"
```

#### 3. Ansible で接続テスト

```bash
cd airgap/

# Windows 用インベントリを作成
cat > /tmp/win-test-inventory.yml << 'EOF'
all:
  children:
    windows:
      hosts:
        win-airgap-vm:
          ansible_host: 127.0.0.1
          ansible_port: 5985
          ansible_user: cocoon
          ansible_password: "C@c#on160"
          ansible_connection: winrm
          ansible_winrm_transport: basic
          ansible_winrm_server_cert_validation: ignore
EOF

# ansible.windows コレクションをインストール
ansible-galaxy collection install ansible.windows

# ping テスト
ansible -i /tmp/win-test-inventory.yml win-airgap-vm -m ansible.windows.win_ping
```

#### 4. バンドルを転送して Playbook 実行

```bash
# バンドルをWinRM経由でWindows VMに転送
# ※ win_copy は大きなファイルの転送が遅いため、
#   SMB共有やISOマウントの方が実用的

# Playbook実行
ansible-playbook -i /tmp/win-test-inventory.yml playbooks/windows-setup.yml -v
```

### 注意: windows-setup.yml の既知修正事項

RHEL版テストで発覚したパターンに基づき、以下の修正が必要になる可能性あり:

1. **vars_files の追加**: `rhel-setup.yml` と同様に `windows-setup.yml` にも `vars_files` を追加する必要がある可能性
   ```yaml
   vars_files:
     - ../group_vars/all.yml
     - ../group_vars/windows.yml
   ```

2. **cocoonstack イメージのユーザー**: group_vars/windows.yml の `ansible_user` は `ansible` になっているが、cocoonstack イメージのユーザーは `cocoon`。インベントリまたはgroup_varsで上書きが必要

3. **podman on Windows**: cocoonstack イメージには podman がプリインストールされていない可能性。win_podman ロールが正しく動作するか要確認

### .tracecraft ジャーナルの更新指示

作業完了後、以下のファイルに追記してください:

```
.tracecraft/2026-08-18_fa8df054_airgap-ansible-training/worklog.md
```

追記フォーマット:
```markdown
## Step 13: Windows 11 VM 起動（KVMモード）

- **目的**: KVM対応ホストでWindows 11 VMを起動しWinRM接続を確認
- **実行内容**: （実行した内容を記載）
- **結果**: （結果を記載）

## Step 14: Windows 11 Ansible Playbook 実行

- **目的**: airgap Windows VMに対してPlaybookを実行
- **実行内容**: （実行した内容を記載）
- **結果**: （結果を記載）
```

### ファイル構造の概要

```
airgap/
├── README.md                     # 全体ガイド
├── prepare-offline-bundle.sh     # オフラインバンドル作成
├── ansible.cfg                   # Ansible設定
├── inventory/                    # インベントリテンプレート
├── group_vars/                   # 変数定義
├── playbooks/
│   ├── rhel-setup.yml           # RHEL用（検証済み）
│   ├── windows-setup.yml        # Windows用（要検証）
│   ├── verify.yml               # 検証用（RHEL検証済み）
│   ├── site.yml                 # マスター
│   └── roles/                   # 5ロール
├── offline-resources/            # オフラインリソース（1.3GB）
├── templates/                    # compose テンプレート, WinRM スクリプト
├── docs/
│   ├── architecture.md          # アーキテクチャ設計書
│   └── operations-guide.md      # 運用手順書
└── kvm/
    ├── vms/win11/windows-11-25h2.qcow2  # Windows 11 イメージ (14GB)
    ├── create-airgap-network.xml
    ├── create-rhel-vm.sh
    ├── create-windows-vm.sh
    └── prepare-kvm-host.sh
```
