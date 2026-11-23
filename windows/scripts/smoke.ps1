# NOT: Bu dosya UTF-8 BOM'lu kalmalı (Windows PowerShell 5.1 BOM'suz dosyadaki Türkçe karakterleri bozuyor).
# CI duman testi: uygulamayı açar, olay gönderir, ekran görüntüsü alır, çökmediğini doğrular.
param([string]$Exe, [string]$Hook, [string]$Out = "shots")
$ErrorActionPreference = "Stop"
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
New-Item -ItemType Directory -Force $Out | Out-Null
$home2 = Join-Path $env:RUNNER_TEMP "tp-home"
New-Item -ItemType Directory -Force $home2 | Out-Null
$env:TELEPAITH_PORTABLE = "1"
$env:TELEPAITH_HOME = $home2
$env:TELEPAITH_HOOK_DEBUG = "1"

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
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Mouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, IntPtr extra);
  public static void Down() { mouse_event(0x02, 0, 0, 0, IntPtr.Zero); }
  public static void Up() { mouse_event(0x04, 0, 0, 0, IntPtr.Zero); }
  public static void RightClick() { mouse_event(0x08, 0, 0, 0, IntPtr.Zero); mouse_event(0x10, 0, 0, 0, IntPtr.Zero); }
}
"@
function State() {
  $port = (Get-Content (Join-Path $home2 "port")).Trim()
  $raw = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/state").Content
  Write-Host "state: $raw"
  return ($raw | ConvertFrom-Json)
}
function Check($cond, $msg) {
  if ($cond) { Write-Host "  ok: $msg"; return }
  foreach ($f in @("error.log", "watch-debug.txt")) {
    $log = Join-Path $home2 $f
    if (Test-Path $log) { Write-Host "--- $f ---"; Get-Content $log -Encoding UTF8 | Write-Host }
  }
  throw "BAŞARISIZ: $msg"
}
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
function Post($json, $query = "") {
  $port = (Get-Content (Join-Path $home2 "port")).Trim()
  Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$port/event$query" -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" | Out-Null
}
function HookEvent($source, $json) {
  $ErrorActionPreference = "Continue"
  $out = ($json | & $Hook hook $source 2>&1 | ForEach-Object { "$_" }) -join " "
  Write-Host "  hook $source -> exit $LASTEXITCODE $out"
}

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
for ($t = 0; $t -lt 6 -and $st.minis -lt 2; $t++) { Start-Sleep -Milliseconds 500; $st = State }
Check ($st.minis -ge 2) "diğer oturumlar minik kafa"
Post '{"agent":"claude","session":"s1","project":"web","state":"done","text":"Bitti"}'
Start-Sleep -Milliseconds 1200
Shot "4-done"
$st = State
Check ($st.state -eq "Done" -or $st.minis -ge 1) "bitti / sıradaki oturum"

