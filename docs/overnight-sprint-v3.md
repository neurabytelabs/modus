# MODUS Sprint v3 — "Truly Alive"
> 17 Şubat 2026, 15:00-06:00 (15 iterations × 1h)
> RUNE-enhanced development sprint

## Philosophy
"Bir agent gerçekten yaşıyor mu? Öğreniyor mu? Hatırlıyor mu? Planlıyor mu? Üretiyor mu?"
Bu sprint, MODUS agent'larını gerçekten otonom, öğrenen, üreten varlıklara dönüştürüyor.

## Current State: v2.3.0 Amor
- 62 modül, 214 test (37 failing ⚠️)
- Spinoza Mind Engine: Conatus + Affect + Memory + Reasoning
- Wildlife, Buildings, Resources, Seasons, Culture, History, Observatory
- Multi-LLM: Antigravity (60+ model) + Gemini + Ollama
- Docker: modus-app + modus-llm

## Sprint v3 Hedefler
1. **Zero Failures** — 37 test fix + yeni testler
2. **Deep Agent Intelligence** — gerçek öğrenme, planlama, hafıza
3. **Emergent Economy** — ticaret, para, pazar dinamikleri
4. **Agent Creativity** — hikaye, isim, gelenek üretimi
5. **Ecology** — yaban hayatı üremesi, besin zinciri
6. **Social Depth** — ittifaklar, diplomasi, liderlik
7. **Crafting & Skills** — zanaat, uzmanlık, beceri ağacı
8. **Performance** — düşük kaynak, ETS optimizasyon
9. **Data-Driven UI** — LiveView ile zengin veri gösterimi

## Lessons Learned (Sprint v2'den)
- GenServer.call blocking → :persistent_term veya ETS kullan
- Float.round guard → ensure_float() her yerde
- Sub-agent'lara detaylı spec ver → kalite artar
- Test isolation → PubSub start_supervised çakışması fix edilmeli
- JSON int/float → her zaman explicit cast
- Docker rebuild sonrası test → her iteration sonunda

---

## IT-01 (15:00) — v2.4.0 Veritas: Test Stabilization & Foundation
**"Sağlam temel olmadan yüksek bina olmaz"**

### Görevler
- [ ] Fix 37 failing tests (PubSub isolation, Float guards, missing modules)
- [ ] Test helper: shared setup for PubSub/ETS isolation
- [ ] Add `Modus.TestHelper` module with `setup_isolated_env/0`
- [ ] Refactor all test files to use shared helper
- [ ] CI-ready test suite: `mix test` = 0 failures
- [ ] Performance baseline: measure memory/CPU per agent

### Hedef: 214 test, 0 failure + perf baseline
### Versiyon: v2.4.0 Veritas ("truth")

---

## IT-02 (16:00) — v2.5.0 Memoria: Deep Agent Memory
**"Hatırlamayan öğrenemez"**

### Görevler
- [ ] `Modus.Mind.EpisodicMemory` — agent'lar yaşadıklarını episodik olarak kaydeder
- [ ] Memory types: event, social, spatial, emotional
- [ ] Memory decay: eski anılar soluk, önemli anılar güçlü (emotional weight)
- [ ] Memory recall: LLM context'e son N anı enjekte (en relevant olanlar)
- [ ] Agent karar verirken geçmiş deneyimlere referans
- [ ] ETS-backed, lightweight, per-agent memory store
- [ ] Bugfix session (15 min)

### Hedef: Agent'lar deneyimlerinden öğrensin
### Versiyon: v2.5.0 Memoria ("memory")

---

## IT-03 (17:00) — v2.6.0 Consilium: Agent Planning & Goals
**"Gelecek düşünmeyen, hayatta kalamaz"**

### Görevler
- [ ] `Modus.Mind.Planner` — multi-step goal planlama
- [ ] Goal decomposition: "ev yap" → [odun topla, taş topla, inşa et]
- [ ] Priority queue: acil ihtiyaçlar (açlık) > uzun vadeli hedefler
- [ ] Plan execution tracking: hangi adımda, ne kadar kaldı
- [ ] Plan revision: engel varsa alternatif plan üret
- [ ] Goals UI panel: agent'ın aktif planı ve ilerlemesi
- [ ] Bugfix session (15 min)

