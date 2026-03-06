# Night Sprint Directives (Sprint 3-10)

## Priority Features (from Rick)

### 1. Full English — Remove all Turkish
- Scan ALL .ex, .exs, .heex files for Turkish text
- Replace with English equivalents
- UI labels, comments, demo content — everything EN

### 2. Conscious Chat (HIGH PRIORITY)
Agent chat responses must come from their FULL inner state:
- Affect (joy/sadness/fear/desire/wonder) → shapes tone
- Conatus level → energy/verbosity
- Episodic memories → "remember when..." references
- Relationships → friend vs stranger tone
- Big Five personality → speaking style
- Current goals/needs → organic mentions
- Location/environment → spatial awareness
- NO generic LLM responses — every reply UNIQUE to that agent

Implementation:
- Enhance PersonalityPromptBuilder to inject ALL state
- Build ConsciousChatPrompt module — assembles full context
- System prompt template with live state variables
- Test: same question to 2 different agents = 2 different answers

### 3. Dream System (MEDIUM PRIORITY)
Night cycle feature:
- Agents "dream" — process day events through affect-weighted memory
- Surreal narratives mixing real memories + imagination
- Dreams affect next-day personality/goals
- Dream journal in agent detail panel
- Social dreams: agents dream ABOUT each other
- Nightmares when conatus low / sadness high
- Morning: agents share dreams in chat

Implementation:
- DreamEngine module (GenServer, triggered by night cycle)
- DreamPromptBuilder (memory + affect → dream narrative)
- Dream schema (ETS or Ecto)
- UI: dream journal tab in agent panel
- Integration: Ticker night phase → trigger dreams

### 4. UI/UX Excellence
- Every sprint must include at least 1 UI improvement
- Target: "the best interface this project deserves"
- Inspiration: Linear, Vercel, Supabase dashboards
- Focus: interactions quality, animations, responsiveness

### 5. Security Check
- Every commit: grep for API keys/secrets before push
- No hardcoded keys EVER

## Deploy Plan
- Written: docs/deploy-plan-nb.md
- Review: 2026-03-06 10:00 Berlin with Rick
