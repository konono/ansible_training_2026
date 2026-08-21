# Windows OpenSSH Server 有効化スクリプト
# Airgap 環境で Ansible から SSH 接続するための事前設定
# 管理者権限の PowerShell で実行してください
#
# 現在の Playbook は SSH 接続を標準としています。
# cocoonstack イメージでは OpenSSH が事前設定済みのため、
# 通常このスクリプトの実行は不要です。
#
# 使用方法:
#   Set-ExecutionPolicy RemoteSigned -Force
#   .\enable-ssh.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== OpenSSH Server 有効化スクリプト ===" -ForegroundColor Green
Write-Host ""

# OpenSSH Server のインストール確認
Write-Host "[1/5] OpenSSH Server の確認..."
$sshCapability = Get-WindowsCapability -Online -Name "OpenSSH.Server*"
if ($sshCapability.State -ne "Installed") {
    Write-Host "  OpenSSH Server をインストール中..."
    Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0"
    Write-Host "  インストール完了"
} else {
    Write-Host "  既にインストール済み"
}

# sshd サービスを有効化・起動
Write-Host "[2/5] sshd サービスを設定中..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# デフォルトシェルを PowerShell に変更
# Ansible の ansible.windows.* モジュールは PowerShell を必要とする
Write-Host "[3/5] デフォルトシェルを PowerShell に設定..."
$shellPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$regPath = "HKLM:\SOFTWARE\OpenSSH"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
New-ItemProperty -Path $regPath -Name DefaultShell -Value $shellPath -PropertyType String -Force | Out-Null
Write-Host "  DefaultShell = $shellPath"

# ファイアウォールルールを追加
Write-Host "[4/5] ファイアウォール設定中..."
$rule = Get-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" `
        -Direction Inbound `
        -LocalPort 22 `
        -Protocol TCP `
        -Action Allow `
        -Profile Any
    Write-Host "  ファイアウォールルールを追加しました"
} else {
    Write-Host "  ファイアウォールルールは既に存在します"
}

# ssh-agent サービスを有効化（オプション）
Write-Host "[5/5] ssh-agent サービスを設定中..."
$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agent) {
    Set-Service -Name ssh-agent -StartupType Automatic
    Start-Service ssh-agent -ErrorAction SilentlyContinue
    Write-Host "  ssh-agent を有効化しました"
} else {
    Write-Host "  ssh-agent は利用できません（スキップ）"
}

# 設定確認
Write-Host ""
Write-Host "=== 設定確認 ===" -ForegroundColor Green
$sshdStatus = Get-Service sshd | Select-Object -ExpandProperty Status
$defaultShell = (Get-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
Write-Host "  sshd サービス:    $sshdStatus"
Write-Host "  デフォルトシェル: $defaultShell"
Write-Host "  SSH ポート:       22"
Write-Host ""
Write-Host "OpenSSH Server の有効化が完了しました。" -ForegroundColor Green
Write-Host ""
Write-Host "Ansible 接続テスト:" -ForegroundColor Yellow
Write-Host "  ansible win-target -m ansible.windows.win_ping -c ssh" -ForegroundColor Yellow
Write-Host ""
Write-Host "Ansible inventory 設定例:" -ForegroundColor Yellow
Write-Host "  ansible_connection: ssh" -ForegroundColor Yellow
Write-Host "  ansible_port: 22" -ForegroundColor Yellow
Write-Host "  ansible_shell_type: powershell" -ForegroundColor Yellow
