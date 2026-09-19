$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assets = 'C:\Users\jingyi.lin\Documents\vibe_coding\tangerine-nudge\nudge\Assets'
$states = @('waiting', 'done', 'silent')
$sizes = @(16, 32)
$cellW = 220
$cellH = 250
$width = $cellW * 2
$height = $cellH * 3
$bmp = New-Object System.Drawing.Bitmap($width, $height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 32, 32, 32))
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$font = New-Object System.Drawing.Font('Segoe UI', 10)
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
for ($r = 0; $r -lt $states.Count; $r++) {
    for ($c = 0; $c -lt $sizes.Count; $c++) {
        $s = [int]$sizes[$c]
        $state = $states[$r]
        $ico = New-Object System.Drawing.Icon((Join-Path $assets "nudge-$state.ico"), (New-Object System.Drawing.Size($s, $s)))
        $x = $cellW * $c
        $y = $cellH * $r
        $g.DrawString("$state @ ${s}px", $font, $white, [single]$x, [single]$y)
        $g.DrawImage($ico.ToBitmap(), [single]($x + 10), [single]($y + 30), [single]($s * 6), [single]($s * 6))
        $ico.Dispose()
    }
}
$g.Dispose()
$bmp.Save((Join-Path $assets 'preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$font.Dispose(); $white.Dispose(); $bmp.Dispose()
Write-Host saved
