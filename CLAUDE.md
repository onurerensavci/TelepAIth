# TelepAIth — çalışma kuralları

- **Her sürüm hem Mac hem Windows için çıkar.** `VERSION` tek; `release.yml` aynı etikete Mac (`TelepAIth*.zip/.dmg`) ve Windows (`Windows-TelepAIth-x64.zip`) paketlerini koyar. Sadece birini yayınlama.
- **Bir platformda eklenen/değişen özellik diğerine de yapılır** (Mac: `Sources/TelepAIth`, Windows: `windows/`). Ortak mantık Windows'ta `windows/TelepAIth.Core`'da, Mac'tekiyle aynı davranmalı.
- Yayından önce `Build` iş akışının iki işi de (macOS + Windows duman testi) yeşil olmalı.
- Commit mesajları Türkçe. Ayrıntılar: `docs/GELISTIRME.md`.
