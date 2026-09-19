#Requires -Version 5.1
<#
.SYNOPSIS
    Delete everything the build generated, and nothing else.

.DESCRIPTION
    Removes:
        nudge\bin\      compiler output (Debug and Release, every RID)
        nudge\obj\      intermediates: generated .g.cs, BAML, restore state
        dist\           the publish output (override with -OutputDir)
        .vs\            IDE scratch state (skip with -KeepIdeState)

    Keeps, deliberately:
        every source file - *.cs, *.xaml, *.csproj, *.slnx, Assets\*.ico, tools\*.ps1
        nudge\nudge.csproj.user    the IDE's debug-launch profile; hand-kept, not a build product
        .workbuddy\                project notes
        %APPDATA%\Nudge\           user settings - that is reset.ps1's job, not this one's

    Nothing here is irreplaceable: the whole cost of running it is one rebuild. -WhatIf prints
    the plan and deletes nothing.

.PARAMETER OutputDir
    The publish output to remove. Default: <repo>\dist. If you published somewhere else, point
    this at it. A path outside the repo is accepted only when you pass it explicitly, and the
    usual user folders are refused outright.

.PARAMETER KeepIdeState
    Leave .vs alone (it holds open-document and window-layout state).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\clean.ps1 -WhatIf

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\clean.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [string]$OutputDir,
    [switch]$KeepIdeState
)

$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $PSScriptRoot          # <repo>\nudge
$repoRoot   = Split-Path -Parent $projectDir            # <repo>

if (-not (Test-Path -LiteralPath (Join-Path $projectDir 'nudge.csproj'))) {
    throw "nudge.csproj not found under $projectDir - this script expects to sit in <repo>\nudge\tools."
}

$outputWasGiven = $PSBoundParameters.ContainsKey('OutputDir')
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot 'dist' }
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

$repoFull  = ([System.IO.Path]::GetFullPath($repoRoot)).TrimEnd('\')
$driveRoot = ([System.IO.Path]::GetPathRoot($repoFull)).TrimEnd('\')
$personal  = @(
    $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA,
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'Documents'),
    (Join-Path $env:USERPROFILE 'Downloads')
) | Where-Object { $_ } | ForEach-Object { ([System.IO.Path]::GetFullPath($_)).TrimEnd('\') }

# A guard, not decoration: the four paths below are computed, but -OutputDir is not, and a
# typo there must not turn "clean" into "delete something that matters".
function Assert-Deletable([string]$path, [bool]$explicitOutside) {
    $full = ([System.IO.Path]::GetFullPath($path)).TrimEnd('\')
    if ($full -ieq $driveRoot) { throw "refusing to delete a drive root: $full" }
    if ($full -ieq $repoFull) { throw "refusing to delete the repo root: $full" }
    foreach ($p in $personal) {
        if ($full -ieq $p) { throw "refusing to delete $full - that is a user folder, not a build artifact" }
    }
    if ($repoFull.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing to delete $full - it contains the project."
    }
    if ($full.StartsWith($repoFull + '\', [StringComparison]::OrdinalIgnoreCase)) { return }
    if (-not $explicitOutside) {
        throw "refusing to delete $full - it is outside the project ($repoFull)."
    }
    Write-Warning "removing $full, which is outside the project"
}

$targets = @(
    [pscustomobject]@{ Label = 'bin';  Path = (Join-Path $projectDir 'bin'); Explicit = $false }
    [pscustomobject]@{ Label = 'obj';  Path = (Join-Path $projectDir 'obj'); Explicit = $false }
    [pscustomobject]@{ Label = 'dist'; Path = $OutputDir;                    Explicit = $outputWasGiven }
)
if (-not $KeepIdeState) {
    $targets += [pscustomobject]@{ Label = '.vs'; Path = (Join-Path $repoRoot '.vs'); Explicit = $false }
}

Write-Host "clean: $repoFull"
Write-Host ''

$freed = 0
$removed = 0
$failed = @()

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Path)) {
        Write-Host ("  {0,-5} absent   {1}" -f $t.Label, $t.Path)
        continue
    }

    Assert-Deletable $t.Path ([bool]$t.Explicit)

    $sum = (Get-ChildItem -LiteralPath $t.Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }

    if (-not $PSCmdlet.ShouldProcess($t.Path, "remove $($t.Label)")) {
        Write-Host ("  {0,-5} planned  {1}   ({2:N1} MB)" -f $t.Label, $t.Path, ($sum / 1MB))
        continue
    }

    try {
        Remove-Item -LiteralPath $t.Path -Recurse -Force -ErrorAction Stop
        $freed += $sum
        $removed++
        Write-Host ("  {0,-5} removed  {1}   ({2:N1} MB)" -f $t.Label, $t.Path, ($sum / 1MB))
    } catch {
        # Usually a running IDE holding a file open. Report it and keep going: one locked
        # folder must not hide the state of the others.
        $failed += $t.Label
        Write-Warning "could not fully remove $($t.Path): $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host ("freed {0:N1} MB from {1} folder(s)" -f ($freed / 1MB), $removed)
Write-Host 'kept: sources, Assets, tools, nudge.csproj.user, .workbuddy, and %APPDATA%\Nudge (reset.ps1 handles that).'

if ($failed.Count) {
    Write-Warning "still there: $($failed -join ', ') - close the IDE and run clean again."
    exit 1
}
