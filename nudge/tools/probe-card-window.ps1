# Self-service visual QA for the reminder card: proves whether the window exists, is visible,
# is cloaked by DWM, and what actually lands on the screen pixels.
param(
    [int]$Hold = 25,
    [string]$Exe = (Join-Path $PSScriptRoot '..\bin\Debug\net10.0-windows10.0.19041.0\nudge.exe'),
    [string]$OutDir = (Join-Path $env:TEMP 'nudge-card-probe'),
    [switch]$DpiAware
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-Process nudge -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400

Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public delegate bool EnumProc(IntPtr h, IntPtr l);
public static class Win {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", EntryPoint="GetWindowLong")] static extern int GetWindowLong32(IntPtr h, int i);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtr")] static extern IntPtr GetWindowLong64(IntPtr h, int i);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
    public static int ExStyle(IntPtr h) {
        if (IntPtr.Size == 8) return unchecked((int)(long)GetWindowLong64(h, -20));
        return GetWindowLong32(h, -20);
    }
    public struct RECT { public int Left, Top, Right, Bottom; }
    public static string Rect(IntPtr h) {
        RECT r; if (!GetWindowRect(h, out r)) return "n/a";
        return r.Left + "," + r.Top + " " + (r.Right - r.Left) + "x" + (r.Bottom - r.Top);
    }
    public static string Cloak(IntPtr h) {
        int v; int hr = DwmGetWindowAttribute(h, 14, out v, 4);
        if (hr != 0) return "err:" + hr.ToString("X8");
        return v.ToString();
    }
    public static void Shot(string path, int x, int y, int w, int hh) {
        using (Bitmap bmp = new Bitmap(w, hh)) {
            using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, hh)); }
            bmp.Save(path, ImageFormat.Png);
        }
    }
}
'@

$exeItem = Get-Item $Exe
if ($DpiAware) {
    # PER_MONITOR_AWARE_V2 = -4. Must run before this process touches the screen DC, otherwise
    # BitBlt hands back a DPI-virtualized (downscaled) desktop and coordinates lie.
    $ok = [Win]::SetProcessDpiAwarenessContext([IntPtr](-4))
    Write-Output "SetProcessDpiAwarenessContext(PMv2) -> $ok (last error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
}
$proc = Start-Process -FilePath $exeItem.FullName -ArgumentList '--debug-reminder', '--hold', "$Hold" -PassThru
Write-Output "pid=$($proc.Id)"
Start-Sleep -Seconds 3

$global:found = @()
$cb = [EnumProc] {
    param($h, $l)
    $p = [uint32]0
    [void][Win]::GetWindowThreadProcessId($h, [ref]$p)
    if ($p -eq [uint32]$proc.Id) {
        $sb = New-Object System.Text.StringBuilder 256
        [void][Win]::GetClassName($h, $sb, 256)
        $ex = [Win]::ExStyle($h)
        $global:found += [pscustomobject]@{
            Hwnd    = $h.ToInt64()
            Class   = $sb.ToString()
            Visible = [Win]::IsWindowVisible($h)
            Rect    = [Win]::Rect($h)
            ExStyle = '0x{0:X8}' -f $ex
            Layered = (($ex -band 0x80000) -ne 0)
            Topmost = (($ex -band 0x8) -ne 0)
            Cloaked = [Win]::Cloak($h)
        }
    }
    return $true
}
[void][Win]::EnumWindows($cb, [IntPtr]::Zero)

$found | Format-Table -AutoSize | Out-String -Width 220 | Write-Output

$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
Write-Output ("screen {0}x{1} at {2},{3}" -f $screen.Width, $screen.Height, $screen.X, $screen.Y)
$full = Join-Path $OutDir 'screen.png'
[Win]::Shot($full, $screen.X, $screen.Y, $screen.Width, $screen.Height)
Write-Output "wrote $full"

foreach ($f in $found) {
    $r = [Win]::Rect([IntPtr]$f.Hwnd)
    if ($r -notmatch '^(-?\d+),(-?\d+) (\d+)x(\d+)$') { continue }
    $w = [int]$Matches[3]; $hh = [int]$Matches[4]
    if ($w -lt 20 -or $hh -lt 20) { continue }
    $crop = Join-Path $OutDir ("crop-{0}.png" -f $f.Hwnd)
    [Win]::Shot($crop, [int]$Matches[1], [int]$Matches[2], $w, $hh)
    Write-Output "wrote $crop"
}
