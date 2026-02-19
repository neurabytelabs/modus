# Sprint v6 "Divinus" — RICK Direktifi
## Onay: Patron (Mustafa Saraç) — 2026-02-19
## Koordinatör: RICK (M3)

## Hedef
4 saatte 8 iterasyon. Chat + God Mode + Demo-Ready.

## Kurallar
- Her iterasyonda RUNE.md framework kullan (8-Layer + Spinoza Validator)
- 30dk = 1 iterasyon
- Her iterasyon sonunda kısa rapor (docs/sprint-v6-log.md'ye append et)
- Test %70 altına düşerse STOP
- Budget: $30 limit

## İterasyon Planı

### IT-01 (30dk): God Mode Command Executor
- Router action intent'leri çalışsın: terrain_modify, spawn_entity, config_change, rule_inject
- "Fırtına gönder" yazınca gerçekten fırtına tetiklensin
- Test yaz

### IT-02 (30dk): Chat Personality Enhancement  
- Agent yanıtları Big Five + Affect state'e göre şekillensin
- Korkan agent farklı, mutlu agent farklı konuşsun
- Mevcut DialogueSystem'e entegre

### IT-03 (30dk): Conversation Memory
- Agent kullanıcıyla geçmiş sohbetleri hatırlasın
- EpisodicMemory'ye user_chat kategori ekle
- "Daha önce bana ne söylemiştin?" çalışsın

### IT-04 (30dk): Prayer Response System
- Agent dua eder → UI'da görünsün
- Kullanıcı yanıt verebilsin → agent affect değişsin
- PrayerSystem GenServer

### IT-05 (30dk): Agent-to-Agent Chat Viewer
- DialogueSystem konuşmalarını frontend'de canlı stream
- Read-only chat log paneli
- Filtreleme: topic bazlı

### IT-06 (30dk): Demo Mode
- Read-only izleme modu, login gerektirmesin
- URL: /demo veya /watch
- Temel metrikleri göster

### IT-07 (30dk): RUNE CLI Entegrasyonu
- RUNE.md'yi Modus'un system prompt'larına entegre et
- LLM provider'lar RUNE framework ile çalışsın
- Prompt kalitesi artışını test et

### IT-08 (30dk): Polish + Deploy Hazırlık
- Tüm testleri çalıştır
- Bug fix
- docker-compose prod config
- CHANGELOG güncelle
- Sprint raporu yaz

## Rapor Formatı
Her IT sonunda docs/sprint-v6-log.md'ye:
```
## IT-XX — [İsim] — [Saat]
✅ Tamamlanan:
🔄 Devam eden:
🚫 Blocker:
Test: XX/XX passed
```

## Override
- PAUSE: Patron veya Rick durdurabilir
- REDIRECT: Öncelik değişikliği yapılabilir
- BUDGET: $30 aşılırsa STOP

## EK GÖREV: Prompt Amplification (RUNE v1.6)
- arXiv:2512.14982 — Google Research bulgularını entegre et
- lib/modus/intelligence/llm_provider.ex'e prompt repetition ekle
- Non-reasoning çağrılarda otomatik prompt tekrarlama
- Reasoning modda bypass
- Test: aynı prompt ile before/after karşılaştırma
- RUNE.md güncellendi (Section 5 eklendi)