### Hedef: Agent'lar stratejik düşünsün
### Versiyon: v2.6.0 Consilium ("planning/counsel")

---

## IT-04 (18:00) — v2.7.0 Mercatura: Trade & Economy
**"Takas, medeniyetin başlangıcıdır"**

### Görevler
- [ ] `Modus.Simulation.TradeSystem` — agent-to-agent ticaret
- [ ] Barter: fazla olan kaynağı ihtiyacı olan agent'la takas
- [ ] Value assessment: her agent kaynaklara farklı değer biçer (personality-based)
- [ ] Market building: pazar varsa ticaret bonusu
- [ ] Trade history: kim kimle ne takas etti
- [ ] Trade events in event log: "Maya traded 3 wood for 2 fish with Kai"
- [ ] Supply/demand: çok olan ucuzlar, az olan pahalanır
- [ ] Bugfix session (15 min)

### Hedef: Organik ekonomi doğsun
### Versiyon: v2.7.0 Mercatura ("trade")

---

## IT-05 (19:00) — v2.8.0 Ars: Agent Creativity
**"Üretmek, var olmanın en yüksek ifadesi"**

### Görevler
- [ ] `Modus.Mind.Creativity` — agent'lar yaratıcı çıktı üretir
- [ ] Story generation: agent'lar yaşadıklarını hikayeye dönüştürür (LLM)
- [ ] Naming: agent'lar yerlere, gruplara isim verir
- [ ] Invention: yeni crafting recipe keşfi (random combination)
- [ ] Art: agent "painting" yapar (description olarak) → culture'a eklenir
- [ ] Oral tradition: hikayeler agent'tan agent'a aktarılır, değişir
- [ ] Creative output panel in UI
- [ ] Bugfix session (15 min)

### Hedef: Agent'lar kültür üretsin
### Versiyon: v2.8.0 Ars ("art/craft")

---

## IT-06 (20:00) — v2.9.0 Natura: Ecology & Wildlife Depth
**"Doğa bir denge, bozulursa herkes kaybeder"**

### Görevler
- [ ] Wildlife breeding: hayvanlar çoğalır (population cap)
- [ ] Food chain: kurtlar geyik avlar, tavşanlar çoğalırsa kurt çoğalır
- [ ] Seasonal migration: hayvanlar mevsime göre hareket
- [ ] Plant growth cycle: ağaçlar büyür, kesilince tekrar filizlenir
- [ ] Ecosystem balance: aşırı avlanma → kaynak tükenmesi → kıtlık
- [ ] Fishing spots: balık stoku, aşırı avlanma riski
- [ ] Nature events: orman yangını, sel, çekirge sürüsü
- [ ] Bugfix session (15 min)

### Hedef: Gerçekçi ekosistem
### Versiyon: v2.9.0 Natura ("nature")

---

## IT-07 (21:00) — v3.0.0 Societas: Social Structures
**"Tek başına hayatta kalabilirsin, ama yaşayamazsın"**

### Görevler
- [ ] `Modus.Mind.SocialEngine` — grup dinamikleri
- [ ] Clan/tribe formation: yakın agent'lar grup oluşturur
- [ ] Leadership: en yüksek social influence = lider
- [ ] Group decisions: lider grup adına karar verir
- [ ] Alliance/rivalry: gruplar arası ilişkiler
- [ ] Shared resources: grup kaynakları ortak
- [ ] Group names & identity: LLM ile grup ismi/kimliği üretilir
- [ ] Social panel: grup listesi, üyeler, ilişkiler
- [ ] Bugfix session (15 min)

### Hedef: Medeniyetler oluşsun
### Versiyon: v3.0.0 Societas ("society") — MAJOR VERSION

---

## IT-08 (22:00) — v3.1.0 Fabrica: Crafting & Skill Trees
**"Usta olmak zaman ister"**

