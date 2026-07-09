@echo off
echo === Ansible WinRM Configuration ===
echo Configuring WinRM for Ansible remote management...

powershell.exe -ExecutionPolicy Bypass -File C:\OEM\ConfigureRemotingForAnsible.ps1 -SkipNetworkProfileCheck

echo === WinRM Configuration Complete ===
echo WinRM HTTP  : port 5985
echo WinRM HTTPS : port 5986
