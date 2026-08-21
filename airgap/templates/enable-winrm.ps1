# Windows WinRM 有効化スクリプト
# Airgap 環境で Ansible から WinRM 接続するための事前設定
# 管理者権限の PowerShell で実行してください
#
# 注意: 現在の Playbook は SSH 接続を使用しています。
#       WinRM 接続を使う場合のみ、このスクリプトを実行してください。
#       SSH 接続には enable-ssh.ps1 を使用してください。
#
# 使用方法:
#   Set-ExecutionPolicy RemoteSigned -Force
#   .\enable-winrm.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== WinRM 有効化スクリプト ===" -ForegroundColor Green
Write-Host ""

# WinRM サービスを有効化・起動
Write-Host "[1/5] WinRM サービスを設定中..."
Set-Service -Name WinRM -StartupType Automatic
Start-Service WinRM

# WinRM の基本設定
Write-Host "[2/5] WinRM リスナーを設定中..."
winrm quickconfig -force

# Basic 認証を有効化
Write-Host "[3/5] Basic 認証を有効化..."
winrm set winrm/config/service/auth '@{Basic="true"}'

# 暗号化なし通信を許可（airgap ローカル環境のため）
Write-Host "[4/5] 暗号化なし通信を許可..."
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# ファイアウォールルールを追加
Write-Host "[5/5] ファイアウォール設定中..."
$rule = Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" `
        -Direction Inbound `
        -LocalPort 5985 `
        -Protocol TCP `
        -Action Allow `
        -Profile Any
}

# LocalAccountTokenFilterPolicy を設定（リモート管理者アクセス用）
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$regName = "LocalAccountTokenFilterPolicy"
$existing = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
if (-not $existing -or $existing.$regName -ne 1) {
    New-ItemProperty -Path $regPath -Name $regName -Value 1 -PropertyType DWORD -Force | Out-Null
}

# 設定確認
Write-Host ""
Write-Host "=== 設定確認 ===" -ForegroundColor Green
winrm enumerate winrm/config/listener
Write-Host ""
Write-Host "WinRM 有効化が完了しました。" -ForegroundColor Green
Write-Host ""
Write-Host "Ansible 接続テスト:" -ForegroundColor Yellow
Write-Host "  ansible win-target -m ansible.windows.win_ping -c winrm" -ForegroundColor Yellow
