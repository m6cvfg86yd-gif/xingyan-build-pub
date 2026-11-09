param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $Root "app-icon-starorbit-1024.png"
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Missing icon source: $sourcePath"
}

function New-RoundedPath {
    param(
        [System.Drawing.RectangleF]$Rect,
        [float]$Radius
    )
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $arc = [System.Drawing.RectangleF]::new($Rect.X, $Rect.Y, $diameter, $diameter)
    $path.AddArc($arc, 180, 90)
    $arc.X = $Rect.Right - $diameter
    $path.AddArc($arc, 270, 90)
    $arc.Y = $Rect.Bottom - $diameter
    $path.AddArc($arc, 0, 90)
    $arc.X = $Rect.X
    $path.AddArc($arc, 90, 90)
    $path.CloseFigure()
    return $path
}

function Add-GlassFinish {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$Path,
        [string]$Mode
    )

    $canvas = [System.Drawing.Bitmap]::new(1024, 1024,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode =
        [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode =
        [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    if ($Mode -eq "tinted") {
        $matrix = [System.Drawing.Imaging.ColorMatrix]::new()
        $matrix.Matrix00 = 0.299
        $matrix.Matrix01 = 0.299
        $matrix.Matrix02 = 0.299
        $matrix.Matrix10 = 0.587
        $matrix.Matrix11 = 0.587
        $matrix.Matrix12 = 0.587
        $matrix.Matrix20 = 0.114
        $matrix.Matrix21 = 0.114
        $matrix.Matrix22 = 0.114
        $matrix.Matrix33 = 1.0
        $matrix.Matrix44 = 1.0
        $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
        $attributes.SetColorMatrix($matrix)
        $rect = [System.Drawing.Rectangle]::new(0, 0, 1024, 1024)
        $graphics.DrawImage($Bitmap, $rect, 0, 0, 1024, 1024,
            [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $attributes.Dispose()
    } elseif ($Mode -eq "dark") {
        $graphics.DrawImage($Bitmap, 0, 0, 1024, 1024)
        $shade = [System.Drawing.SolidBrush]::new(
            [System.Drawing.Color]::FromArgb(118, 4, 18, 13))
        $graphics.FillRectangle($shade, 0, 0, 1024, 1024)
        $shade.Dispose()
    } else {
        $graphics.DrawImage($Bitmap, 0, 0, 1024, 1024)
    }

    $pathShape = New-RoundedPath `
        -Rect ([System.Drawing.RectangleF]::new(4, 4, 1016, 1016)) `
        -Radius 224

    $highlightAlpha = if ($Mode -eq "dark") { 72 } else { 54 }
    $highlight = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.PointF]::new(110, 0),
        [System.Drawing.PointF]::new(820, 920),
        [System.Drawing.Color]::FromArgb($highlightAlpha, 255, 255, 255),
        [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $highlight.SetSigmaBellShape(0.24, 0.72)
    $graphics.FillPath($highlight, $pathShape)
    $highlight.Dispose()

    $sweep = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.PointF]::new(0, 760),
        [System.Drawing.PointF]::new(1024, 210),
        [System.Drawing.Color]::FromArgb(0, 175, 255, 225),
        [System.Drawing.Color]::FromArgb(
            $(if ($Mode -eq "dark") { 64 } else { 46 }),
            175, 255, 225))
    $sweep.SetSigmaBellShape(0.48, 0.94)
    $graphics.FillPath($sweep, $pathShape)
    $sweep.Dispose()

    $edge = [System.Drawing.Pen]::new(
        [System.Drawing.Color]::FromArgb(
            $(if ($Mode -eq "dark") { 82 } else { 64 }),
            255, 255, 255),
        3.2)
    $edge.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Inset
    $graphics.DrawPath($edge, $pathShape)
    $edge.Dispose()

    $random = [System.Random]::new(20261110)
    $noise = [System.Drawing.SolidBrush]::new(
        [System.Drawing.Color]::FromArgb(15, 255, 255, 255))
    for ($i = 0; $i -lt 3600; $i++) {
        $x = $random.Next(8, 1016)
        $y = $random.Next(8, 1016)
        $graphics.FillRectangle($noise, $x, $y, 1, 1)
    }
    $noise.Dispose()

    $pathShape.Dispose()
    $graphics.Dispose()
    $canvas.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
}

$source = [System.Drawing.Bitmap]::new($sourcePath)
$outputs = @{
    "app-icon-starorbit-glass-1024.png" = "normal"
    "app-icon-starorbit-glass-dark-1024.png" = "dark"
    "app-icon-starorbit-glass-tinted-1024.png" = "tinted"
}
foreach ($entry in $outputs.GetEnumerator()) {
    Add-GlassFinish -Bitmap $source `
        -Path (Join-Path $Root $entry.Key) `
        -Mode $entry.Value
}
$source.Dispose()

Write-Host "Glass icon variants generated in $Root"
