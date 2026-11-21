# CI duman testi: uygulamayı açar, olay gönderir, ekran görüntüsü alır, çökmediğini doğrular.
param([string]$Exe, [string]$Hook, [string]$Out = "shots")
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $Out | Out-Null
$home2 = Join-Path $env:RUNNER_TEMP "tp-home"
New-Item -ItemType Directory -Force $home2 | Out-Null
$env:TELEPAITH_PORTABLE = "1"
$env:TELEPAITH_HOME = $home2

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
function Shot($name) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $op = [System.Drawing.CopyPixelOperation]::SourceCopy -bor [System.Drawing.CopyPixelOperation]::CaptureBlt
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size, $op)
  $bmp.Save((Join-Path $Out "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "shot $name ($($b.Width)x$($b.Height))"
}
function Post($json) {
  $port = (Get-Content (Join-Path $home2 "port")).Trim()
  Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$port/event" -Body $json -ContentType "application/json" | Out-Null
}
function HookEvent($source, $json) { $json | & $Hook hook $source }

$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep 8
if ($p.HasExited) { Get-Content (Join-Path $home2 "error.log") -ErrorAction SilentlyContinue; throw "Uygulama açılır açılmaz kapandı (kod $($p.ExitCode))" }
Shot "1-start"

$port = (Get-Content (Join-Path $home2 "port")).Trim()
$health = Invoke-RestMethod "http://127.0.0.1:$port/health"
Write-Host "health: $health"

Post '{"agent":"claude","session":"s1","project":"web","state":"thinking","text":"Düşünüyor…"}'
Start-Sleep 2
Shot "2-thinking"
Post '{"agent":"claude","session":"s1","project":"web","state":"waiting","text":"Onayını bekliyor: npm install"}'
HookEvent "gpt" '{"hook_event_name":"UserPromptSubmit","session_id":"g1","cwd":"C:\\proj\\api","prompt":"testleri düzelt"}'
HookEvent "claude" '{"hook_event_name":"PreToolUse","session_id":"s2","cwd":"C:\\proj\\mobile","tool_name":"Bash","tool_input":{"command":"npm test"}}'
Start-Sleep 3
Shot "3-waiting-minis"
Post '{"agent":"claude","session":"s1","project":"web","state":"done","text":"Bitti"}'
Start-Sleep 1.2
Shot "4-done"

Start-Sleep 2
if ($p.HasExited) { Get-Content (Join-Path $home2 "error.log") -ErrorAction SilentlyContinue; throw "Uygulama çöktü (kod $($p.ExitCode))" }
if (Test-Path (Join-Path $home2 "error.log")) { Write-Host "--- error.log ---"; Get-Content (Join-Path $home2 "error.log") }
Get-ChildItem $home2 | Select-Object Name, Length | Format-Table | Out-String | Write-Host
Stop-Process -Id $p.Id -Force
Write-Host "Duman testi geçti"
