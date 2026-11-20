<p align="center"><img src="assets/logo.svg" width="160" alt="TelepAIth"></p>

<h1 align="center">TelepAIth</h1>

Ekranının köşesinde süzülen, LED nokta gözlü küçük bir robot kafası. Claude ve GPT o an ne yapıyorsa okur (Claude Code, Codex ve Claude/ChatGPT masaüstü uygulamaları), başının üstündeki balonla söyler, iş bitince ya da seni beklerken bildirim atar. Claude'a geçince gözleri turuncu, GPT'ye geçince mavi yanar. İstediğin başka bir AI'ı da bağlayabilirsin.

- **Durumlar:** düşünüyor, okuyor, arıyor, düzenliyor, komut çalıştırıyor, alt ajan çalıştırıyor, seni bekliyor, bitti, hata, uyuyor
- **Robot:** gövdesiz bir kafa; gözleri minik LED noktalarından oluşur ve duruma göre desen değiştirir (düşünürken yukarı bakar, okurken sağa sola tarar, bitince ^^ olur, hata olunca X). Alnındaki ışık sağlık göstergesi: **yeşil** her şey yolunda, **turuncu** güncelleme var (robot balonda da söyler; tıklarsan kurar), **kırmızı** bir şey çalışmıyor (tıklarsan sebebini söyler). Düşünürken başından telepati halkaları yayılır, bitince zıplar, hata olunca sarsılır, 10 dakika olay gelmezse uyur. Boştayken ara sıra laf atar (menüden kapatılabilir).
- **Ruh hâlleri (mochi gibi):** teşekkür edince gözleri kalp olur, "çalışmıyor/neden" deyince gerilir, BÜYÜK HARFLE yazınca şaşırır; `rm -rf` gibi tehlikeli komutta korkar; testler geçince parti yapar, kırılınca başı döner; commit'te gururlanır, push'ta sevinir; üst üste 3 hatada sersemler. İş bitince tur özeti verir: süre · araç sayısı · düzenleme sayısı. İstersen kısa sesler de çalar (menü → Sesler).
- **Hangi AI:** gözlerinin renginden anlarsın: öndeki uygulama Claude ise turuncu, Codex ya da ChatGPT ise mavi. Başka bir uygulamadaysan (Terminal gibi) seni bekleyen ya da o an çalışan AI'ı gösterir. Kendi eşlemen için config.json'a `"apps": {"uygulama.bundle.id": "claude"}` ekleyebilirsin.
- **Pencereye uçma:** Claude'a, ChatGPT'ye ya da Codex'e geçince robot o pencerenin sağ-alt köşesine uçar, pencereyi taşırsan peşinden gelir; başka uygulamalara geçince olduğu yerde kalır (menü → AI penceresine gitsin).
- **Masaüstleri (Spaces):** robot her masaüstünde görünmez; Claude/GPT hangi masaüstündeyse orada kalır. Başka masaüstüne geçince orada kalmaya devam eder, Claude ya da GPT'ye dönünce onunla birlikte gelir. Menü → Robotu bu masaüstüne getir ile istediğin masaüstüne çağırabilirsin.
- **Her zaman üstte:** robota sağ tık → 📌 Her zaman üstte (varsayılan açık). Kapatınca robot normal bir pencere gibi davranır, öndeki pencereler onu örtebilir.
- **Kilit:** robota sağ tık → 🔒 Kilitle: olduğu yerde ve olduğu masaüstünde kalır, sürüklenmez, Claude/GPT'ye tıklayınca uçmaz. Aynı menüden kilidi açılır (menü çubuğunda da var).
- **Etkileşim:** robota tıkla → son 5 olay; sürükle → taşı (başka monitöre de), bir köşeye yaklaştırıp bırakınca o ekranın köşesine yapışır; sağ tık → gizle
- **Bildirim:** 20 saniyeden uzun süren iş bitince, AI senden onay/cevap beklerken ve hata olunca
- **Kota:** ClaudeBar kuruluysa, kota azalınca ilgili robot uyarır
- **Dil:** Türkçe veya İngilizce (menü → Dil). İlk açılışta sistem dilini kullanır.
- **Emojiler:** robot eyleme göre emojiyle konuşur: düşünürken 🔮, okurken 📖, test çalıştırırken 🧪, paket kurarken 📦, `git push`'ta 🚀, bitince 🎉/✨/✅, seni beklerken ✋. Menü → Emojiler ile kapatılabilir.

