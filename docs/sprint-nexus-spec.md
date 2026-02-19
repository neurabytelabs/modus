# Sprint Nexus — MODUS Akıllı Sohbet Katmanı
# 5 İterasyon | 11:00-15:00 CET | 19 Şubat 2026

## Genel Kurallar
- Maliyet SIFIR: Ollama (local) veya en ucuz model (gemini-3-flash)
- Her iterasyon: özellik çalışsın, test geçsin, commit atılsın
- Türkçe rapor + screenshot
- UI değişikliği minimal — backend ağırlıklı
- 5. iterasyon sonunda Mustafa'ya özet rapor

## IT-01 — NexusRouter + Intent Classification (11:00)
**Versiyon:** v5.5.0 Nexus
**Hedef:** Chat mesajını insight/action/casual olarak sınıfla
- `Modus.Nexus.Router` modülü — keyword + pattern matching (LLM yok, hızlı)
- Intent tipleri: `:insight` (soru), `:action` (komut), `:chat` (sohbet)
- Insight alt-tipleri: agent_query, event_query, stats_query, why_query
- Action alt-tipleri: terrain_modify, spawn_entity, config_change, rule_inject
- Birim testleri (en az 10 senaryo)
- Mevcut chat SystemModuleUI'a entegre et

## IT-02 — InsightEngine (12:00)
**Versiyon:** v5.5.1
**Hedef:** Simülasyon durumunu sorgulayabilme
- `Modus.Nexus.InsightEngine` modülü
- Agent state query: konum, enerji, affect, son kararlar
- Position history tracking (son 50 hamle ETS'te tut)
- Event replay: son N olayı listele
- Stats: toplam ajan, ortalama enerji, en mutlu/üzgün ajan
- LLM kullanımı: Ollama (local) ile cevap formatlama — yoksa template string

## IT-03 — ActionEngine (13:00)
**Versiyon:** v5.5.2
**Hedef:** Chat ile dünyayı değiştirebilme
- `Modus.Nexus.ActionEngine` modülü
- Terrain modification: biome değiştir (belirli alan)
- Entity spawning: ajan/hayvan ekle
- Config update: decay rate, speed, danger level
- Safety validation: crash-proof command execution
- Undo desteği (son komut geri al)

## IT-04 — Agent Trace + Why Engine (14:00)
**Versiyon:** v5.5.3
**Hedef:** "Neden?" sorularına gerçek veriyle cevap
- `Modus.Nexus.TraceEngine` modülü
- Agent decision log: her tick'te ne karar verdi, neden
- Position trace: ajan neredeydi, nereye gitti (timeline)
- Disappearance detection: ajan görünür alandan çıkınca log
- "Why" cevapları: decision log + affect state + spatial data birleştir
- Ollama ile natural language explanation (veya template fallback)

## IT-05 — Chat UI Entegrasyonu + Rapor (15:00)
**Versiyon:** v5.6.0 Nexus Complete
**Hedef:** Tüm Nexus özelliklerini UI'da çalıştır
- Chat input → NexusRouter → InsightEngine/ActionEngine
- Insight cevapları özel formatta göster (data + açıklama)
- Action komutları için onay mekanizması (tehlikeli olanlar)
- Multi-turn context (son 5 mesajı hatırla)
- 5 iterasyonun özet raporunu hazırla
- Mustafa'ya Telegram'dan bildir
- Screenshot çek
