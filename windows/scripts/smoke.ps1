# CI duman testi: uygulamayı açar, olay gönderir, ekran görüntüsü alır, çökmediğini doğrular.
param([string]$Exe, [string]$Hook, [string]$Out = "shots")
$ErrorActionPreference = "Stop"
$OutputEncoding = [Text.Encoding]::UTF8
New-Item -ItemType Directory -Force $Out | Out-Null
$home2 = Join-Path $env:RUNNER_TEMP "tp-home"
New-Item -ItemType Directory -Force $home2 | Out-Null
$env:TELEPAITH_PORTABLE = "1"
$env:TELEPAITH_HOME = $home2

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class Snap {
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, int rop);
  public static void Save(string path) {
    var b = System.Windows.Forms.SystemInformation.VirtualScreen;
    using (var bmp = new Bitmap(b.Width, b.Height))
    using (var g = Graphics.FromImage(bmp)) {
      IntPtr screen = GetDC(IntPtr.Zero);
      IntPtr hdc = g.GetHdc();
      BitBlt(hdc, 0, 0, b.Width, b.Height, screen, b.Left, b.Top, 0x00CC0020 | 0x40000000);
      g.ReleaseHdc(hdc);
      ReleaseDC(IntPtr.Zero, screen);
      bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }
  }
}
"@
function Shot($name) {
  [Snap]::Save((Join-Path (Resolve-Path $Out) "$name.png"))
  Write-Host "shot $name"
}
function State() {
  $port = (Get-Content (Join-Path $home2 "port")).Trim()
  $raw = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/state").Content
  Write-Host "state: $raw"
  return ($raw | ConvertFrom-Json)
}
function Check($cond, $msg) { if (-not $cond) { throw "BAŞARISIZ: $msg" } else { Write-Host "  ok: $msg" } }
# Robotun penceresi gerçekten çiziliyor mu? Kafanın olduğu yerde masaüstünden farklı renkli piksel say
function PixelCheck($st, $name) {
  Add-Type -AssemblyName System.Drawing
  $bmp = [System.Drawing.Bitmap]::FromFile((Join-Path (Resolve-Path $Out) "$name.png"))
  $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $cx = [int]$st.head.x - $vs.Left; $cy = [int]$st.head.y - $vs.Top; $r = [int]($st.head.size / 2)
  $bg = $bmp.GetPixel([Math]::Min($bmp.Width - 1, $cx + 3 * $r), [Math]::Max(0, $cy - 3 * $r))
  $diff = 0; $total = 0; $dark = 0
  for ($x = $cx - $r; $x -lt $cx + $r; $x += 3) { for ($y = $cy - $r; $y -lt $cy + $r; $y += 3) {
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $bmp.Width -or $y -ge $bmp.Height) { continue }
    $c = $bmp.GetPixel($x, $y); $total++
    if ([Math]::Abs($c.R - $bg.R) + [Math]::Abs($c.G - $bg.G) + [Math]::Abs($c.B - $bg.B) -gt 40) { $diff++ }
    if ($c.R -lt 40 -and $c.G -lt 40 -and $c.B -lt 60) { $dark++ }
  } }
  $bmp.Dispose()
  Write-Host "  pixels $name : $diff / $total farklı, $dark koyu (vizör)"
  return $diff / [Math]::Max(1, $total)
}
function Post($json) {
  $port = (Get-Content (Join-Path $home2 "port")).Trim()
  Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$port/event" -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" | Out-Null
}
function HookEvent($source, $json) { $json | & $Hook hook $source }

$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep 8
if ($p.HasExited) { Get-Content (Join-Path $home2 "error.log") -ErrorAction SilentlyContinue; throw "Uygulama açılır açılmaz kapandı (kod $($p.ExitCode))" }
Shot "1-start"
$st = State
Check ($st.visible -and $st.windowVisible) "robot görünür"
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
Check ($st.head.x -gt $vs.Left -and $st.head.x -lt $vs.Right -and $st.head.y -gt $vs.Top -and $st.head.y -lt $vs.Bottom) "kafa ekranın içinde"
Check ((PixelCheck $st "1-start") -gt 0.3) "robot ekrana çiziliyor"

$port = (Get-Content (Join-Path $home2 "port")).Trim()
$health = Invoke-RestMethod "http://127.0.0.1:$port/health"
Write-Host "health: $health"

Post '{"agent":"claude","session":"s1","project":"web","state":"thinking","text":"Düşünüyor…"}'
Start-Sleep 2
Shot "2-thinking"
$st = State
Check ($st.source -eq "claude" -and $st.state -eq "Thinking") "Claude düşünüyor"
Post '{"agent":"claude","session":"s1","project":"web","state":"waiting","text":"Onayını bekliyor: npm install"}'
HookEvent "gpt" '{"hook_event_name":"UserPromptSubmit","session_id":"g1","cwd":"C:\\proj\\api","prompt":"testleri düzelt"}'
HookEvent "claude" '{"hook_event_name":"PreToolUse","session_id":"s2","cwd":"C:\\proj\\mobile","tool_name":"Bash","tool_input":{"command":"npm test"}}'
Start-Sleep 3
Shot "3-waiting-minis"
$st = State
Check ($st.state -eq "Waiting") "onay bekliyor"
Check ($st.bubble -like "*npm install*") "balonda komut yazıyor"
Check ($st.minis -ge 2) "diğer oturumlar minik kafa"
Post '{"agent":"claude","session":"s1","project":"web","state":"done","text":"Bitti"}'
Start-Sleep -Milliseconds 1200
Shot "4-done"
$st = State
Check ($st.state -eq "Done" -or $st.minis -ge 1) "bitti / sıradaki oturum"

Start-Sleep 2
if ($p.HasExited) { Get-Content (Join-Path $home2 "error.log") -ErrorAction SilentlyContinue; throw "Uygulama çöktü (kod $($p.ExitCode))" }
if (Test-Path (Join-Path $home2 "error.log")) { Write-Host "--- error.log ---"; Get-Content (Join-Path $home2 "error.log") }
Get-ChildItem $home2 | Select-Object Name, Length | Format-Table | Out-String | Write-Host
Stop-Process -Id $p.Id -Force
Write-Host "Duman testi geçti"
