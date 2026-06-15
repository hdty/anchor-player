# design\anchor_source.png（透過PNG）から、角丸グラデーション背景付きの
# Windows アプリアイコン app_icon.ico を生成する。
# 背景: 左上(10時)=水色 #A3D8E1 → 右下(4時)=桜色 #E8AFCF、角丸は16pxで半径3.5px相当。
# 元はPhotoNote用に作ったスクリプトを Anchor Player 用に流用。
param(
    [string]$Art,
    [string]$Ico,
    [string]$PreviewDir
)

$repo = Split-Path -Parent $PSScriptRoot
if (-not $Art)        { $Art        = Join-Path $repo 'design\anchor_source.png' }
if (-not $Ico)        { $Ico        = Join-Path $repo 'windows\runner\resources\app_icon.ico' }
if (-not $PreviewDir) { $PreviewDir = Join-Path $repo 'design' }

if (-not (Test-Path $Art)) {
    Write-Error "元画像が見つかりません: $Art （透過PNGをここに保存してください）"
    exit 1
}
New-Item -ItemType Directory -Force -Path $PreviewDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Ico) | Out-Null

$code = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class IconMaker
{
    public static void Make(string artPath, string icoPath, string previewDir)
    {
        using (var src = new Bitmap(artPath))
        using (var art = RemoveBackground(src))
        {
            int[] sizes = { 16, 24, 32, 48, 64, 256 };
            var pngs = new List<byte[]>();
            Color blue = Color.FromArgb(163, 216, 225);
            Color pink = Color.FromArgb(232, 175, 207);
            foreach (var s in sizes)
            {
                using (var bmp = new Bitmap(s, s, PixelFormat.Format32bppArgb))
                {
                    using (var g = Graphics.FromImage(bmp))
                    {
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        float r = Math.Max(2f, s * 3.5f / 16f);
                        using (var path = RoundedRect(0, 0, s, s, r))
                        using (var brush = new LinearGradientBrush(
                            new Point(0, 0), new Point(s, s), blue, pink))
                        {
                            g.FillPath(brush, path);
                        }
                        int inset = Math.Max(1, (int)(s * 0.05));
                        g.DrawImage(art, inset, inset, s - inset * 2, s - inset * 2);
                    }
                    using (var ms = new MemoryStream())
                    {
                        bmp.Save(ms, ImageFormat.Png);
                        pngs.Add(ms.ToArray());
                    }
                    if (s == 16 || s == 64 || s == 256)
                        File.WriteAllBytes(Path.Combine(previewDir, "icon_" + s + ".png"), pngs[pngs.Count - 1]);
                }
            }
            using (var outFs = File.Create(icoPath))
            using (var bw = new BinaryWriter(outFs))
            {
                bw.Write((ushort)0); bw.Write((ushort)1); bw.Write((ushort)sizes.Length);
                int offset = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++)
                {
                    int s = sizes[i];
                    bw.Write((byte)(s >= 256 ? 0 : s));
                    bw.Write((byte)(s >= 256 ? 0 : s));
                    bw.Write((byte)0); bw.Write((byte)0);
                    bw.Write((ushort)1); bw.Write((ushort)32);
                    bw.Write((uint)pngs[i].Length); bw.Write((uint)offset);
                    offset += pngs[i].Length;
                }
                foreach (var b in pngs) bw.Write(b);
            }
        }
    }

    static GraphicsPath RoundedRect(float x, float y, float w, float h, float r)
    {
        var p = new GraphicsPath();
        float d = r * 2;
        p.AddArc(x, y, d, d, 180, 90);
        p.AddArc(x + w - d, y, d, d, 270, 90);
        p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        p.AddArc(x, y + h - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    // 外周から背景(透明 or 白/薄灰の低彩度ピクセル)をたどって透明化する。
    // 既に透過済みのPNGでも安全に通せる（前面の濃い色や鮮やかな色は残る）。
    static Bitmap RemoveBackground(Bitmap src)
    {
        int w = src.Width, h = src.Height;
        var bmp = new Bitmap(src);
        var rect = new Rectangle(0, 0, w, h);
        var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = data.Stride;
        var px = new byte[stride * h];
        Marshal.Copy(data.Scan0, px, 0, px.Length);

        Func<int, int, bool> isBg = (x, y) =>
        {
            int i = y * stride + x * 4;
            byte b = px[i], gc = px[i + 1], rc = px[i + 2], a = px[i + 3];
            if (a < 200) return true;
            int mx = Math.Max(rc, Math.Max(gc, b)), mn = Math.Min(rc, Math.Min(gc, b));
            return (mx - mn) <= 18 && mn >= 175;
        };

        var visited = new bool[w * h];
        var queue = new Queue<int>();
        Action<int, int> push = (x, y) =>
        {
            int idx = y * w + x;
            if (!visited[idx] && isBg(x, y)) { visited[idx] = true; queue.Enqueue(idx); }
        };
        for (int x = 0; x < w; x++) { push(x, 0); push(x, h - 1); }
        for (int y = 0; y < h; y++) { push(0, y); push(w - 1, y); }
        while (queue.Count > 0)
        {
            int idx = queue.Dequeue();
            int x = idx % w, y = idx / w;
            px[y * stride + x * 4 + 3] = 0;
            if (x > 0) push(x - 1, y);
            if (x < w - 1) push(x + 1, y);
            if (y > 0) push(x, y - 1);
            if (y < h - 1) push(x, y + 1);
        }

        // 外周と繋がっていない閉じた背景領域(錨の輪っかの穴など)のうち、
        // 最大の連結成分を透明化する。穴の向こうに後ろのグラデーションが透ける。
        var seen2 = new bool[w * h];
        var dq2 = new Queue<int>();
        List<int> best = null;
        for (int sy = 0; sy < h; sy++)
        {
            for (int sx = 0; sx < w; sx++)
            {
                int si = sy * w + sx;
                if (visited[si] || seen2[si] || !isBg(sx, sy)) continue;
                var comp = new List<int>();
                seen2[si] = true; dq2.Enqueue(si);
                while (dq2.Count > 0)
                {
                    int ci = dq2.Dequeue(); comp.Add(ci);
                    int cx = ci % w, cy = ci / w;
                    Action<int, int> push2 = (nx, ny) =>
                    {
                        int ni = ny * w + nx;
                        if (!visited[ni] && !seen2[ni] && isBg(nx, ny)) { seen2[ni] = true; dq2.Enqueue(ni); }
                    };
                    if (cx > 0) push2(cx - 1, cy);
                    if (cx < w - 1) push2(cx + 1, cy);
                    if (cy > 0) push2(cx, cy - 1);
                    if (cy < h - 1) push2(cx, cy + 1);
                }
                if (best == null || comp.Count > best.Count) best = comp;
            }
        }
        if (best != null)
            foreach (int ci in best)
                px[(ci / w) * stride + (ci % w) * 4 + 3] = 0;

        Marshal.Copy(px, 0, data.Scan0, px.Length);
        bmp.UnlockBits(data);
        return bmp;
    }
}
'@
if ($PSEdition -eq 'Core') {
    # PowerShell 7+ (.NET) 用
    $refs = @(
        'System.Drawing.Common', 'System.Drawing.Primitives', 'System.Collections',
        'System.Runtime.InteropServices', 'System.IO.MemoryMappedFiles', 'netstandard'
    )
} else {
    # Windows PowerShell 5.1 (.NET Framework) 用
    $refs = @('System.Drawing')
}
Add-Type -TypeDefinition $code -ReferencedAssemblies $refs
[IconMaker]::Make($Art, $Ico, $PreviewDir)
Get-Item $Ico | Select-Object Name, Length
"プレビュー: $PreviewDir\icon_16.png / icon_64.png / icon_256.png"
