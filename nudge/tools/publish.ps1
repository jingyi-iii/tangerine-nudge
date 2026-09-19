#Requires -Version 5.1
<#
.SYNOPSIS
    Publish Nudge as one self-contained executable.

.DESCRIPTION
    Produces a single nudge.exe with the .NET runtime and every managed and native library
    packed inside it, so the file can be copied to a machine that has never seen .NET and run
    straight away. The output folder ends up holding exactly that one file.

    The build choices this script pins, and why:

      PublishSingleFile + IncludeNativeLibrariesForSelfExtract
          WPF ships native DLLs (wpfgfx_cor3, PresentationNative_cor3, D3DCompiler). Single-file
          on its own leaves those sitting next to the exe; this property is what folds them in.

      PublishTrimmed=false
          The trimmer is not supported for WPF. It builds cleanly and then dies at startup on a
          missing type, so it is pinned off rather than left to whatever the SDK defaults to.

      DebugType=none / DebugSymbols=false
          Otherwise a .pdb lands beside the exe and "one file" stops being true.

      SatelliteResourceLanguages=en
          Drops the localized WPF resource assemblies. The UI is English only.

      EnableCompressionInSingleFile
          Roughly halves the exe. Costs a little on the first start, while the bundle unpacks
          its native libraries into %TEMP%\.net (see reset.ps1, which cleans that up).

    About the autostart entry: the app decides for itself whether to register one, based on where
    it is running from (App.IsDevLocation). A copy under %TEMP% or under obj/bin does not touch
    the registry, so a published build can be smoke-tested without side effects. Running it from
    .\dist, or from wherever it ends up on the target machine, does add the HKCU Run entry - that
    is the intent.

.PARAMETER Runtime
    Target RID: win-x64 (default), win-arm64 or win-x86.

.PARAMETER Configuration
    Release (default) or Debug.

.PARAMETER OutputDir
    Where to publish. Default: <repo>\dist.

.PARAMETER FrameworkDependent
    Do not bundle the runtime. The exe drops to well under a megabyte, but the target machine
    then needs the .NET 10 Desktop Runtime installed. Everything else is the same.

.PARAMETER NoCompress
    Skip bundle compression: a bigger exe that starts a little faster.

.PARAMETER KeepRunning
    Do not stop a running Nudge. The publish will usually fail on a locked file.

.PARAMETER Verify
    After publishing, run the exe with "--debug-reminder --count 1 --hold 5" and check the app
    log and the exit code. Proves the bundle is runnable, not merely present. Safe: the debug
    paths return before App.EnsureAutoStart, so nothing is written to the registry.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\publish.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\publish.ps1 -Verify

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\publish.ps1 -Runtime win-arm64 -NoCompress
#>
[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-arm64', 'win-x86')]
    [string]$Runtime = 'win-x64',

    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',

    [string]$OutputDir,

    [switch]$FrameworkDependent,
    [switch]$NoCompress,
    [switch]$KeepRunning,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $PSScriptRoot          # <repo>\nudge
$repoRoot   = Split-Path -Parent $projectDir            # <repo>
$csproj     = Join-Path $projectDir 'nudge.csproj'

if (-not (Test-Path -LiteralPath $csproj)) {
    throw "nudge.csproj not found at $csproj - this script expects to sit in <repo>\nudge\tools."
}
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot 'dist' }
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet is not on PATH. Install the .NET SDK, or run this from a Developer Prompt."
}