## Kurulum

Gerekli: macOS 13+ ve Xcode Command Line Tools (`xcode-select --install`).

```bash
cd TelepAIth
chmod +x scripts/*.sh
scripts/build-app.sh
open build/TelepAIth.app
```

Menü çubuğunda bir sihirli değnek ikonu çıkar, ekranın altında da turuncu robot belirir. Kalıcı kurmak için `build/TelepAIth.app`'i Uygulamalar klasörüne kopyala. Bildirim izni sorulursa izin ver.

İlk denemede menüden **Dene → Claude: kısa bir görev** seç. Robotun düşünüp, okuyup, düzenleyip, komut çalıştırıp zıpladığını görürsün.

## GitHub ve güncellemeler

Depo **herkese açık (public)** olmalı; güncelleme denetimi GitHub API'sine anahtarsız bakıyor.

Depo: https://github.com/onurerensavci/telepaith — her push'ta GitHub Actions kodu macOS'ta derler (Actions sekmesinde yeşil tik = derleniyor).

**Sürüm yayınlama:**

1. Bir değişiklik bitince `VERSION` dosyasındaki numarayı artır (ör. `0.2.0`) ve main'e gönder.
2. GitHub'da **Actions → Release → Run workflow → Run workflow**. Sürüm kutusunu boş bırakırsan `VERSION` dosyasındaki numara kullanılır.

Actions uygulamayı derler, `v0.2.0` etiketini atar ve Releases'a `TelepAIth-v0.2.0.zip` olarak koyar. Bilgisayarında depo klonu varsa `scripts/release.sh 0.2.0` de aynı işi yapar.

**Kullanıcı tarafı:** İlk sürümü Releases'tan indirip Uygulamalar'a koy. İnternetten indirilen imzasız uygulama ilk açılışta engellenir: sağ tık → Aç, ya da `xattr -dr com.apple.quarantine /Applications/TelepAIth.app`. Sonraki sürümlerde uygulama açılıştan 15 saniye sonra ve 3 saatte bir GitHub'a bakar; yeni sürüm varsa robotun alnı turuncu yanar ve balonda söyler, yeni sürüm varsa bildirim gelir, menüde **⬆︎ Güncelle** çıkar. Tıklayınca indirir, eski sürümün yerine koyar ve yeniden açılır (sorun olursa eskiyi geri koyar). Menüdeki **Güncellemeleri denetle…** ile elle de bakabilirsin.

Yerelde `scripts/build-app.sh` ile derlenen kopya da, `origin` GitHub deposuysa güncellemeleri oradan denetler.

## Bağlantılar

Menü → **Bağlantılar**:

- **Claude ve ChatGPT uygulamaları:** Claude, ChatGPT ve Codex masaüstü uygulamalarında AI'ın çalıştığını, onay beklediğini ve bitirdiğini ekrandaki düğmelerden ("Durdur", "İzin ver") anlar. macOS'un **Erişilebilirlik** iznini ister: Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik → TelepAIth. Uygulama imzasız olduğu için her güncellemeden sonra bu izni kapatıp açman gerekebilir; menüde ⚠︎ uyarısı çıkarsa bundandır. Varsayılan olarak açıktır; ilk açılışta izin ister. Çalışırken yazı kutusunun hemen üstündeki durum satırını (ör. "Mapping the dot grid onto the shapes") okuyup balonda söyler. Menüde her uygulama için ne gördüğü yazar (izleniyor / çalışıyor / onay bekliyor / yazı kutusu bulunamadı). Algılama tutmazsa düğme adlarını `~/.telepaith/watch-debug.txt` dosyasına yazar (menü → Algılama günlüğünü aç); bu dosyayı paylaşırsan algılamayı düzeltmek kolaylaşır.