### Görevler
- [ ] `Modus.Simulation.CraftingSystem` — recipe-based üretim
- [ ] Skill levels: novice → apprentice → expert → master
- [ ] Recipes: sword (iron+wood), bread (wheat+water), medicine (herb+water)
- [ ] Skill XP: tekrar yaptıkça ustalaşır
- [ ] Tool quality: usta agent daha iyi araç yapar
- [ ] Teaching: usta agent çırağına öğretir (skill transfer)
- [ ] Crafting log: ne üretildi, kim üretti
- [ ] Bugfix session (15 min)

### Hedef: Zanaat ve uzmanlık sistemi
### Versiyon: v3.1.0 Fabrica ("workshop/craft")

---

## IT-09 (23:00) — v3.2.0 Ratio: LLM Intelligence Optimization
**"Düşünmek pahalı, akıllıca düşünmek ucuz"**

### Görevler
- [ ] LLM call batching: aynı tick'te birden fazla agent'ı tek prompt'ta gönder
- [ ] Response caching: benzer durumlar için cache (ETS, TTL=100 tick)
- [ ] Prompt compression: context'i minimize et (token tasarrufu)
- [ ] Fallback chain: Antigravity → Gemini → Ollama → hardcoded behavior
- [ ] LLM budget tracking: tick başına max N call, priority queue
- [ ] Decision tree fallback: basit kararlar LLM'siz (behavior tree)
- [ ] Agent "thinking" indicator in UI
- [ ] Metrics: LLM calls/tick, avg latency, cache hit rate
- [ ] Bugfix session (15 min)

### Hedef: 10x daha az LLM call, aynı zeka
### Versiyon: v3.2.0 Ratio ("reason")

---

## IT-10 (00:00) — v3.3.0 Optimum: Performance & Efficiency
**"Kaynağı iyi kullanan, her zaman kazanır"**

### Görevler
- [ ] Memory audit: per-agent memory usage measurement
- [ ] ETS table consolidation: benzer tablolar birleştir
- [ ] Process reduction: gereksiz GenServer'ları kaldır
- [ ] Tick optimization: O(n²) → O(n) agent interactions
- [ ] Lazy evaluation: uzaktaki agent'lar detaylı hesaplanmaz
- [ ] GC tuning: fullsweep_after ayarları
- [ ] Benchmark: 50 agent, 100 agent, 200 agent perf test
- [ ] Memory limit: agent başına max 10KB state
- [ ] Bugfix session (15 min)

### Hedef: 200 agent rahatça çalışsın
### Versiyon: v3.3.0 Optimum ("optimal")

---

## IT-11 (01:00) — v3.4.0 Nexus: Agent Communication Protocol v2
**"İletişim, zekanın göstergesidir"**

### Görevler
- [ ] Structured dialogue: agent'lar konu-bazlı konuşur (trade, alliance, gossip)
- [ ] Persuasion: agent'lar birbirini ikna edebilir (skill-based)
- [ ] Information sharing: "orada kurt var" → spatial knowledge transfer
- [ ] Rumor system: bilgi yayılır ama bozulabilir (telephone game)
- [ ] Secret keeping: bazı bilgiler sadece güvenilen agent'larla paylaşılır
- [ ] Conversation topics driven by current needs/goals
- [ ] Chat panel shows conversation type icons
- [ ] Bugfix session (15 min)

### Hedef: Anlamlı, amaca yönelik diyaloglar
### Versiyon: v3.4.0 Nexus ("connection")

---

## IT-12 (02:00) — v3.5.0 Eventus: Dynamic World Events v2
**"Kader kapıyı çaldığında hazır ol"**

### Görevler
- [ ] Complex event chains: kuraklık → kıtlık → göç → savaş
- [ ] Player-triggered events (God Mode): "send plague", "spawn treasure"
- [ ] Discovery events: agent'lar gizli lokasyonlar keşfeder
- [ ] Festival/celebration: mutlu agent'lar festival düzenler
- [ ] Migration waves: yeni agent'lar gelir (population growth)
- [ ] Natural disasters with recovery period
- [ ] Event probability system: mevsime/duruma göre olasılık
- [ ] Event notification system (toast + log + timeline)
- [ ] Bugfix session (15 min)

