# common.ps1 - shared helpers for the porthole provisioning scripts.
# PowerShell 5.1 syntax only, ASCII only, CRLF line endings.
$ErrorActionPreference = 'Stop'

if (-not $OemDir) {
    $OemDir = $PSScriptRoot | Split-Path -Parent
}

function Write-PortholeLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    try {
        Add-Content -Path (Join-Path $OemDir 'porthole.log') -Value $line -Encoding ASCII
    } catch {
        # logging must never break provisioning
    }
}

function Get-PortholeSettings {
    $path = Join-Path $OemDir 'settings.json'
    if (-not (Test-Path $path)) {
        throw "missing $path - was the OEM folder rendered correctly?"
    }
    return (Get-Content -Raw -Path $path | ConvertFrom-Json)
}

function Set-PortholeStage {
    param(
        [string]$Stage,
        [bool]$Ok = $true
    )
    $payload = @{
        stage = $Stage
        ok    = $Ok
        time  = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress

    Set-Content -Path (Join-Path $OemDir 'status.json') -Value $payload -Encoding ASCII

    $share = '\\host.lan\Data\porthole-status.json'
    try {
        Set-Content -Path $share -Value $payload -Encoding ASCII -ErrorAction Stop
    } catch {
        Write-PortholeLog "status not published to share: $($_.Exception.Message)"
    }
}

function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Wait-PortholePath {
    param(
        [string]$Path,
        [int]$TimeoutSeconds = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $Path) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}
