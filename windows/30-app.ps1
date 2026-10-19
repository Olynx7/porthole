# 30-app.ps1 - install the application and make it start maximised on login.

$OemDir = Split-Path -Parent $PSCommandPath
. (Join-Path $OemDir 'lib\common.ps1')

$settings = Get-PortholeSettings
$app = $settings.app
$exe = $app.exe
$installerName = $app.installer

Write-PortholeLog 'stage: app'
Set-PortholeStage -Stage 'app'

function Find-Installer {
    param([string]$Name)
    if (-not $Name) { return $null }
    $candidates = @(
        (Join-Path $OemDir $Name),
        "\\host.lan\Data\$Name",
        "Z:\$Name"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Resolve-AppExe {
    param([string]$Preferred)
    if ($Preferred -and (Test-Path $Preferred)) { return $Preferred }

    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        $entry = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'WeCom|WXWork' } |
            Select-Object -First 1
        if ($entry -and $entry.InstallLocation) {
            $candidate = Join-Path $entry.InstallLocation 'WXWork.exe'
            if (Test-Path $candidate) { return $candidate }
        }
    }

    foreach ($root in @('C:\Program Files (x86)\WXWork', 'C:\Program Files\WXWork')) {
        $candidate = Join-Path $root 'WXWork.exe'
        if (Test-Path $candidate) { return $candidate }
    }

    return $Preferred
}

if (Test-Path $exe) {
    Write-PortholeLog "$exe already present - skipping the installer"
} elseif (-not $installerName) {
    Write-PortholeLog 'no installer configured - nothing to install'
} else {
    $installer = Find-Installer -Name $installerName
    if (-not $installer) {
        Write-PortholeLog "installer $installerName not found yet - waiting for the share"
        # The SMB share can take a moment to come up during first logon.
        $deadline = (Get-Date).AddSeconds(180)
        while (-not $installer -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 10
            $installer = Find-Installer -Name $installerName
        }
    }

    if ($installer) {
        $arguments = @($app.install_args)
        # Copy it locally first: running an .exe straight off the SMB share
        # triggers the "Open File - Security Warning" dialog, which blocks a
        # silent install forever.
        $local = Join-Path $env:TEMP ("porthole-" + $installerName)
        Copy-Item -LiteralPath $installer -Destination $local -Force
        Unblock-File -Path $local -ErrorAction SilentlyContinue
        Write-PortholeLog "installing $local with arguments: $($arguments -join ' ')"
        $process = Start-Process -FilePath $local -ArgumentList $arguments -PassThru
        Write-PortholeLog "installer started (pid $($process.Id))"

        $deadline = (Get-Date).AddMinutes(30)
        while (-not (Test-Path $exe) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 10
        }

        if (Test-Path $exe) {
            Write-PortholeLog "install finished: $exe"
        } else {
            Write-PortholeLog 'installer did not produce the expected executable'
            if (-not $process.HasExited) {
                Write-PortholeLog "installer is still running (pid $($process.Id))"
            } else {
                Write-PortholeLog "installer exit code: $($process.ExitCode)"
            }
        }
    } else {
        Write-PortholeLog "giving up on $installerName - install it later with 'porthole shell'"
    }
}

# Start the app at login, maximised.
if ((Test-Path $exe) -and $app.startup) {
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    $shortcutPath = Join-Path $startup ("{0}.lnk" -f $app.alias)
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exe
    $shortcut.WorkingDirectory = Split-Path -Parent $exe
    $shortcut.WindowStyle = 3
    $shortcut.Description = 'Started by porthole'
    $shortcut.Save()
    Write-PortholeLog "startup shortcut created: $shortcutPath"

    # Keep the app filling the desktop, even when the RDP session changes the
    # screen resolution after the app has started.
    $fitPath = Join-Path $startup 'porthole-fit.lnk'
    $fit = $wsh.CreateShortcut($fitPath)
    $fit.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $fit.Arguments = '-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\OEM\40-fit.ps1"'
    $fit.WindowStyle = 7
    $fit.Save()
    Write-PortholeLog "fit watcher shortcut created: $fitPath"
}

$exe = Resolve-AppExe -Preferred $exe
if (Test-Path $exe) {
    Set-PortholeStage -Stage 'done'
    Write-PortholeLog 'provisioning complete'
} else {
    Set-PortholeStage -Stage 'failed' -Ok $false
    Write-PortholeLog 'provisioning finished without the application - marking as failed'
    exit 1
}
