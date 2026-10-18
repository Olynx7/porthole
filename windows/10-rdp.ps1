# 10-rdp.ps1 - make Remote Desktop usable from the host.
# tiny10 keeps the RDP stack, but the listener, the firewall rule and the
# session policies are all off by default.

$OemDir = Split-Path -Parent $PSCommandPath
. (Join-Path $OemDir 'lib\common.ps1')

Write-PortholeLog 'stage: rdp'
Set-PortholeStage -Stage 'rdp'

$ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$tcp = "$ts\WinStations\RDP-Tcp"

Set-RegValue -Path $ts -Name 'fDenyTSConnections' -Value 0
Set-RegValue -Path $ts -Name 'fSingleSessionPerUser' -Value 1
Set-RegValue -Path $ts -Name 'fAutoReboot' -Value 0

# SecurityLayer 2 = TLS, UserAuthentication 0 = no NLA.
# TLS without NLA is the combination FreeRDP handles most reliably.
Set-RegValue -Path $tcp -Name 'SecurityLayer' -Value 2
Set-RegValue -Path $tcp -Name 'UserAuthentication' -Value 0
Set-RegValue -Path $tcp -Name 'MinEncryptionLevel' -Value 3
Set-RegValue -Path $tcp -Name 'MaxDisconnectionTime' -Value 60000
Set-RegValue -Path $tcp -Name 'MaxIdleTime' -Value 0
Set-RegValue -Path $tcp -Name 'MaxConnectionTime' -Value 0

# Keep the clock sane after long pauses and avoid the "select a session"
# dialog on reconnect.
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fResetBroken' -Value 1

Set-Service -Name TermService -StartupType Automatic
Start-Service TermService
Write-PortholeLog 'TermService started'

try {
    Get-NetFirewallRule -Name 'RemoteDesktop-UserMode-In-TCP' -ErrorAction Stop |
        Enable-NetFirewallRule | Out-Null
    Write-PortholeLog 'firewall rule enabled'
} catch {
    Write-PortholeLog "could not enable the RDP firewall rule: $($_.Exception.Message)"
}

try {
    net localgroup "Remote Desktop Users" "$env:USERNAME" /add 2>&1 | Out-Null
} catch {
    Write-PortholeLog 'user already in Remote Desktop Users'
}

# No sleep, no hibernate, no monitor blanking: a paused VM must come back
# exactly where it was.
& powercfg /change monitor-timeout-ac 0
& powercfg /change standby-timeout-ac 0
& powercfg /change hibernate-timeout-ac 0
& powercfg /change disk-timeout-ac 0
& powercfg /hibernate off

# Fast startup confuses ACPI shutdown from the container.
Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
    -Name 'HiberbootEnabled' -Value 0

Write-PortholeLog 'rdp configured'