- **Claude Code:** `~/.claude/settings.json`'a hook ekler. Yeni açılan oturumlar robota haber verir. İlk değişiklikten önce dosyanın yedeği `settings.json.telepaith-backup` olarak alınır.
- **Codex (GPT):** `~/.codex/hooks.json`'a hook ekler. Codex yeni hook'lar için onay istiyor: Codex'i açınca `/hooks` yazıp TelepAIth hook'larını onayla.
- Tekrar tıklayınca hook'lar kaldırılır. Başka araçların hook'larına dokunulmaz; TelepAIth kendi kayıtlarını `__telepaith_hook` işaretinden tanır.

Hook'lar olayı arka planda gönderip hemen çıkar, yani Claude Code ya da Codex'i yavaşlatmaz. TelepAIth kapalıysa istek sessizce düşer.

### ClaudeBar kota uyarıları

ClaudeBar → Settings → Sync & Alerts → Webhooks → Add Webhook:

- URL: `http://localhost:19850/claudebar`
- Channel: **JSON**
- Sends: Quota alerts + Status alerts

Menüdeki **ClaudeBar kota uyarıları…** URL'yi panoya kopyalar.

## Anlatıcı: Claude kendisi söylesin

Ekrandan tahmin etmek yerine Claude'un robota doğrudan "şunu yapıyorum" demesi için TelepAIth küçük bir MCP aracı (`telepaith_say`) içerir.

1. Menü → Bağlantılar → **Anlatıcı (Claude kendisi söylesin)**. Claude masaüstünün MCP ayarına eklenir (`claude_desktop_config.json`, ilk değişiklikten önce yedeği alınır).
2. Claude uygulamasını kapatıp aç.
3. Claude → Ayarlar → Profil tercihlerine şu talimatı ekle (açılan pencerede kopyalama düğmesi var): *"Çalışırken her önemli adımın başında telepaith_say aracıyla ne yaptığını kısa Türkçe bir cümleyle söyle, iş bitince state "done" ile haber ver."*

Claude Code için Terminal'de bir kere: `claude mcp add --scope user telepaith -- "/Applications/TelepAIth.app/Contents/MacOS/TelepAIth" --mcp --source claude`

## Kalkan

Claude Code bağlıyken `rm -rf`, `git push --force`, `git reset --hard`, `DROP TABLE` gibi tehlikeli görünen komutlarda Claude Code senden onay ister (komutu engellemez, sadece sordurur). Menü → Bağlantılar → Claude Code altındaki **Kalkan** ile kapatılabilir.

## Teşhis

Menü → **Teşhis…** (ya da robota sağ tık): robotun her uygulamada ne gördüğünü gösterir: pencere, yazı kutusu, Durdur/Gönder/İzin ver düğmeleri, metin akışı, aşama, düğme adları. **Panoya kopyala** ile raporu paylaşabilirsin.

## Diğer

- **Çift tıklama:** robota çift tıklayınca o an gösterdiği AI'ın uygulamasını öne getirir.
- **Sesli konuşma:** menü → Sesli konuşsun; iş bitince, seni beklerken ve güncelleme olunca Türkçe sesli söyler.
- **Testler:** `swift test` (GitHub'da her push'ta çalışır).

## Kendi AI'ını bağla

Herhangi bir araç `POST` ile olay gönderebilir. Yeni bir `source` ilk olayda yeni bir robot olarak belirir.

```bash
curl -s -H 'Content-Type: application/json' \
  -d '{"state":"running","text":"Testleri çalıştırıyor","project":"app"}' \
  "http://127.0.0.1:19850/event?source=gemini"
```

