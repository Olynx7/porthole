# 20-desktop.ps1 - make the guest desktop get out of the way.
# Everything here is cosmetic and reversible; set desktop.tweaks = false in
# the profile to skip the whole file.

$OemDir = Split-Path -Parent $PSCommandPath
. (Join-Path $OemDir 'lib\common.ps1')

$settings = Get-PortholeSettings
if (-not $settings.desktop_tweaks) {
    Write-PortholeLog 'desktop tweaks disabled - skipping'
    exit 0
}

Write-PortholeLog 'stage: desktop'
Set-PortholeStage -Stage 'desktop'

# explorer.exe writes StuckRects3 back on exit, so it has to be down
# *before* we change the taskbar settings, not after.
try {
    Stop-Process -Name explorer -Force -ErrorAction Stop
    Start-Sleep -Seconds 3
    Write-PortholeLog 'explorer stopped'
} catch {
    Write-PortholeLog 'explorer was not running'
}

$explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$advanced = "$explorer\Advanced"

# Hide desktop icons and disable the "show desktop" corner.
Set-RegValue -Path $advanced -Name 'HideIcons' -Value 1
Set-RegValue -Path $advanced -Name 'TaskbarGlomLevel' -Value 2
Set-RegValue -Path "$explorer\HideDesktopIcons\NewStartPanel" `
    -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Value 1

# Remove the search box and the task view button.
Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' `
    -Name 'SearchboxTaskbarMode' -Value 0

# Plain black wallpaper: if it ever shows through, it reads as a background,
# not as a Windows desktop.
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -Value '' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Colors' -Name 'Background' -Value '0 0 0' -Type String

# No screen saver, no lock screen, no "welcome" transition.
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveActive' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaverIsSecure' -Value '0' -Type String
Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaverTimeout' -Value '0' -Type String
Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' `
    -Name 'NoLockScreen' -Value 1
Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' `
    -Name 'DisableLockWorkstation' -Value 1

# DPI: the client renders at monitor pixels, so the guest has to scale up.
$dpi = [int]$settings.display.dpi_scale
if ($dpi -ge 100 -and $dpi -le 400) {
    $logpixels = [int]($dpi * 96 / 100)
    Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'LogPixels' -Value $logpixels
    Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'Win8DpiScaling' -Value 1
    Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'DesktopDPIOverride' -Value 0
    Write-PortholeLog "dpi set to $dpi percent (LogPixels=$logpixels)"
}

# Auto-hide the taskbar: byte 8 of the StuckRects3 blob carries the flags,
# 0x03 = always auto-hide.
$stuckPath = "$explorer\StuckRects3"
if (-not (Test-Path $stuckPath)) {
    New-Item -Path $stuckPath -Force | Out-Null
}
$blob = (Get-ItemProperty -Path $stuckPath -Name 'Settings' -ErrorAction SilentlyContinue).Settings
if (-not $blob -or $blob.Length -lt 12) {
    # A brand new profile has no StuckRects3 yet; the taskbar picks its
    # defaults up from this blob, so build one with auto-hide set.
    $blob = New-Object byte[] 40
}
$blob[8] = 3
Set-ItemProperty -Path $stuckPath -Name 'Settings' -Value $blob -Type Binary
Write-PortholeLog ("taskbar auto-hide set (blob {0} bytes)" -f $blob.Length)

# Bring the shell back with the new settings loaded.
Start-Process -FilePath 'explorer.exe'
Start-Sleep -Seconds 5

try {
    Add-Type -Namespace Porthole -Name Shell -MemberDefinition @'
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@ -ErrorAction Stop
    [Porthole.Shell]::SystemParametersInfo(20, 0, '', 0x01 -bor 0x02) | Out-Null
} catch {
    Write-PortholeLog "could not refresh system parameters: $($_.Exception.Message)"
}

Write-PortholeLog 'desktop configured'
