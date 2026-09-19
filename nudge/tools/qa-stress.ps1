# Second-level stress test: point Nudge's real scheduler at HH:mm:ss windows a few seconds
# apart, then save timed full-screen frames so the result can be inspected without a human
# watching the screen. Settings and state are backed up and restored around the run.
param(
    [int]$Count = 8,
    [int]$Every = 2,
    [int]$Tail = 6,
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Debug\net10.0-windows10.0.19041.0\nudge.exe'),
    [string]$OutDir = (Join-Path $env:TEMP 'nudge-stress')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class Grab {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    // A DPI-unaware process gets a virtualized screen DC that omits layered windows entirely,
    // which once made a perfectly good reminder card look like it never appeared.
    public static void BecomeDpiAware() { SetProcessDpiAwarenessContext((IntPtr)(-4)); }
    public static void Full(string file) {
        Rectangle b = System.Windows.Forms.SystemInformation.VirtualScreen;
        using (Bitmap bmp = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppRgb)) {
            using (Graphics g = Graphics.FromImage(bmp)) {
                g.CopyFromScreen(b.X, b.Y, 0, 0, b.Size, CopyPixelOperation.SourceCopy);
            }
            bmp.Save(file, ImageFormat.Png);
        }
    }
}
'@
[Grab]::BecomeDpiAware()

$root = Join-Path $env:APPDATA 'Nudge'
$settingsPath = Join-Path $root 'settings.json'
$statePath = Join-Path $root 'state.json'
$logPath = Join-Path $root 'nudge.log'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-ChildItem $OutDir -Filter '*.png' -ErrorAction SilentlyContinue | Remove-Item -Force

$originalSettings = $null
$originalState = $null
if (Test-Path $settingsPath) { $originalSettings = Get-Content $settingsPath -Raw }
if (Test-Path $statePath) { $originalState = Get-Content $statePath -Raw }

try {
    Get-Process nudge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500

    $doc = $originalSettings | ConvertFrom-Json
    $windows = @()
    $start = (Get-Date).AddSeconds(3)
    for ($i = 1; $i -le $Count; $i++) {
        $at = $start.AddSeconds(($i - 1) * $Every).ToString('HH:mm:ss')
        $windows += [pscustomobject]@{ at = $at; label = "Sweep $i" }
    }
    $doc | Add-Member -NotePropertyName windows -NotePropertyValue $windows -Force
    # Today must be a work day or the scheduler stays silent.
    $dow = [int](Get-Date).DayOfWeek
    if ($dow -eq 0) { $dow = 7 }
    $days = @($doc.workDays)
    if ($days -notcontains $dow) { $days += $dow }
    $doc | Add-Member -NotePropertyName workDays -NotePropertyValue $days -Force

    $doc | ConvertTo-Json -Depth 6 | Set-Content $settingsPath -Encoding UTF8
    if (Test-Path $statePath) { Remove-Item $statePath -Force }
    "windows: $($windows.at -join ' ')  every ${Every}s"

    $logMark = 0
    if (Test-Path $logPath) { $logMark = (Get-Item $logPath).Length }

    Start-Process -FilePath $Exe | Out-Null
    $seconds = ($Count * $Every) + $Tail
    for ($i = 0; $i -le $seconds; $i++) {
        Start-Sleep -Seconds 1
        $p = Join-Path $OutDir ('frame-{0:d2}-{1}.png' -f $i, (Get-Date).ToString('HHmmss'))
        [Grab]::Full($p)
    }
    "captured $($seconds + 1) frames in $OutDir"

    Get-Process nudge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    if (Test-Path $logPath) {
        $fs = [System.IO.File]::Open($logPath, 'Open', 'Read', 'ReadWrite')
        try {
            [void]$fs.Seek($logMark, 'Begin')
            $sr = New-Object System.IO.StreamReader($fs)
            $sr.ReadToEnd() -split "`r?`n" | Where-Object { $_ -match 'Reminder|window|Nudge starting|ERROR' }
            $sr.Dispose()
        } finally { $fs.Dispose() }
    }
}
finally {
    if ($null -ne $originalSettings) { Set-Content $settingsPath -Value $originalSettings -Encoding UTF8 }
    if ($null -ne $originalState) { Set-Content $statePath -Value $originalState -Encoding UTF8 }
    Start-Process -FilePath $Exe | Out-Null
    "settings and state restored, Nudge running again"
}