# Refuse to wipe anything that is not a place a publish output would live.
function Assert-SafeOutputDir([string]$path) {
    $full = $path.TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($full -ieq $root) { throw "refusing to publish into a drive root: $full" }
    $personal = @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA) |
        Where-Object { $_ } |
        ForEach-Object { ([System.IO.Path]::GetFullPath($_)).TrimEnd('\') }
    foreach ($p in $personal) {
        if ($full -ieq $p) { throw "refusing to publish into a user folder: $full" }
    }
    if ($full -ieq ([System.IO.Path]::GetFullPath($repoRoot)).TrimEnd('\')) {
        throw "refusing to publish into the repo root - that would clear the source tree."
    }
}

Assert-SafeOutputDir $OutputDir

if (-not $KeepRunning) {
    $running = @(Get-Process -Name nudge -ErrorAction SilentlyContinue)
    if ($running.Count) {
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 400
        Write-Host "stopped $($running.Count) running nudge process(es) so the build can overwrite its own binaries"
    }
}

# A publish folder accumulates: without this, a leftover file from a framework-dependent run
# would survive and quietly break the "exactly one file" promise.
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$selfContained = -not $FrameworkDependent
$props = [ordered]@{
    SelfContained                        = $selfContained
    PublishSingleFile                    = $true
    PublishTrimmed                       = $false   # unsupported for WPF; see .DESCRIPTION
    PublishReadyToRun                    = $false   # size over startup speed for a tray app
    IncludeNativeLibrariesForSelfExtract = $selfContained
    EnableCompressionInSingleFile        = ($selfContained -and -not $NoCompress)
    UseAppHost                           = $true
    DebugType                            = 'none'
    DebugSymbols                         = $false
    SatelliteResourceLanguages           = 'en'
}

$publishArgs = @('publish', $csproj, '-c', $Configuration, '-r', $Runtime, '-o', $OutputDir, '--nologo')
foreach ($key in $props.Keys) {
    $publishArgs += "-p:$key=$($props[$key].ToString().ToLowerInvariant())"
}

$kind = if ($selfContained) { 'self-contained' } else { 'framework-dependent' }
Write-Host "publishing $kind, $Runtime, $Configuration"
Write-Host "  -> $OutputDir"
Write-Host ''

& dotnet @publishArgs
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

# --- report what came out ---------------------------------------------------------------
$exes = @(Get-ChildItem -LiteralPath $OutputDir -Filter '*.exe' -File)
if ($exes.Count -ne 1) {
    throw "expected exactly one exe in $OutputDir but found $($exes.Count): $($exes.Name -join ', ')"
}
$exe = $exes[0]

$extras = @(Get-ChildItem -LiteralPath $OutputDir -File | Where-Object { $_.FullName -ne $exe.FullName })
$hash = (Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash

Write-Host ''
Write-Host 'published'
Write-Host ("  file     {0}" -f $exe.FullName)
Write-Host ("  size     {0:N1} MB" -f ($exe.Length / 1MB))
Write-Host ("  sha256   {0}" -f $hash)
if ($extras.Count) {
    Write-Warning "$($extras.Count) extra file(s) share the folder - 'one exe' is not true: $($extras.Name -join ', ')"
} else {
    Write-Host '  folder   contains nothing but that exe'
}
if (-not $selfContained) {
    Write-Warning 'framework-dependent build: the target machine needs the .NET 10 Desktop Runtime.'
}

# --- optional smoke test ----------------------------------------------------------------
if ($Verify) {
    Write-Host ''
    Write-Host 'verifying: running the published exe (1 card, 5s, then it exits on its own)'

    $log = Join-Path $env:APPDATA 'Nudge\nudge.log'
    $mark = 0
    if (Test-Path -LiteralPath $log) { $mark = (Get-Item -LiteralPath $log).Length }

    $proc = Start-Process -FilePath $exe.FullName `
        -ArgumentList '--debug-reminder', '--count', '1', '--hold', '5' -PassThru
    if (-not $proc.WaitForExit(60000)) {
        $proc.Kill()
        throw 'the published exe did not shut itself down - something is wrong with the bundle'
    }

    # Read only what this run appended, so old noise cannot pass for a clean start.
    $tail = ''
    if (Test-Path -LiteralPath $log) {
        $fs = [System.IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
        try {
            [void]$fs.Seek($mark, 'Begin')
            $sr = New-Object System.IO.StreamReader($fs)
            $tail = $sr.ReadToEnd()
            $sr.Dispose()
        } finally { $fs.Dispose() }
    }

    $started = $tail -match 'Debug reminder shown'
    $errored = $tail -match 'ERROR'
    Write-Host ("  exit code  {0}" -f $proc.ExitCode)
    Write-Host ("  log        start ok = {0}, errors = {1}" -f $started, $errored)

    if ($proc.ExitCode -ne 0 -or -not $started -or $errored) {
        throw "the published exe did not start cleanly. Log tail from this run:`n$tail"
    }
    Write-Host '  ok - the bundle runs'
}

Write-Host ''
Write-Host 'next: copy that single exe to the target machine and run it. On first launch it seeds'
Write-Host '%APPDATA%\Nudge\settings.json and registers itself for autostart (HKCU Run).'
