#Requires -Version 5.1
<#
.SYNOPSIS
    Remove every trace of Nudge from this machine: user settings and the autostart entry.

.DESCRIPTION
    Nudge writes exactly three things outside its own folder:

        %APPDATA%\Nudge\
            settings.json, state.json, nudge.log (plus nudge.log.old when it rotates past
            512 KB). May also hold hand-made backups and a legacy\ folder from an earlier
            layout - everything in there goes.

        HKCU\Software\Microsoft\Windows\CurrentVersion\Run  value "Nudge"
            the autostart entry added by AutoStart.cs.

        %TEMP%\.net\nudge\
            native libraries the self-contained single-file bundle unpacks on first run.

    This removes those three and nothing else. It does not delete the program itself - remove
    the exe by hand - and it never touches the source tree.

    The settings folder is moved aside rather than deleted, to
    %APPDATA%\Nudge.backup-<timestamp>. A reset you regret is worse than one folder you did not
    ask for, and the app only ever reads %APPDATA%\Nudge, so the backup is inert. Pass -Purge to
    delete it outright instead.

    A running Nudge is stopped first: it rewrites state.json as it runs, so resetting under a
    live instance leaves a half-reset folder behind. That is what -KeepRunning disables.

    The registry value is not gone for good - App.EnsureAutoStart re-adds it on the next normal
    launch. Delete the exe as well if you want autostart to stay away.

    -WhatIf prints the whole plan and changes nothing.

    To run it unattended, use -Force. Do not use -Confirm:$false for that: launched through
    "powershell -File", every argument is handed over as a literal string, so -Confirm:$false
    arrives as the string "$false" and the script refuses to start. (-Confirm:$false does work
    when you invoke the script from inside a PowerShell session.)

.PARAMETER Purge
    Delete the settings folder instead of keeping a timestamped backup.

.PARAMETER KeepRunning
    Do not stop a running Nudge. Expect the delete to fail on a locked file.

.PARAMETER Force
    Do not ask for confirmation. The unattended equivalent of answering "yes to all".

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\reset.ps1 -WhatIf

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\reset.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\reset.ps1 -Purge -Force
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Purge,
    [switch]$KeepRunning,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Force) { $ConfirmPreference = 'None' }

$configRoot = Join-Path $env:APPDATA 'Nudge'
$runKey     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValue   = 'Nudge'
# Where the single-file host unpacks the native libraries it carries. The folder is named
# after the assembly, so it is always "...\.net\nudge".
$extractRoot = Join-Path $env:TEMP '.net\nudge'

$backupPath = $null

Write-Host 'Nudge reset'
Write-Host ''
Write-Host 'found:'

if (Test-Path -LiteralPath $configRoot) {
    $all = @(Get-ChildItem -LiteralPath $configRoot -Recurse -Force -File -ErrorAction SilentlyContinue)
    $sum = ($all | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }
    Write-Host ("  settings {0}" -f $configRoot)
    # Everything below is computed into a variable before it is formatted on purpose: the comma
    # operator binds tighter than arithmetic, so "-f $name, $bytes / 1KB" silently parses as
    # "($name, $bytes) / 1KB" and dies trying to divide an array.
    foreach ($entry in (Get-ChildItem -LiteralPath $configRoot -Force)) {
        $name = $entry.Name
        if ($entry.PSIsContainer) {
            $inner = @(Get-ChildItem -LiteralPath $entry.FullName -Recurse -Force -File -ErrorAction SilentlyContinue)
            $kb = ($inner | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $kb) { $kb = 0 }
            Write-Host ("             {0,-38} {1,8:N0} KB  (folder, {2} files)" -f $name, ($kb / 1KB), $inner.Count)
        } else {
            Write-Host ("             {0,-38} {1,8:N0} KB" -f $name, ($entry.Length / 1KB))
        }
    }
    Write-Host ("             {0,-38} {1,8:N0} KB  total" -f '', ($sum / 1KB))
} else {
    Write-Host ("  settings {0}  (absent)" -f $configRoot)
}

$stored = $null
try { $stored = (Get-ItemProperty -Path $runKey -Name $runValue -ErrorAction Stop).$runValue } catch { $stored = $null }
if ($stored) {
    $stale = if (Test-Path -LiteralPath $stored.Trim('"')) { 'path exists' } else { 'path is already stale' }
    Write-Host ("  autostart HKCU Run value `"{0}`" = {1}  ({2})" -f $runValue, $stored, $stale)
} else {
    Write-Host ("  autostart no HKCU Run value named `"{0}`"" -f $runValue)
}

if (Test-Path -LiteralPath $extractRoot) {
    $sum = (Get-ChildItem -LiteralPath $extractRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    Write-Host ("  temp    {0}  ({1:N1} MB of unpacked runtime)" -f $extractRoot, ($sum / 1MB))
} else {
    Write-Host ("  temp    {0}  (absent)" -f $extractRoot)
}

$running = @(Get-Process -Name nudge -ErrorAction SilentlyContinue)
Write-Host ("  process {0}" -f $(if ($running.Count) { "$($running.Count) running instance(s)" } else { 'not running' }))

Write-Host ''
Write-Host 'removing:'

if ($running.Count) {
    if ($KeepRunning) {
        Write-Warning 'Nudge is still running (-KeepRunning); deleting its files may well fail.'
    } elseif ($PSCmdlet.ShouldProcess("$($running.Count) running nudge process(es)", 'stop')) {
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 600
        Write-Host '  stopped the running instance(s)'
    }
}

if ($stored) {
    # Remove the value, never the key: the Run key is Windows' and holds every other app's
    # autostart entry too.
    if ($PSCmdlet.ShouldProcess("$runKey\$runValue", 'remove autostart entry')) {
        Remove-ItemProperty -Path $runKey -Name $runValue -ErrorAction SilentlyContinue
        Write-Host ("  removed HKCU Run value `"{0}`"" -f $runValue)
    }
}

if (Test-Path -LiteralPath $configRoot) {
    if ($Purge) {
        if ($PSCmdlet.ShouldProcess($configRoot, 'delete settings folder')) {
            Remove-Item -LiteralPath $configRoot -Recurse -Force
            Write-Host ("  deleted {0}" -f $configRoot)
        }
    } else {
        # Two resets inside the same second would collide; nudge the name until it is free.
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = "$configRoot.backup-$stamp"
        $n = 1
        while (Test-Path -LiteralPath $backupPath) { $backupPath = "$configRoot.backup-$stamp-$n"; $n++ }
        if ($PSCmdlet.ShouldProcess($configRoot, "move settings aside to $backupPath")) {
            Move-Item -LiteralPath $configRoot -Destination $backupPath -Force
            Write-Host ("  moved {0}" -f $configRoot)
            Write-Host ("     to {0}" -f $backupPath)
        }
    }
}

if (Test-Path -LiteralPath $extractRoot) {
    if ($PSCmdlet.ShouldProcess($extractRoot, 'delete unpacked runtime')) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ("  deleted {0}" -f $extractRoot)
    }
}

Write-Host ''
if ($WhatIfPreference) {
    Write-Host 'nothing was changed (-WhatIf).'
} else {
    Write-Host 'done. Nudge seeds a fresh settings.json the next time it runs.'
    if ($backupPath) { Write-Host "your previous settings are still at $backupPath" }
    if ($Purge)      { Write-Host 'the settings folder was purged, not backed up.' }
    Write-Host 'the program itself is untouched - delete the exe by hand to uninstall.'
}
