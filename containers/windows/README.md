# Windows コンテナ環境（オプション）

## 概要

[dockur/windows](https://github.com/dockur/windows) を使用して、Windows Server 2022 をコンテナ内で実行し、WinRM 経由で Ansible から管理できる環境を構築します。

## 制約事項

| 項目 | 要件 |
|---|---|
| ホスト OS | **Windows 11 のみ**（nested virtualization + KVM 必須） |
| macOS | **非対応**（KVM を提供できないため動作しません） |
| RAM | 最低 4GB（Windows VM に割り当て） |
| ディスク | 最低 64GB の空き容量 |
| 仮想化 | BIOS で Intel VT-x / AMD SVM が有効であること |
| WSL2 | WSL2(Windows Subsystem for Linux 2) がインストールされていること |

## セットアップ手順

### 1. docker-compose.yml の編集

`containers/docker-compose.yml` 内の `winnode` セクションのコメントを外します。

### 2. コンテナの起動

```bash
docker-compose up -d winnode
```

Windows のインストールが自動で開始されます（約10〜20分）。環境、スペックによってはより時間がかかる場合があります。

### 3. インストール状況の確認

ブラウザで `http://localhost:8006` にアクセスすると、Windows のインストール画面を確認できます。

### 4. WinRM の確認

インストール完了後、`oem/install.bat` が自動実行され WinRM が有効化されます。

```bash
# WinRM ポートの応答確認
curl http://172.20.0.20:5985/wsman
```

### 5. Ansible からの接続テスト

[応用演習 11 - Windowsノードの管理](../advanced/ex11.md)のSection1の手順を実施して、ansibleコマンドを実行します。

```bash
ansible winnode -m ansible.windows.win_ping
```

## インベントリ設定

```yaml
all:
  children:
    windows:
      hosts:
        winnode:
          ansible_host: 172.20.0.20
          ansible_user: ansible
          ansible_password: "AnsiblePass123!"
          ansible_connection: winrm
          ansible_port: 5985
          ansible_winrm_transport: ntlm
          ansible_winrm_server_cert_validation: ignore
```

## OEM フォルダについて

`oem/` フォルダの内容は Windows インストール完了時に `C:\OEM` にコピーされ、`install.bat` が自動実行されます。

- `install.bat` — WinRM 設定スクリプトを呼び出すバッチファイル
- `ConfigureRemotingForAnsible.ps1` — Ansible 公式の WinRM セットアップスクリプト（SSL 証明書生成、ファイアウォールルール追加、認証設定）

## トラブルシューティング

### KVM エラーが発生する場合

```
qemu-system-x86_64: error: KVM is not available
```

- BIOS で仮想化支援機能（VT-x / AMD-V）が有効か確認
- Windows の場合: Hyper-V が有効であること、WSL2 が正しくセットアップされていること
- `podman machine` が KVM をサポートしているか確認

### WinRM に接続できない場合

- Windows のインストールが完了しているか確認（ブラウザで `http://localhost:8006`）
- ファイアウォールで port 5985 が開いているか確認
- `install.bat` が正常に実行されたか確認（RDP でログインして `C:\OEM\install.bat` を手動実行）
