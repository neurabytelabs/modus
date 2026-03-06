# MODUS Sprint Marathon — 6 March 2026

## Config
- Duration: 30min/sprint, 11:00-18:00 CET
- Base: v9.1.0 (960 tests, 114 modules, d2a03dc)
- Chain: Each sprint schedules next via `openclaw cron add --at +32m`
- Tweet: After each major feature completion
- Rule: All tests must pass before commit. No hardcoded keys.

## Sprint Plan (RUNE validated)

### Phase 1: Conscious Chat (Sprint 4-8, HIGH PRIORITY)
- S4 (11:00): ConsciousChatPrompt module — assembles affect+memory+conatus+personality into system prompt
- S5 (11:30): Enhance PersonalityPromptBuilder — inject ALL inner state variables
- S6 (12:00): Integration — wire ConsciousChat into chat flow, unique responses per agent
- S7 (12:30): Testing + edge cases — same question to 2 agents = 2 different answers
- S8 (13:00): Polish + integration tests → TWEET: Conscious Chat live

### Phase 2: Full English (Sprint 9-10)
- S9 (13:30): Scan all .ex/.exs/.heex for Turkish → replace with English
- S10 (14:00): Verify + test → TWEET: Full English

### Phase 3: Dream System (Sprint 11-14)
- S11 (14:30): DreamEngine GenServer + DreamPromptBuilder
- S12 (15:00): Dream schema (ETS) + night cycle trigger
- S13 (15:30): Dream journal UI in agent panel + social dreams
- S14 (16:00): Integration tests + polish → TWEET: Dream System

### Phase 4: Buffer (Sprint 15-17)
- S15 (16:30): UI/UX polish + any overflow
- S16 (17:00): Final test sweep + version bump
- S17 (17:30): Deploy prep for modus.neurabytelabs.com
