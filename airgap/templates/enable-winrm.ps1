# Windows WinRM 有効化スクリプト
# Airgap環境でAnsibleから接続するための事前設定
# 管理者権限のPowerShellで実行してください
#
# 使用方法:
#   Set-ExecutionPolicy RemoteSigned -Force
#   .\enable-winrm.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== WinRM 有効化スクリプト ===" -ForegroundColor Green

# WinRM サービスを有効化・起動
Write-Host "WinRM サービスを設定中..."
Set-Service -Name WinRM -StartupType Automatic
Start-Service WinRM

# WinRM の基本設定
Write-Host "WinRM リスナーを設定中..."
winrm quickconfig -force

# Basic 認証を有効化
Write-Host "Basic 認証を有効化..."
winrm set winrm/config/service/auth '@{Basic="true"}'

# 暗号化なし通信を許可（airgapローカル環境のため）
Write-Host "暗号化なし通信を許可..."
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# ファイアウォールルールを追加
Write-Host "ファイアウォール設定中..."
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
Write-Host "LocalAccountTokenFilterPolicy を設定..."
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
Write-Host "Ansible から接続テスト:" -ForegroundColor Yellow
Write-Host "  ansible win-target -m ansible.windows.win_ping" -ForegroundColor Yellow
