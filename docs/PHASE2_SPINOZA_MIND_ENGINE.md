# MODUS Phase 2 — Spinoza Mind Engine

> "Deep minds in 2D dots > hollow scripts in 3D models"

## Vizyon
Her agent'a bir **iç dünya** vermek: enerji (conatus), duygu (affect), hafıza (memory) ve akıl yürütme (reasoning). Spinoza'nın Ethics'inden doğrudan esinlenilmiş bir zihin motoru.

## Sprint 1 (Bu Tur) — Conatus Engine + Affect States

### Deliverables
1. **Conatus Engine** — `Modus.Mind.Conatus` modülü
   - `conatus_energy` float (0.0-1.0) — yaşama iradesi
   - Başarılı aksiyonlar enerjiyi artırır (+0.05-0.15)
   - Başarısız aksiyonlar azaltır (-0.03-0.10)
   - Sosyal etkileşimler affect alignment'a göre amplify
   - conatus = 0 → ölüm (mevcut age-based death'in yanına)

2. **Affect State Machine** — `Modus.Mind.Affect`
   - 5 temel duygu: `:joy`, `:sadness`, `:desire`, `:fear`, `:neutral`
   - Event-driven geçişler (yemek bulma → joy, açlık → fear, sosyal ret → sadness)
   - Her affect'in conatus'a etkisi: joy +regen, sadness -drain, desire +motivation, fear -freeze

3. **Visual Feedback** — Renderer güncellemesi
   - Agent renk haritası: gold=joy, blue=sadness, green=desire, red=fear, grey=neutral
   - Conatus bar (agent altında ince bar, enerji seviyesi)
   - Affect geçişlerinde particle efekti

4. **Agent Detail Panel** — Güncellenmiş UI
   - Conatus enerji göstergesi (yüzde + bar)
   - Mevcut affect state + geçiş geçmişi
   - Son 5 affect geçişi timeline

### Test Senaryoları
- [ ] Agent yemek bulunca conatus artar, affect → joy
- [ ] Uzun süre aç kalan agent: conatus düşer, affect → fear
- [ ] İki agent konuşunca: her ikisinin de conatus'u artar (affect alignment)
- [ ] Conatus 0'a düşen agent ölür
- [ ] Renderer'da agent rengi affect'e göre değişir
- [ ] Detail panel'de conatus + affect doğru gösterilir

### Mimari
```
Agent GenServer state'e eklenenler:
  %{
    ...existing fields...
    conatus_energy: 0.7,        # float 0.0-1.0
    affect_state: :neutral,      # atom
    affect_history: [],           # [{tick, old_affect, new_affect, reason}]
    conatus_history: [],          # [{tick, delta, reason}]
  }

Modüller:
  Modus.Mind.Conatus    — enerji hesaplama, decay, boost
  Modus.Mind.Affect     — state machine, geçiş kuralları
  Modus.Mind.MindEngine — orchestrator, tick'te çalışır
```

### Dosya Planı
- `src/lib/modus/mind/conatus.ex` — Conatus hesaplama modülü
- `src/lib/modus/mind/affect.ex` — Affect state machine
- `src/lib/modus/mind/mind_engine.ex` — Orchestrator (her tick çalışır)
- `src/lib/modus/simulation/agent.ex` — State'e yeni alanlar
- `src/lib/modus_web/channels/world_channel.ex` — Affect/conatus data push
- `src/assets/js/renderer.js` — Renk haritası + conatus bar
- `src/lib/modus_web/live/universe_live.ex` — Detail panel güncellemesi
- `src/test/modus/mind/conatus_test.exs`
- `src/test/modus/mind/affect_test.exs`

---

## Sprint 2 — Affect Memory (RAG-lite)
- Agent'ların duygusal anıları: "Tick 500'de yemek buldum → joy hissettim"
- ETS-based in-memory store (no external DB)
- LLM context'e son 5 affect memory eklenir
- Agents geçmiş deneyimlere göre karar verir

## Sprint 3 — LLM Reasoning Cycle
- Persistent sadness (>50 tick) → LLM reasoning trigger
- Agent "düşünür": "Neden üzgünüm? Ne yapabilirim?"
- Reasoning sonucu aksiyonu değiştirir
- "Cerebro" Mind View — affect graph + reasoning display

## Magic Moment (Demo Hedefi)
İki üzgün agent bir araya gelir → konuşur → affect'leri sadness→joy'a geçer →
renkleri blue→gold olur → conatus yükselir → LLM der: "İşbirliği güç kapasitemizi artırdı"
