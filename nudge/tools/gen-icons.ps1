# Nudge tray icon generator — one glyph (the glance), three honest states, drawn for two taskbars.
#
# The taskbar is the one surface Nudge does not own, so the glyph is drawn twice: light strokes
# for a dark taskbar, dark strokes for a light one. Same geometry, same orange pupil — only the
# stroke inverts. Windows keeps the answer in
#   HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\SystemUsesLightTheme
# and Tray.cs picks the matching set at runtime.
#
# The unsuffixed set is the dark-taskbar one. The reminder card always wears its own dark surface
# no matter what the system theme is, so it keeps using the unsuffixed set on purpose.
#
# Re-run after tweaking geometry: powershell -ExecutionPolicy Bypass -File tools/gen-icons.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Join-Path (Split-Path -Parent $PSScriptRoot) 'Assets'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)

# The one accent both sets share: the pupil. Orange carries on white and on black alike.
$orange = [System.Drawing.Color]::FromArgb(255, 240, 120, 30)

# Strokes, keyed by the taskbar they are drawn for. Contrasts are against a white taskbar
# (#FFFFFF) and a black one (#000000) respectively; each set clears 4.5:1 except the "receded"
# moon, which is meant to sit back.
$palettes = @(
    @{
        Taskbar = 'a dark taskbar'
        Suffix  = ''
        Line    = [System.Drawing.Color]::FromArgb(255, 226, 226, 226)   # open eye outline
        Done    = [System.Drawing.Color]::FromArgb(255, 198, 198, 198)   # closed eye, "seen"
        Faint   = [System.Drawing.Color]::FromArgb(255, 118, 118, 118)   # rest day, receded
    },
    @{
        Taskbar = 'a light taskbar'
        Suffix  = '-light'
        Line    = [System.Drawing.Color]::FromArgb(255, 26, 26, 26)      # open eye outline
        Done    = [System.Drawing.Color]::FromArgb(255, 69, 69, 69)      # closed eye, "seen"
        Faint   = [System.Drawing.Color]::FromArgb(255, 127, 127, 127)   # rest day, receded
    }
)

function F([double]$v) { return [float]$v }

function Draw-Glyph([int]$s, [string]$state, $pal) {
    # 4x supersample then downscale: clean curves even at 16px.
    $big = New-GlyphRaw ($s * 4) $state $pal
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($big, (New-Object System.Drawing.Rectangle(0, 0, $s, $s)))
    $g.Dispose(); $big.Dispose()
    return $bmp
}

function New-GlyphRaw([int]$s, [string]$state, $pal) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $w = [Math]::Max(1.25, [Math]::Round(0.09 * $s, 2))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, (F $w))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath

    if ($state -eq 'waiting') {
        # Open eye: almond of two symmetric beziers + one filled pupil. Nothing else.
        $pen.Color = $pal.Line
        $path.AddBezier((F(0.06*$s)), (F(0.52*$s)), (F(0.25*$s)), (F(0.10*$s)), (F(0.75*$s)), (F(0.10*$s)), (F(0.94*$s)), (F(0.52*$s)))
        $path.AddBezier((F(0.94*$s)), (F(0.52*$s)), (F(0.75*$s)), (F(0.94*$s)), (F(0.25*$s)), (F(0.94*$s)), (F(0.06*$s)), (F(0.52*$s)))
        $g.DrawPath($pen, $path)
        $r = 0.185 * $s
        $brush = New-Object System.Drawing.SolidBrush($orange)
        $g.FillEllipse($brush, (F(0.5*$s - $r)), (F(0.52*$s - $r)), (F(2*$r)), (F(2*$r)))
        $brush.Dispose()
    }
    elseif ($state -eq 'done') {
        # Seen: same open eye, pupil replaced by an orange check. "Glanced, settled."
        $pen.Color = $pal.Done
        $path.AddBezier((F(0.06*$s)), (F(0.52*$s)), (F(0.25*$s)), (F(0.10*$s)), (F(0.75*$s)), (F(0.10*$s)), (F(0.94*$s)), (F(0.52*$s)))
        $path.AddBezier((F(0.94*$s)), (F(0.52*$s)), (F(0.75*$s)), (F(0.94*$s)), (F(0.25*$s)), (F(0.94*$s)), (F(0.06*$s)), (F(0.52*$s)))
        $g.DrawPath($pen, $path)
        $check = New-Object System.Drawing.Pen($orange, (F([Math]::Max(1.4, 0.11 * $s))))
        $check.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $check.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
        $check.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawLines($check, @(
            (New-Object System.Drawing.PointF((F(0.36*$s)), (F(0.53*$s)))),
            (New-Object System.Drawing.PointF((F(0.46*$s)), (F(0.65*$s)))),
            (New-Object System.Drawing.PointF((F(0.67*$s)), (F(0.36*$s))))
        ))
        $check.Dispose()
    }
    else {
        # Rest day: a receded crescent moon. Eyes are off duty — no smile ambiguity.
        # Fill the disk, then punch out the offset disk with transparent pixels.
        $brush = New-Object System.Drawing.SolidBrush($pal.Faint)
        $g.FillEllipse($brush, (F(0.14*$s)), (F(0.16*$s)), (F(0.68*$s)), (F(0.68*$s)))
        $brush.Dispose()
        $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $cut = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $g.FillEllipse($cut, (F(0.40*$s)), (F(0.02*$s)), (F(0.66*$s)), (F(0.66*$s)))
        $cut.Dispose()
        # SourceCopy leaves the rest of the canvas replaced; redraw nothing else — moon only.
    }

    $path.Dispose(); $pen.Dispose(); $g.Dispose()
    return $bmp
}