| Alan | Açıklama |
|---|---|
| `state` | `idle`, `thinking`, `reading`, `searching`, `editing`, `running`, `delegating`, `waiting`, `done`, `error` |
| `text` | Balonda görünecek metin |
| `project` | Balonda küçük başlık (isteğe bağlı) |
| `session` | Aynı AI'da birden fazla oturum varsa ayırmak için (isteğe bağlı) |
| `notify` | `true` ise `done` olayında süre beklemeden bildirim atar |
| `emoji` | Balonda metnin önüne konacak emoji (isteğe bağlı; yoksa duruma göre seçilir) |

Claude Code/Codex formatında (`hook_event_name` içeren) JSON da kabul edilir. Örnek: `scripts/send-test.sh gemini done "Hepsi geçti"`.

Sunucu sadece bu Mac'ten gelen istekleri kabul eder (loopback), tarayıcıdaki sayfaların isteklerini reddeder. Port doluysa sıradaki port kullanılır; geçerli port `~/.telepaith/port` dosyasındadır.

## Renkler

`~/.telepaith/config.json` (menü → Ayar klasörünü aç):

```json
{
  "longTurnSeconds": 20,
  "sources": {
    "claude": { "name": "Claude", "color": "#D97757" },
    "gpt":    { "name": "GPT",    "color": "#3B82F6" },
    "gemini": { "name": "Gemini", "color": "#8B5CF6" }
  }
}
```

Değiştirdikten sonra menü → **Renkleri ve kostümleri yeniden yükle**.

## Kostümler (GPT görselleri)

Robot normalde kodla çizilir. GPT'ye çizdirdiğin karakteri koymak için:

1. `docs/GORSEL-PROMPT.md`'deki prompt ile 5×2'lik kafa tablosunu ürettir (şeffaf arka plan).
2. Turuncu sürümü `~/.telepaith/skins/claude/sheet.png`, mavi sürümü `~/.telepaith/skins/gpt/sheet.png` olarak kaydet.
3. Menü → **Renkleri ve kostümleri yeniden yükle**.

Tablo sırası: 1. satır `idle, thinking, reading, searching, editing`; 2. satır `running, waiting, done, error, sleeping`. Tablo yerine tek tek `idle.png`, `waiting.png` gibi dosyalar da koyabilirsin; tek dosyalar tablodakini ezer. Kaynağa özel klasör yoksa `skins/default/` kullanılır.

Uygulama ikonu `assets/AppIcon.png` (kaynağı `assets/logo.svg`). Değiştirmek için bu PNG'yi 1024×1024 yeni bir görselle değiştir; derleme sırasında .icns otomatik üretilir.

## Sorun giderme

- **Robot hiç tepki vermiyor:** menüde iki tik var mı bak (`Bağlantılar`). Claude Code oturumunu yeniden başlat. `curl http://127.0.0.1:19850/` "TelepAIth çalışıyor" demeli.
- **Codex tepki vermiyor:** Codex'te `/hooks` yazıp hook'ları onayladın mı?
- **Bildirim gelmiyor:** Sistem Ayarları → Bildirimler → TelepAIth. Uygulamayı `swift run` ile çıplak çalıştırırsan bildirimler `osascript` ile gelir.
- **ClaudeBar'ın kota ölçümleri robotu oynatıyor:** olmamalı; hook, ClaudeBar'ın `CLAUDEBAR_PROBE` işaretli oturumlarını yok sayar.

## Yol haritası

- ChatGPT ve Claude masaüstü uygulamaları (Erişilebilirlik API'siyle "yazıyor/bitti" algılama)
- claude.ai ve chatgpt.com için tarayıcı eklentisi
- Mochi'deki gibi tehlikeli komut kalkanı (`rm -rf`, force push…)
- Robotun yanında kota halkaları

## Teşekkür

Fikir [mochi](https://github.com/oztrkemree/mochi)'den, hook yaklaşımı (localhost'a POST, port dosyası, probe işareti) [ClaudeBar](https://github.com/tddworks/claudebar)'dan esinlendi.
