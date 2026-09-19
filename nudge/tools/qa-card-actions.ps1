# Drives one reminder card from the real scheduler and presses a button on it through UI
# Automation, so "does acknowledging work end to end" is answered without a human at the keyboard.
param(
    [ValidateSet('ack', 'pause', 'dismiss')] [string]$Action = 'ack',
    [int]$LeadSeconds = 4,
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Debug\net10.0-windows10.0.19041.0\nudge.exe'),
    [string]$OutDir = (Join-Path $env:TEMP 'nudge-card-actions')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, UIAutomationClient, UIAutomationTypes
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @'
using System;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public delegate bool EnumProc2(IntPtr h, IntPtr l);
public static class Win2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc2 cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public static void Aware() { SetProcessDpiAwarenessContext((IntPtr)(-4)); }
    public static void Shot(string file) {
        Rectangle b = System.Windows.Forms.SystemInformation.VirtualScreen;
        using (Bitmap bmp = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppRgb)) {
            using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(b.X, b.Y, 0, 0, b.Size); }
            bmp.Save(file, ImageFormat.Png);
        }
    }
}
'@
[Win2]::Aware()

$root = Join-Path $env:APPDATA 'Nudge'
$settingsPath = Join-Path $root 'settings.json'
$statePath = Join-Path $root 'state.json'
$logPath = Join-Path $root 'nudge.log'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$originalSettings = $null
$originalState = $null
if (Test-Path $settingsPath) { $originalSettings = Get-Content $settingsPath -Raw }
if (Test-Path $statePath) { $originalState = Get-Content $statePath -Raw }

function Find-CardWindow([int]$processId) {
    $global:cardHwnd = [IntPtr]::Zero
    $cb = [EnumProc2] {
        param($h, $l)
        $p = [uint32]0
        [void][Win2]::GetWindowThreadProcessId($h, [ref]$p)
        if ($p -eq [uint32]$processId -and [Win2]::IsWindowVisible($h)) {
            $sb = New-Object System.Text.StringBuilder 256
            [void][Win2]::GetClassName($h, $sb, 256)
            if ($sb.ToString().StartsWith('HwndWrapper[nudge')) { $global:cardHwnd = $h }
        }
        return $true
    }
    [void][Win2]::EnumWindows($cb, [IntPtr]::Zero)
    return $global:cardHwnd
}

function Invoke-CardButton([int]$processId, [System.Windows.Automation.Condition]$which, [string]$label) {
    $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
    $byPid = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $processId)
    $win = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $byPid)
    if ($null -eq $win) { throw 'card window not found through UIA' }
    $btn = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $which)
    if ($null -eq $btn) { throw "button '$label' not found in the card" }
    $pattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
    "invoked '$label'"
}

function By-Name([string]$value) {
    New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $value)
}

function By-AutomationId([string]$value) {
    New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $value)
}

try {
    Get-Process nudge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500

    $doc = $originalSettings | ConvertFrom-Json
    $at = (Get-Date).AddSeconds($LeadSeconds).ToString('HH:mm:ss')
    $doc | Add-Member -NotePropertyName windows -NotePropertyValue @(
        [pscustomobject]@{ at = $at; label = 'Action probe' }) -Force
    $dow = [int](Get-Date).DayOfWeek
    if ($dow -eq 0) { $dow = 7 }
    $days = @($doc.workDays)
    if ($days -notcontains $dow) { $days += $dow }
    $doc | Add-Member -NotePropertyName workDays -NotePropertyValue $days -Force
    $doc | ConvertTo-Json -Depth 6 | Set-Content $settingsPath -Encoding UTF8
    if (Test-Path $statePath) { Remove-Item $statePath -Force }
    "due at $at, action=$Action"

    $logMark = 0
    if (Test-Path $logPath) { $logMark = (Get-Item $logPath).Length }

    $proc = Start-Process -FilePath $Exe -PassThru
    $deadline = (Get-Date).AddSeconds($LeadSeconds + 15)
    $hwnd = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        $hwnd = Find-CardWindow $proc.Id
        if ($hwnd -ne [IntPtr]::Zero) { break }
    }
    if ($hwnd -eq [IntPtr]::Zero) { throw 'no reminder card appeared' }
    "card window present"
    [Win2]::Shot((Join-Path $OutDir 'before.png'))

    switch ($Action) {
        'ack' { Invoke-CardButton $proc.Id (By-Name 'Mark as seen') 'Mark as seen' }
        'pause' { Invoke-CardButton $proc.Id (By-Name 'Pause today') 'Pause today' }
        'dismiss' { Invoke-CardButton $proc.Id (By-AutomationId 'CloseButton') 'close' }
    }

    Start-Sleep -Seconds 2
    $still = Find-CardWindow $proc.Id
    "card window after click: $(if ($still -eq [IntPtr]::Zero) { 'gone' } else { 'STILL OPEN' })"
    [Win2]::Shot((Join-Path $OutDir 'after.png'))
    if (Test-Path $statePath) { "state.json: `n$((Get-Content $statePath -Raw) -replace '\s+', ' ')" }

    Get-Process nudge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    if (Test-Path $logPath) {
        $fs = [System.IO.File]::Open($logPath, 'Open', 'Read', 'ReadWrite')
        try {
            [void]$fs.Seek($logMark, 'Begin')
            $sr = New-Object System.IO.StreamReader($fs)
            $sr.ReadToEnd() -split "`r?`n" | Where-Object { $_ -match 'Reminder|Acknowledged|Paused|ERROR' }
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
