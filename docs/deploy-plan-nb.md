# MODUS Demo Deploy — modus.neurabytelabs.com

> Review: 2026-03-06 10:00 Berlin

## Target
Public demo at modus.neurabytelabs.com — accessible to everyone, demo mode default

## Infrastructure

### Hetzner (Coolify)
- Server: 91.98.46.190 / 100.75.40.116 (Tailscale)
- Platform: Coolify v4 @ panel.mustafasarac.com
- neurabytelabs.com already running here

### Docker Deployment
1. Create `docker-compose.prod.yml` (no dev deps)
2. Coolify new service: modus-app (Elixir) + modus-llm (optional Ollama)
3. Port: 4001 (internal) → modus.neurabytelabs.com (Coolify reverse proxy)
4. SSL: Coolify auto (Let's Encrypt)

### LLM Strategy
- Primary: Gemini API (free tier, GEMINI_API_KEY env var)
- Fallback: Ollama on Hetzner (CPU-only, slower but works)
- Demo mode: Rate limit per session

### DNS
- `modus.neurabytelabs.com` → Hetzner IP (A record)
- Cloudflare proxy optional

## Demo Mode Limits
- Save/Load: 1 slot only
- Max agents: 20
- Max simulation: 30 min (auto-pause)
- Chat: 10 msg/min rate limit
- CTA: "Full version: self-host with Docker"

## neurabytelabs.com Integration
- Products page: MODUS card → "Try Demo" button
- Hero section: "Live Demo" badge
- Blog post: "MODUS is live"

## Action Items
- [ ] docker-compose.prod.yml
- [ ] Coolify service setup
- [ ] DNS A record
- [ ] GEMINI_API_KEY env var
- [ ] Demo mode default config
- [ ] Rate limiting
- [ ] neurabytelabs.com CTA
- [ ] Landing/onboarding optimize
- [ ] Smoke test
