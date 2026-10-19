# 50-shell.ps1 - optionally replace the Windows shell with the application.
#
# Windows keeps showing its taskbar no matter how the auto-hide registry is
# poked, so the only reliable way to get a taskbar-free screen is to not start
# explorer at all: the application becomes the shell.

$OemDir = Split-Path -Parent $PSCommandPath
. (Join-Path $OemDir 'lib\common.ps1')

$settings = Get-PortholeSettings
$mode = $settings.session.shell
Write-PortholeLog "stage: shell ($mode)"

if ($mode -ne 'app') {
    Write-PortholeLog 'shell mode is explorer - nothing to do'
    exit 0
}

$launcher = Join-Path $OemDir 'session.cmd'
$lines = @(
    '@echo off',
    'start "" "{0}"' -f $settings.app.exe,
    'start "" /min powershell -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\OEM\40-fit.ps1"'
)
Set-Content -Path $launcher -Value $lines -Encoding ASCII

Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' `
    -Name 'Shell' -Value $launcher -Type String

Write-PortholeLog "shell replaced with $launcher"