function Get-BmpFrame($bmp) {
    # Classic 32bpp BGRA XOR + AND mask. GDI+ Icon cannot load PNG-compressed ICO frames.
    $s = $bmp.Width
    $andRow = [int](($s + 31) / 32) * 4
    $xorLen = $s * $s * 4
    $andLen = $andRow * $s
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([uint32]40); $bw.Write([int32]$s); $bw.Write([int32]($s * 2))
    $bw.Write([uint16]1);  $bw.Write([uint16]32); $bw.Write([uint32]0)
    $bw.Write([uint32]($xorLen + $andLen))
    $bw.Write([int32]0);   $bw.Write([int32]0);   $bw.Write([uint32]0); $bw.Write([uint32]0)
    for ($y = $s - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $s; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A)
        }
    }
    $bw.Write((New-Object byte[] $andLen))
    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose(); $bmp.Dispose()
    return , $bytes
}

function New-Ico([string]$outPath, [string]$state, $pal) {
    $frames = @()
    foreach ($s in $sizes) {
        $frames += , (Get-BmpFrame (Draw-Glyph $s $state $pal))
    }
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    foreach ($i in 0..($frames.Count - 1)) {
        $s = $sizes[$i]
        $b = $frames[$i]
        $dim = if ($s -ge 256) { 0 } else { $s }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim)
        $bw.Write([byte]0);    $bw.Write([byte]0)
        $bw.Write([uint16]1);  $bw.Write([uint16]32)
        $bw.Write([uint32]$b.Length); $bw.Write([uint32]$offset)
        $offset += $b.Length
    }
    foreach ($b in $frames) { $bw.Write($b) }
    [System.IO.File]::WriteAllBytes($outPath, $ms.ToArray())
    $bw.Dispose(); $ms.Dispose()
    Write-Host ("wrote {0}  ({1}, for {2})" -f (Split-Path -Leaf $outPath), $state, $pal.Taskbar)
}

foreach ($pal in $palettes) {
    New-Ico (Join-Path $root "nudge-waiting$($pal.Suffix).ico") 'waiting' $pal
    New-Ico (Join-Path $root "nudge-done$($pal.Suffix).ico")   'done'    $pal
    New-Ico (Join-Path $root "nudge-silent$($pal.Suffix).ico") 'silent'  $pal
}

# The executable's own icon (Explorer, Alt-Tab, Task Manager): dark-taskbar strokes, since those
# surfaces are dark in the shell's default look and there is no theme hook for a static icon.
Copy-Item (Join-Path $root 'nudge-waiting.ico') (Join-Path $root 'nudge.ico') -Force
Write-Host 'done'
