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
Check ($st.glyph -eq "!") "onay beklerken gözde ! var ($($st.glyph))"
Check ($st.gazeAllowed -eq $false) "sohbetler çalışırken gözler imleci izlemiyor"
for ($t = 0; $t -lt 6 -and $st.minis -lt 1; $t++) { Start-Sleep -Milliseconds 500; $st = State }
Check ($st.minis -eq 1) "minik kafa sadece öteki AI için, tek ($($st.minis))"
Check ($st.extras -ge 1) "kafalarda görünmeyen sohbet kafada ışık ($($st.extras))"
Post '{"agent":"claude","session":"s1","project":"web","state":"done","text":"Bitti"}'
Start-Sleep -Milliseconds 1200
Shot "4-done"
$st = State
Check ($st.state -eq "Done" -or $st.minis -ge 1) "bitti / sıradaki oturum"
# İş bitince kutlama (zıplama/parıltı; başparmak kaldırıldı)
HookEvent "claude" '{"hook_event_name":"Stop","session_id":"s2","cwd":"C:\\proj\\mobile"}'
Start-Sleep -Milliseconds 500
Shot "4b-thumbs-up"
$st = State
Check ($st.celebrating -eq $true -and $st.source -eq "claude") "iş bitince kutlama (Claude ekranda kalır)"
Check ($st.gesture -ne "ThumbsUp") "başparmak yok ($($st.gesture))"
Start-Sleep 3
$st = State
Check ($st.source -eq "gpt") "kutlamadan sonra hâlâ çalışan GPT'ye geçti"

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
# Tıkla → sohbet listesi (ad · durum · süre)
[Mouse]::SetCursorPos([int]$st.head.x, [int]$st.head.y); Start-Sleep -Milliseconds 300
[Mouse]::Down(); Start-Sleep -Milliseconds 60; [Mouse]::Up(); Start-Sleep -Milliseconds 800
Shot "6-clicked-chat-list"
$st = State
Check (@($st.chatList).Count -ge 1) "tıklayınca sohbet listesi açıldı ($($st.chatList -join ' | '))"
Check (@($st.chatList | Where-Object { $_ -match "(çalışıyor|bitti|seni bekliyor) · " }).Count -ge 1) "listede durum ve süre yazıyor"
# Tekrar tıkla → liste kapanır
Start-Sleep -Milliseconds 700
[Mouse]::Down(); Start-Sleep -Milliseconds 60; [Mouse]::Up(); Start-Sleep -Milliseconds 800
$st = State
Check ($st.chatList -eq $null) "tekrar tıklayınca liste kapandı"
# Art arda hızlı tıklayınca başı döner
Start-Sleep -Milliseconds 1700
for ($i = 0; $i -lt 4; $i++) { [Mouse]::Down(); Start-Sleep -Milliseconds 50; [Mouse]::Up(); Start-Sleep -Milliseconds 150 }
Start-Sleep -Milliseconds 300
Shot "6b-dizzy"
$st = State
Check ($st.mood -eq "Dizzy") "hızlı tıklayınca başı döndü ($($st.mood))"
Start-Sleep 3
# Sağ tık → menü (Esc ile kapat)
[Mouse]::RightClick(); Start-Sleep -Milliseconds 800
Shot "7-menu"
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
# Hook dayanıklılığı: 10 oturum arka arkaya, hepsi ulaşmalı
$before = @((State).sessions | Where-Object { $_ -like "claude/x*" }).Count
for ($i = 1; $i -le 10; $i++) {
  HookEvent "claude" ('{"hook_event_name":"PreToolUse","session_id":"x' + $i + '","cwd":"C:\\proj\\p' + $i + '","tool_name":"Read","tool_input":{"file_path":"C:\\proj\\a.cs"}}')
}
Start-Sleep 2
$st = State
$after = @($st.sessions | Where-Object { $_ -like "claude/x*" }).Count
Check ($after -ge $before + 10) "10 hook olayının hepsi ulaştı ($before → $after)"
Check ($st.minis -le 1) "çok oturum olsa da minik kafa AI başına bir ($($st.minis))"
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
# Robottan onay: hook izin ister, robotun balonundaki düğmeye tıklanır, karar hook'un çıktısına yazılır
$hookAbs = (Resolve-Path $Hook).Path
function AskPermission($session) {
  $req = '{"hook_event_name":"PermissionRequest","session_id":"' + $session + '","cwd":"C:\\proj\\api","tool_name":"Bash","tool_input":{"command":"npm install"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm install"}],"behavior":"allow","destination":"localSettings"}]}'
  Start-Job -ScriptBlock { param($h, $home3, $body) $env:TELEPAITH_HOME = $home3; $OutputEncoding = New-Object System.Text.UTF8Encoding $false; $body | & $h permission claude } -ArgumentList $hookAbs, $home2, $req
}
foreach ($case in @(@{ Session = "perm1"; Button = "allow"; Expect = '"behavior":"allow"' }, @{ Session = "perm2"; Button = "always"; Expect = '"updatedPermissions"' }, @{ Session = "perm3"; Button = "deny"; Expect = '"behavior":"deny"' })) {
  $job = AskPermission $case.Session
  $st = $null
  for ($t = 0; $t -lt 20; $t++) { Start-Sleep -Milliseconds 400; $st = State; if ($st.approval -and $st.approval.buttons.($case.Button)) { break } }
  Shot ("11-approval-" + $case.Button)
  Check ($st.approval -ne $null) "izin sorusu balonda ($($case.Button))"
  Check ($st.bubble -like "*npm install*") "balonda sorunun kendisi yazıyor ($($case.Button))"
  $xy = $st.approval.buttons.($case.Button)
  [Mouse]::SetCursorPos([int]$xy[0], [int]$xy[1]); Start-Sleep -Milliseconds 400
  [Mouse]::Down(); Start-Sleep -Milliseconds 60; [Mouse]::Up()
  $done = Wait-Job $job -Timeout 10
  $hookOut = (Receive-Job $job | Out-String).Trim()
  Remove-Job $job -Force
  Write-Host "  hook çıktısı: $hookOut"
  Check ($hookOut -like ("*" + $case.Expect + "*")) "düğmeye tıklayınca karar Claude Code'a gitti ($($case.Button))"
  Start-Sleep -Milliseconds 800
}
# Robot kapalıyken ya da ayar kapalıyken hook hemen boş döner (soru terminalde çıkar): bağlantı kurulamayan port
$env:TELEPAITH_HOME_SAVE = $env:TELEPAITH_HOME
$empty = Join-Path $env:RUNNER_TEMP "tp-empty"; New-Item -ItemType Directory -Force $empty | Out-Null; Set-Content (Join-Path $empty "port") "19899"
$sw = [Diagnostics.Stopwatch]::StartNew()
$env:TELEPAITH_HOME = $empty
$o = '{"hook_event_name":"PermissionRequest","session_id":"x","tool_name":"Bash","tool_input":{"command":"ls"}}' | & $hookAbs permission claude
$env:TELEPAITH_HOME = $env:TELEPAITH_HOME_SAVE
Check ([string]::IsNullOrWhiteSpace($o) -and $sw.Elapsed.TotalSeconds -lt 5) "robot yokken hook beklemeden boş döner ($([int]$sw.Elapsed.TotalSeconds) sn)"

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
    // Yan menü: arkada çalışan bir sohbet (8 sn sonra biter)
    var side = new Label { Text = "Sohbet B · running", Left = 10, Top = 40, Width = 250 };
    f.Controls.Add(side);
    var timer = new Timer { Interval = 8000 };
    timer.Tick += (s, e) => { side.Text = "Sohbet B"; timer.Stop(); };
    timer.Start();
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
  if ($round -eq 1) { Check ($st.gesture -eq "Wave") "uygulama açılınca el salladı ($($st.gesture))" }
  Shot ("10-fake-claude-" + $round)
  Check $seen "Claude açılınca robot fark etti (tur $round)"
  Check ($st.state -ne "Sleeping") "robot uyanık (tur $round)"
  Stop-Process -Id $fp.Id -Force
  Start-Sleep 4
}

