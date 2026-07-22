# design\icon_*.png を Windows アプリアイコン app_icon.ico にパックする。
#
# PNG 自体は形状定義（lib\ui\anchor_mark.dart）から生成する:
#     flutter test tools\gen_icon.dart
# このスクリプトは生成済み PNG をまとめるだけで、描画も背景除去も行わない。
#
# .ico は各エントリに PNG をそのまま埋められる（Vista 以降）ので、
# ヘッダを書くだけで済み画像ライブラリは要らない。
param(
    [string]$PngDir,
    [string]$Ico
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $PngDir) { $PngDir = Join-Path $repo 'design' }
if (-not $Ico)    { $Ico    = Join-Path $repo 'windows\runner\resources\app_icon.ico' }

# Windows のシェルが実際に引く標準サイズ。
$sizes = @(16, 24, 32, 48, 64, 256)

$pngs = @()
foreach ($s in $sizes) {
    $path = Join-Path $PngDir "icon_$s.png"
    if (-not (Test-Path $path)) {
        Write-Error "$path がありません。先に flutter test tools\gen_icon.dart を実行してください。"
        exit 1
    }
    $pngs += ,[System.IO.File]::ReadAllBytes($path)
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Ico) | Out-Null
$fs = [System.IO.File]::Create($Ico)
$bw = New-Object System.IO.BinaryWriter($fs)
try {
    # ICONDIR
    $bw.Write([uint16]0)             # reserved
    $bw.Write([uint16]1)             # type: 1 = icon
    $bw.Write([uint16]$sizes.Count)

    # ICONDIRENTRY x n（256 は 1 バイトに収まらないので 0 で表す）
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $s = $sizes[$i]
        $dim = if ($s -ge 256) { 0 } else { $s }
        $bw.Write([byte]$dim)        # width
        $bw.Write([byte]$dim)        # height
        $bw.Write([byte]0)           # パレット色数（true color なので 0）
        $bw.Write([byte]0)           # reserved
        $bw.Write([uint16]1)         # color planes
        $bw.Write([uint16]32)        # bits per pixel
        $bw.Write([uint32]$pngs[$i].Length)
        $bw.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }

    foreach ($p in $pngs) { $bw.Write($p) }
}
finally {
    $bw.Dispose()
    $fs.Dispose()
}

Get-Item $Ico | Select-Object Name, Length
"パック済み: $($sizes -join ', ') px"
