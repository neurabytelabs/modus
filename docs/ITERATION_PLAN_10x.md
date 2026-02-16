# MODUS — 10 İterasyon Geliştirme Planı
## v0.5.0 → v1.5.0 | "Genesis'ten Deus'a"

> "The order and connection of ideas is the same as the order and connection of things" — Spinoza

**Başlangıç:** 16 Şubat 2026, 20:00 CET
**Bitiş:** 17 Şubat 2026, 01:00 CET
**Toplam:** 5 saat (10 × 30 dakika)
**Pattern:** NeuraByte Iteration Sprint™

---

## İterasyon 1 — v0.6.0 Imperium (20:00-20:30)
**Tema:** "Komut ve Kontrol"
**Spinoza:** *Imperium* — İrade ve yönetme gücü

**Hedef:** Çok adımlı komut sistemi + agent hafıza entegrasyonu

**Yapılacaklar:**
- `protocol/command_executor.ex` — Çok adımlı komut zinciri: "Git X'i bul, mesaj ilet"
- `protocol/intent_parser.ex` güncelleme — LLM fallback: regex eşleşmezse küçük model ile parse
- `mind/conversation_memory.ex` — Son 10 konuşmayı agent state'e kaydet
- Chat geçmişi LLM bağlamına enjekte (ContextBuilder güncelle)
- 5+ yeni test

**Başarı Kriteri:** "Kuzeye git ve oradaki kişiyle konuş" komutu çalışır

---

## İterasyon 2 — v0.7.0 Societas (20:30-21:00)
**Tema:** "Toplum ve Grup Dinamikleri"
**Spinoza:** *Societas* — Toplumsal bağ

**Hedef:** Agent grupları/takımlar + kolektif davranış

**Yapılacaklar:**
- `mind/cerebro/group.ex` — Grup oluşturma (leader + members, max 4)
- Grup tabanlı karar: lider karar verir, üyeler takip eder
- Grup görsel: renderer'da aynı renk halo ile göster
- SocialNetwork'e grup ilişkisi ekle
- Grup sohbeti: 3+ agent aynı anda konuşabilir
- 5+ yeni test

**Başarı Kriteri:** 3 agent grup kurar, birlikte hareket eder

---

## İterasyon 3 — v0.8.0 Memoria (21:00-21:30)
**Tema:** "Uzun Vadeli Hafıza"
**Spinoza:** *Memoria* — Deneyimin kalıcılaşması

**Hedef:** SQLite tabanlı kalıcı agent hafızası + öğrenme

**Yapılacaklar:**
- `persistence/agent_memory.ex` — Ecto schema: agent_memories table
- Önemli olayları SQLite'a kaydet (ölüm, arkadaşlık, keşif)
- World load'da hafızayı da yükle
- Agent "hatırlama" — geçmiş deneyimlerden öğrenme
- ContextBuilder'a uzun vadeli hafıza ekle
- 5+ yeni test

**Başarı Kriteri:** Agent save/load sonrası geçmiş konuşmaları hatırlar

---

## İterasyon 4 — v0.9.0 Natura (21:30-22:00)
**Tema:** "Doğa ve Çevre Etkileşimi"
**Spinoza:** *Natura* — Doğanın düzeni

**Hedef:** Dinamik çevre + kaynak sistemi + mevsimler

**Yapılacaklar:**
- `simulation/environment.ex` — Gece/gündüz döngüsü (her 500 tick)
- `simulation/resource_system.ex` — Yenilenebilir kaynaklar (yiyecek spawn, tükenme, yeniden büyüme)
- Arazi etkisi: orman=yiyecek bol, dağ=shelter bol, su=tehlikeli
- Renderer'da gece/gündüz renk değişimi
- Agent'lar kaynak toplarken gerçek resource objelerini tüketsin
- 5+ yeni test

**Başarı Kriteri:** Kaynaklar tükenir ve yeniden büyür, gece/gündüz görünür

---

## İterasyon 5 — v1.0.0 Substantia (22:00-22:30)
**Tema:** "Öz ve Bütünlük — İlk Tam Sürüm"
**Spinoza:** *Substantia* — Her şeyin özü, tek töz

**Hedef:** Ekonomi sistemi + doğum/ölüm dengesi + v1.0 polish

**Yapılacaklar:**
- `simulation/economy.ex` — Basit takas sistemi: agent'lar kaynak paylaşabilir
- `simulation/lifecycle.ex` — Doğum mekanizması (2 mutlu agent → yeni agent spawn)
- Ölüm/doğum dengesi (POP 8-15 arası stabil)
- Top bar'da ekonomi göstergeleri
- Version bump v1.0.0 + CHANGELOG
- 5+ yeni test

**Başarı Kriteri:** Nüfus kendini sürdürür (doğum+ölüm), takas çalışır

---

## İterasyon 6 — v1.1.0 Harmonia (22:30-23:00)
**Tema:** "Denge ve Uyum"
**Spinoza:** *Harmonia* — Doğanın dengesi

**Hedef:** UI/UX polish + performans optimizasyonu

