param(
    [string]$Source = 'assets/videos/idle/idle_01_sip.mp4',
    [string]$Animation = 'assets/animations/idle_01_sip.webp',
    [string]$Poster = 'assets/images/navi_idle_transparent.png'
)

# Produces a portable alpha animation from the black-background preview clip.
# Requires FFmpeg with libwebp_anim and Windows PowerShell / System.Drawing.
# Connected-background matting protects dark details enclosed by the character.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('NaviPreviewMatte' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class NaviPreviewMatte {
    private const int Width = 540;
    private const int Height = 960;
    private const int Threshold = 24;

    private static Process Start(string ffmpeg, string arguments) {
        return Process.Start(new ProcessStartInfo(ffmpeg, arguments) {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true
        });
    }

    private static void SavePoster(byte[] rgba, string path) {
        using (var bitmap = new Bitmap(Width, Height, PixelFormat.Format32bppArgb)) {
            var data = bitmap.LockBits(new Rectangle(0, 0, Width, Height),
                ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            var bgra = new byte[rgba.Length];
            for (int i = 0; i < rgba.Length; i += 4) {
                bgra[i] = rgba[i + 2];
                bgra[i + 1] = rgba[i + 1];
                bgra[i + 2] = rgba[i];
                bgra[i + 3] = rgba[i + 3];
            }
            Marshal.Copy(bgra, 0, data.Scan0, bgra.Length);
            bitmap.UnlockBits(data);
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    public static int Convert(string ffmpeg, string source, string animation, string poster) {
        string dimensions = Width + "x" + Height;
        using (var decoder = Start(ffmpeg,
            "-hide_banner -loglevel error -i \"" + source +
            "\" -an -vf fps=24,scale=" + Width + ":" + Height +
            ":flags=lanczos -f rawvideo -pix_fmt rgb24 pipe:1"))
        using (var encoder = Start(ffmpeg,
            "-hide_banner -loglevel error -y -f rawvideo -pix_fmt rgba -s " + dimensions +
            " -r 24 -i pipe:0 -an -c:v libwebp_anim -lossless 0 -quality 88" +
            " -compression_level 4 -loop 0 \"" + animation + "\"")) {
            int count = Width * Height;
            var rgb = new byte[count * 3];
            var rgba = new byte[count * 4];
            var background = new bool[count];
            var candidate = new bool[count];
            var queue = new int[count];
            int frames = 0;
            try {
                while (true) {
                    int read = 0;
                    while (read < rgb.Length) {
                        int next = decoder.StandardOutput.BaseStream.Read(rgb, read, rgb.Length - read);
                        if (next == 0) break;
                        read += next;
                    }
                    if (read == 0) break;
                    if (read != rgb.Length) throw new InvalidDataException("Incomplete video frame.");
                    Array.Clear(background, 0, count);
                    for (int i = 0; i < count; i++) {
                        int r = i * 3;
                        candidate[i] = Math.Max(rgb[r], Math.Max(rgb[r + 1], rgb[r + 2])) <= Threshold;
                    }
                    int head = 0, tail = 0;
                    for (int i = 0; i < count; i++) {
                        if ((i < Width || i >= count - Width || i % Width == 0 || i % Width == Width - 1)
                            && candidate[i] && !background[i]) {
                            background[i] = true;
                            queue[tail++] = i;
                        }
                    }
                    while (head < tail) {
                        int i = queue[head++];
                        int x = i % Width;
                        if (x > 0) Visit(i - 1, candidate, background, queue, ref tail);
                        if (x < Width - 1) Visit(i + 1, candidate, background, queue, ref tail);
                        if (i >= Width) Visit(i - Width, candidate, background, queue, ref tail);
                        if (i < count - Width) Visit(i + Width, candidate, background, queue, ref tail);
                    }
                    for (int i = 0; i < count; i++) {
                        int r = i * 3, a = i * 4;
                        double alpha = background[i] ? 0 : 1;
                        int x = i % Width;
                        bool edge = !background[i] &&
                            ((x > 0 && background[i - 1]) || (x < Width - 1 && background[i + 1]) ||
                             (i >= Width && background[i - Width]) || (i < count - Width && background[i + Width]));
                        if (edge) {
                            int peak = Math.Max(rgb[r], Math.Max(rgb[r + 1], rgb[r + 2]));
                            alpha = Math.Min(1, Math.Max(0, (peak - Threshold) / 32.0));
                        }
                        rgba[a + 3] = (byte)Math.Round(alpha * 255);
                        for (int c = 0; c < 3; c++)
                            rgba[a + c] = alpha == 0 ? (byte)0 : (byte)Math.Min(255, Math.Round(rgb[r + c] / alpha));
                    }
                    if (frames == 0) SavePoster(rgba, poster);
                    encoder.StandardInput.BaseStream.Write(rgba, 0, rgba.Length);
                    frames++;
                }
                encoder.StandardInput.Close();
                decoder.WaitForExit();
                encoder.WaitForExit();
                if (decoder.ExitCode != 0 || encoder.ExitCode != 0 || frames == 0)
                    throw new InvalidOperationException("FFmpeg could not finish the transparent animation.");
                return frames;
            } finally {
                if (!decoder.HasExited) decoder.Kill();
                if (!encoder.HasExited) encoder.Kill();
            }
        }
    }

    private static void Visit(int i, bool[] candidate, bool[] background, int[] queue, ref int tail) {
        if (candidate[i] && !background[i]) {
            background[i] = true;
            queue[tail++] = i;
        }
    }
}
'@
}

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$animationPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $Animation))
$posterPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $Poster))
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($animationPath)) | Out-Null
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($posterPath)) | Out-Null
$frames = [NaviPreviewMatte]::Convert((Get-Command ffmpeg).Source, $sourcePath, $animationPath, $posterPath)
Write-Output "Prepared $frames transparent frames at 540x960, 24 fps."
Get-Item -LiteralPath $animationPath, $posterPath | Select-Object Name, Length
