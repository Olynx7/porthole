# 40-fit.ps1 - keep the application filling the desktop.
#
# Windows does not re-maximise an application when the RDP session changes the
# screen resolution, so the app can end up as a small window in the corner of a
# much larger desktop. This watches the process and re-maximises it whenever the
# window no longer matches the screen.

$code = @"
using System;
using System.Runtime.InteropServices;

public class Fit {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
"@

Add-Type -TypeDefinition $code

$processName = 'WXWork'
$screenWidth = [Fit]::GetSystemMetrics(0)
$screenHeight = [Fit]::GetSystemMetrics(1)
Write-Host ("screen: {0}x{1}" -f $screenWidth, $screenHeight)

while ($true) {
    $app = Get-Process -Name $processName -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1

    if ($app) {
        $rect = New-Object Fit+RECT
        if ([Fit]::GetWindowRect($app.MainWindowHandle, [ref]$rect)) {
            $width = $rect.Right - $rect.Left
            $height = $rect.Bottom - $rect.Top
            $screenWidth = [Fit]::GetSystemMetrics(0)
            $screenHeight = [Fit]::GetSystemMetrics(1)
            if ($width -lt $screenWidth -or $height -lt $screenHeight) {
                Write-Host ("refit {0}x{1} -> {2}x{3}" -f $width, $height, $screenWidth, $screenHeight)
                [Fit]::ShowWindow($app.MainWindowHandle, 3) | Out-Null
            }
        }
    }

    Start-Sleep -Seconds 5
}