# Arkadaki sohbet: yan menüde "· running" yazan sohbet izlenir (minik kafa), yazı kaybolunca "bitti" gelir
$fp = Start-Process -FilePath $fake -PassThru
$bg = $false
for ($t = 0; $t -lt 14 -and -not $bg; $t++) {
  Start-Sleep -Milliseconds 500
  $st = State
  $bg = @($st.sessions | Where-Object { $_ -like "claude/bg-*" }).Count -gt 0
}
Shot "11-background-chat"
Check $bg "yan menüde çalışan sohbet arkada izleniyor ($($st.sessions -join ', '))"
$done = $false
for ($t = 0; $t -lt 30 -and -not $done; $t++) {
  Start-Sleep -Milliseconds 500
  $st = State
  $done = @($st.recent | Where-Object { $_ -like "*claude/bg-* Stop*" }).Count -gt 0
}
Check $done "arkadaki sohbet bitince 'bitti' geldi"
Stop-Process -Id $fp.Id -Force
Start-Sleep 2

Check (-not (Test-Path (Join-Path $home2 "error.log"))) "hata günlüğü boş"
Start-Sleep 2
if ($p.HasExited) { Get-Content (Join-Path $home2 "error.log") -ErrorAction SilentlyContinue; throw "Uygulama çöktü (kod $($p.ExitCode))" }
if (Test-Path (Join-Path $home2 "error.log")) { Write-Host "--- error.log ---"; Get-Content (Join-Path $home2 "error.log") }
Get-ChildItem $home2 | Select-Object Name, Length | Format-Table | Out-String | Write-Host
Stop-Process -Id $p.Id -Force
Write-Host "Duman testi geçti"