**Yapılacaklar:**
- Renderer optimizasyonu: sprite pooling, frustum culling
- Agent detail panel redesign (daha kompakt, daha bilgilendirici)
- Mini-map (sağ üst köşe)
- Tooltip'ler: agent üzerine hover → kısa bilgi
- Keyboard shortcuts: Space=pause, 1/5/0=speed, M=minimap
- Performans: 50 agent'ta 60fps hedef
- Bug fix sweep

**Başarı Kriteri:** 50 agent smooth, minimap çalışır, keyboard shortcuts aktif

---

## İterasyon 7 — v1.2.0 Infinitas (23:00-23:30)
**Tema:** "Sonsuzluk ve Ölçek"
**Spinoza:** *Infinitas* — Sonsuz potansiyel

**Hedef:** Büyük dünya desteği + world generation iyileştirme

**Yapılacaklar:**
- Grid boyutu: 50×50 → 100×100 (configurable)
- Chunk-based rendering (sadece görünen alanı render et)
- Daha zengin world generation: köy merkezleri, yollar, su kaynakları
- Biome sistemi: her bölgenin karakteri (orman köyü, sahil kasabası)
- World seed sistemi: aynı seed → aynı dünya
- 5+ yeni test

**Başarı Kriteri:** 100×100 dünya smooth render, biome'lar görünür

---

## İterasyon 8 — v1.3.0 Sapientia (23:30-00:00)
**Tema:** "Bilgelik ve Öğrenme"
**Spinoza:** *Sapientia* — Akıl yoluyla özgürlük

**Hedef:** Agent öğrenme sistemi + kültür aktarımı

**Yapılacaklar:**
- `mind/learning.ex` — Agent beceri sistemi (farming, building, social)
- Beceriler deneyimle gelişir (gather→farming skill↑)
- Kültür aktarımı: yeni doğan agent, ebeveynlerden beceri miras alır
- Agent "mesleki uzmanlaşma" — yüksek skill=daha verimli
- Detail panel'de beceri çubukları
- 5+ yeni test

**Başarı Kriteri:** Agent'lar beceri kazanır, yeni nesil miras alır

---

## İterasyon 9 — v1.4.0 Potentia (00:00-00:30)
**Tema:** "Güç ve Yetenek"
**Spinoza:** *Potentia* — Var olma gücü

**Hedef:** Event sistemi genişletme + storytelling + timeline

**Yapılacaklar:**
- `simulation/story_engine.ex` — Otomatik hikaye üretimi (önemli olaylardan)
- Timeline view: sol panel'de zaman çizelgesi (doğum, ölüm, keşif, savaş)
- Notification toasts: önemli olaylar ekranda belirsin
- "Chronicle" — dünya tarihini markdown olarak dışa aktar
- Stat dashboard: nüfus grafiği, kaynak grafiği, ilişki ağı
- 5+ yeni test

**Başarı Kriteri:** Timeline görünür, hikaye üretilir, chronicle export çalışır

---

## İterasyon 10 — v1.5.0 Deus (00:30-01:00)
**Tema:** "Tanrı Görüşü — Tam Platform"
**Spinoza:** *Deus sive Natura* — Tanrı ya da Doğa

**Hedef:** Final polish + demo kalitesi + God Mode

**Yapılacaklar:**
- "God Mode" toggle: tüm agent bilgilerini göster/gizle
- Cinematic camera: auto-follow ilginç olaylar
- Screenshot/video export butonu
- Landing page: simülasyon hakkında bilgi + "Create World" CTA
- Final bug sweep + performance tuning
- README tamamen güncelle
- Demo senaryosu hazırla ve test et
- 5+ yeni test

**Başarı Kriteri:** Demo kalitesinde ürün, izlenebilir hikaye, smooth UX

---

## Özet Tablo

| # | Saat | Versiyon | İsim | Tema |
|---|------|----------|------|------|
| 1 | 20:00 | v0.6.0 | Imperium | Çok adımlı komutlar |
| 2 | 20:30 | v0.7.0 | Societas | Grup dinamikleri |
| 3 | 21:00 | v0.8.0 | Memoria | Kalıcı hafıza |
| 4 | 21:30 | v0.9.0 | Natura | Dinamik çevre |
| 5 | 22:00 | v1.0.0 | Substantia | Ekonomi + yaşam döngüsü |
| 6 | 22:30 | v1.1.0 | Harmonia | UI/UX + performans |
| 7 | 23:00 | v1.2.0 | Infinitas | Ölçek + world gen |
| 8 | 23:30 | v1.3.0 | Sapientia | Öğrenme + kültür |
| 9 | 00:00 | v1.4.0 | Potentia | Storytelling + timeline |
| 10 | 00:30 | v1.5.0 | Deus | Final polish + demo |

---

## NeuraByte Iteration Sprint™ Pattern

Bu iş akış modeli tekrar kullanılabilir:
1. Her iterasyon 30 dakika (sub-agent ile implementasyon)
2. RUNE ile plan zenginleştirme
3. Gemini ile görsel durum raporu
4. Bug fix → test → commit → push → rebuild
5. Sonraki iterasyona hazırlık

**Uygulanabilir projeler:** MODUS, neurabytelabs.com, RUNE, Conatus, SpinozaOS