# Fareyle: sürükleyip sol üst köşeye bırak → köşeye yapışmalı
$st = State
[Mouse]::SetCursorPos([int]$st.head.x, [int]$st.head.y); Start-Sleep -Milliseconds 400
[Mouse]::Down(); Start-Sleep -Milliseconds 150
for ($i = 1; $i -le 20; $i++) {
  $x = [int]($st.head.x + ($vs.Left + 150 - $st.head.x) * $i / 20); $y = [int]($st.head.y + ($vs.Top + 150 - $st.head.y) * $i / 20)
  [Mouse]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 40
}
[Mouse]::Up(); Start-Sleep -Milliseconds 1500
Shot "5-dragged"
$st = State
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
Check ([Math]::Abs($st.head.x - ($wa.Left + 66)) -le 3 -and [Math]::Abs($st.head.y - ($wa.Top + 66)) -le 3) "sürükle-bırak: sol üst köşeye yapıştı"
Check ($st.alignLeft -and $st.bubbleBelow) "balon köşeye göre yön değiştirdi"
$sb = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Check ($st.window.x -ge $sb.Left -and $st.window.y -ge $sb.Top -and ($st.window.x + $st.window.w) -le $sb.Right -and ($st.window.y + $st.window.h) -le $sb.Bottom) "robot penceresi ekranın dışına taşmıyor"
# Tıkla → son olaylar
[Mouse]::SetCursorPos([int]$st.head.x, [int]$st.head.y); Start-Sleep -Milliseconds 300
[Mouse]::Down(); Start-Sleep -Milliseconds 60; [Mouse]::Up(); Start-Sleep -Milliseconds 800
Shot "6-clicked"
$st = State
Check ($st.bubble -ne $null) "tıklayınca balon açıldı"
# Sağ tık → menü (Esc ile kapat)
[Mouse]::RightClick(); Start-Sleep -Milliseconds 800
Shot "7-menu"
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
# Hook dayanıklılığı: 10 oturum arka arkaya, hepsi ulaşmalı
$before = (State).minis
for ($i = 1; $i -le 10; $i++) {
  HookEvent "claude" ('{"hook_event_name":"PreToolUse","session_id":"x' + $i + '","cwd":"C:\\proj\\p' + $i + '","tool_name":"Read","tool_input":{"file_path":"C:\\proj\\a.cs"}}')
}
Start-Sleep 2
$st = State
Check ($st.minis -ge $before + 10) "10 hook olayının hepsi ulaştı ($before → $($st.minis))"
# Yeniden üretme denemesi: POST'un hemen ardından yeni bir AI'dan ilk hook olayı (bazen kayboluyordu)
$lost = @()
for ($i = 1; $i -le 15; $i++) {
  $src = "ai$i"
  Post ('{"agent":"claude","session":"w' + $i + '","state":"waiting","text":"onay ' + $i + '"}')
  HookEvent $src ('{"hook_event_name":"UserPromptSubmit","session_id":"r' + $i + '","cwd":"C:\\proj\\r","prompt":"testleri düzelt"}')
}
Start-Sleep 2
$st = State
for ($i = 1; $i -le 15; $i++) { if (-not ($st.sessions -contains "ai$i/r$i=Thinking")) { $lost += "ai$i" } }
Check ($lost.Count -eq 0) ("POST ardından ilk hook olayları ulaştı (kayıp: " + ($lost -join ",") + ")")
# Renkli emoji: Windows'un çizicisiyle renkli mi çiziliyor?
$port = (Get-Content (Join-Path $home2 "port")).Trim()
function Dbg($q) { (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/debug/$q").Content }
$em = Dbg "emoji" | ConvertFrom-Json
Write-Host "emoji: $(Dbg 'emoji')"
Check ($em.ok -and $em.colored -gt 80) "emoji renkli çiziliyor ($($em.colored) renkli piksel)"
$em2 = Dbg ("emoji?e=" + [uri]::EscapeDataString("✋")) | ConvertFrom-Json
Check ($em2.ok -and $em2.colored -gt 40) "✋ de renkli"
Post '{"agent":"claude","session":"emo","state":"waiting","text":"🎉 Bitti! 🔒 Kilit 📌 Üstte 🧪 Test 👀"}'
Start-Sleep 1
Shot "8-emoji-bubble"

# Tepsi simgesi kenarlara kadar dolu mu? (eskisi 16 pikselde minicikti)
$tr = Dbg "tray" | ConvertFrom-Json
Write-Host "tray: $(Dbg 'tray')"
Check ($tr.fill16 -gt 0.6 -and $tr.fill -gt 0.6) "tepsi simgesi dolu (%$([int]($tr.fill16 * 100)))"

# Yeni görünüm: menüler ve pencereler açılıp hatasız çiziliyor mu?
foreach ($ui in @("robotmenu", "traymenu", "settings&page=0", "settings&page=1", "settings&page=2", "settings&page=3", "onboarding", "diagnostics")) {
  $r = Dbg ("ui?open=" + $ui)
  Check ($r -eq "ok") "açıldı: $ui"
  Start-Sleep -Milliseconds 900
  Shot ("9-" + ($ui -replace '[&=]', '-'))
  Dbg "ui?open=close" | Out-Null
  Start-Sleep -Milliseconds 300
}
# Sahte "Claude" uygulaması: açılınca robot fark etsin, kapatıp yeniden açınca yine fark etsin
$fakeDir = Join-Path $env:RUNNER_TEMP "fake-claude"
New-Item -ItemType Directory -Force $fakeDir | Out-Null
$fake = Join-Path $fakeDir "claude.exe"
Add-Type -OutputAssembly $fake -OutputType WindowsApplication -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System.Windows.Forms;
public static class FakeClaude {
  public static void Main() {
    var f = new Form { Text = "Claude", Width = 900, Height = 650, StartPosition = FormStartPosition.CenterScreen };
    f.Controls.Add(new TextBox { Multiline = true, Dock = DockStyle.Bottom, Height = 80 });
    Application.Run(f);
  }
}
"@
for ($round = 1; $round -le 2; $round++) {
  $fp = Start-Process -FilePath $fake -PassThru
  $seen = $false
  for ($t = 0; $t -lt 16 -and -not $seen; $t++) {
    Start-Sleep -Milliseconds 500
    $st = State
    $seen = ($st.bubble -like "*açıldı*" -or $st.bubble -like "*is open*")
  }
  Shot ("10-fake-claude-" + $round)
  Check $seen "Claude açılınca robot fark etti (tur $round)"
  Check ($st.state -ne "Sleeping") "robot uyanık (tur $round)"
  Stop-Process -Id $fp.Id -Force
  Start-Sleep 4
}

Check (-not (Test-Path (Join-Path $home2 "error.log"))) "hata günlüğü boş"
Start-Sleep 2
if ($p.HasExited) { Get-Content (Join-Path $home2 "error.log") -ErrorAction SilentlyContinue; throw "Uygulama çöktü (kod $($p.ExitCode))" }
if (Test-Path (Join-Path $home2 "error.log")) { Write-Host "--- error.log ---"; Get-Content (Join-Path $home2 "error.log") }
Get-ChildItem $home2 | Select-Object Name, Length | Format-Table | Out-String | Write-Host
Stop-Process -Id $p.Id -Force
Write-Host "Duman testi geçti"
