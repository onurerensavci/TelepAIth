# Geliştirme

[← README](../README.md)

## Kaynaktan derleme

Gerekli: macOS 13+ ve Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/onurerensavci/TelepAIth.git && cd TelepAIth
scripts/build-app.sh          # build/TelepAIth.app
open build/TelepAIth.app
swift test                    # birim testleri
```

`build-app.sh` sürümü `VERSION` dosyasından, güncelleme deposunu `origin`'den alır, `assets/AppIcon.png`'den `.icns` üretir. `CODESIGN_IDENTITY` ortam değişkeni varsa onunla, yoksa ad-hoc imzalar. Ad-hoc imzalı kopyada Erişilebilirlik izni her derlemede sıfırlanabilir. Kalıcı izin için aşağıdaki imza sertifikasını kullan.

## Proje yapısı

| Dosya | Görevi |
|---|---|
| `Sources/TelepAIth/main.swift` | Giriş noktası (`--mcp` ile anlatıcı sunucusu olarak çalışır) |
| `AppDelegate.swift` | Menü çubuğu, bağlantılar, sağlık durumu |
| `RobotManager.swift` | Hangi AI gösterilecek, pencereye uçma, masaüstleri, kilit |
| `RobotModel.swift` | Olaylardan durum, balon metni, ruh hâlleri, tur özeti |
| `RobotWindow.swift` / `RobotView.swift` | Panel, sürükleme, sağ tık menüsü; kafa, LED gözler, balon çizimi |
| `AppWatcher.swift` | Claude/ChatGPT masaüstü uygulamalarını Erişilebilirlik ile izleme |
| `EventServer.swift` / `AgentEvent.swift` | Yerel HTTP sunucusu, hook/ClaudeBar/genel olay ayrıştırma |
| `HookInstaller.swift` | Claude Code ve Codex hook'ları, Kalkan |
| `MCPServer.swift` | `telepaith_say` anlatıcı aracı ve Claude masaüstü kurulumu |
| `Updater.swift` | GitHub Releases'tan güncelleme |
| `Diagnostics.swift` | Teşhis paneli |

## Sürüm yayınlama

1. `VERSION` dosyasındaki numarayı artır (ör. `0.9.3`) ve main'e gönder.
2. GitHub'da **Actions → Release → Run workflow**. Sürüm kutusu boşsa `VERSION` kullanılır.

Actions uygulamayı derler, imzalar, `v0.9.3` etiketini atar ve Releases'a `TelepAIth-v0.9.3.zip`, `TelepAIth-v0.9.3.dmg` ve sabit adlı `TelepAIth.zip` / `TelepAIth.dmg` kopyalarını koyar. Sabit adlılar README'deki indirme bağlantıları ve Homebrew cask'ı (`Casks/telepaith.rb`) içindir; cask her zaman son sürümü indirir, güncellenmesi gerekmez. Açık TelepAIth'ler 3 saat içinde (ya da açılıştan 15 saniye sonra) yeni sürümü görür, robotun ışığı turuncu yanar. `scripts/release.sh 0.9.3` etiketi bilgisayardan gönderir, aynı işi yapar.

Depo herkese açık olmalı: güncelleme denetimi GitHub API'sine anahtarsız bakar.

## İmza sertifikası

macOS Erişilebilirlik iznini uygulamanın imzasına bağlar. Her sürüm aynı sertifikayla imzalanırsa izin güncellemelerden sonra da kalır. Sertifikayı bir kere oluşturup GitHub'a gizli değer olarak kaydetmek için (kendi `gh` girişinle):

```bash
curl -fsSL https://raw.githubusercontent.com/onurerensavci/TelepAIth/main/scripts/setup-signing.sh | bash
```

Script `TelepAIth Self Signed` adında bir sertifika üretir, `MACOS_CERT_P12` ve `MACOS_CERT_PASSWORD` gizli değerlerine yazar. Özel anahtar sadece GitHub'da durur, depoya girmez. Release iş akışı bu değerler varsa onları kullanır, yoksa ad-hoc imzalar.

## README görselleri

`assets/readme/` altındaki görseller koddan üretilir. Robot, `RobotView.swift`'teki çizimle aynı ölçülerle çizilir:

```bash
python3 scripts/make-readme-art.py
```

Sosyal önizleme (`social-preview.png`) için Playwright + Chrome kullanılır, yoksa `rsvg-convert`. GitHub'a yüklemek için: depo → **Settings → General → Social preview → Edit**.

## Hata ayıklama

- `~/.telepaith/watch-debug.txt`: masaüstü uygulamalarında algılama tutmazsa görülen düğme adları ve metinler.
- Menü → **Teşhis…**: uygulama başına pencere, yazı kutusu, düğmeler, metin akışı, aşama.
- `scripts/send-test.sh claude thinking "Deneme"`: sunucuya elle olay gönderir.