### Hedef: Dünya canlı ve sürprizlerle dolu
### Versiyon: v3.5.0 Eventus ("event/fate")

---

## IT-13 (03:00) — v3.6.0 Speculum: Data Visualization Dashboard
**"Görmek, anlamaktır"**

### Görevler
- [ ] Population graph (live, last 100 ticks)
- [ ] Resource distribution chart (wood/stone/food/herbs over time)
- [ ] Relationship network visualization (SVG graph)
- [ ] Agent mood distribution (pie/bar chart)
- [ ] Economy flow: who trades what with whom (sankey-like)
- [ ] Ecosystem balance indicator (predator/prey ratio)
- [ ] All charts pure LiveView/SVG (no JS libraries)
- [ ] Dashboard toggle: D key or menu
- [ ] Bugfix session (15 min)

### Hedef: Zengin veri görselleştirme (JS kütüphanesi olmadan)
### Versiyon: v3.6.0 Speculum ("mirror/observation")

---

## IT-14 (04:00) — v3.7.0 Persistentia: Robust World Persistence
**"Kaybolmayan dünya, değerli dünyadır"**

### Görevler
- [ ] Full world state serialization (agents + buildings + wildlife + economy + history)
- [ ] Auto-save every N ticks (configurable)
- [ ] Save slots: 5 named saves per world
- [ ] World snapshot comparison: load and compare two saves
- [ ] Import/export as JSON (portable)
- [ ] World seed: reproducible worlds from seed number
- [ ] Crash recovery: last auto-save loads on restart
- [ ] Save file size optimization (gzip)
- [ ] Bugfix session (15 min)

### Hedef: Dünyalar asla kaybolmasın
### Versiyon: v3.7.0 Persistentia ("persistence")

---

## IT-15 (05:00) — v3.8.0 Harmonia: Integration & Polish
**"Bütün, parçaların toplamından büyüktür"**

### Görevler
- [ ] Full integration test: tüm sistemler birlikte çalışıyor mu?
- [ ] Edge case fixes: 0 agent, 1 agent, 200 agent
- [ ] Memory leak check: 1000 tick boyunca monitor
- [ ] UI polish: tüm paneller düzgün, responsive
- [ ] Error handling: hiçbir crash kullanıcıya ulaşmasın
- [ ] Documentation: her modülün @moduledoc'u güncel
- [ ] CHANGELOG.md güncellemesi
- [ ] Final `mix test` → 0 failures
- [ ] Docker rebuild + smoke test
- [ ] Git tag v3.8.0 + push
- [ ] Status report generation (HTML dashboard)

### Hedef: Production-ready v3.8.0
### Versiyon: v3.8.0 Harmonia ("harmony")

---

## Sprint v3 Versiyon Haritası
```
v2.4.0 Veritas    → Test Stability
v2.5.0 Memoria    → Deep Memory
v2.6.0 Consilium  → Planning
v2.7.0 Mercatura  → Trade & Economy
v2.8.0 Ars        → Creativity
v2.9.0 Natura     → Ecology
v3.0.0 Societas   → Social Structures (MAJOR)
v3.1.0 Fabrica    → Crafting
v3.2.0 Ratio      → LLM Optimization
v3.3.0 Optimum    → Performance
v3.4.0 Nexus      → Communication v2
v3.5.0 Eventus    → Dynamic Events v2
v3.6.0 Speculum   → Data Visualization
v3.7.0 Persistentia → Persistence
v3.8.0 Harmonia   → Integration & Polish
```

## Cron Pattern
- Her iterasyon 1 saat
- İlk 45 dakika: implementasyon
- Son 15 dakika: bugfix + test + commit
- Her commit sonrası Docker rebuild test
- Her 5 iterasyonda kapsamlı test suite

## Resource Constraints
- Max 16GB RAM (Mac Mini M4)
- Docker containers isolated
- Antigravity gateway for LLM (free tier)
- Gemini fallback (free tier)
- No external dependencies beyond existing
