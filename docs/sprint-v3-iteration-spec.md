# Sprint v3 Iteration Spec Template

## Common Rules for ALL Iterations
1. Work in `/Users/morty/Developer/neurabytelabs/modus/src/`
2. Docker exec: `docker compose exec modus-app <command>`
3. Edit files on host, Docker auto-syncs via volume mount
4. After changes: `docker compose exec modus-app mix compile --no-color`
5. Run tests: `docker compose exec modus-app mix test --no-color`
6. Git commit with version tag after each iteration
7. Update `mix.exs` version field
8. ALWAYS use ETS or :persistent_term for state (not GenServer.call for reads)
9. ALWAYS use `ensure_float()` guards for any arithmetic
10. ALWAYS handle nil/missing data gracefully
11. Keep modules small: max 200 lines per file
12. No external deps — use what's already in mix.exs
13. Test isolation: use `Modus.TestHelper.setup_isolated_env()` (create if missing)
14. Elixir best practices: pattern matching, pipe operator, with statements
15. @moduledoc for every new module
16. ALL reports, commit messages, and announcements MUST be in TURKISH (Türkçe)
17. After each iteration, take a SCREENSHOT of localhost:4000 and send to Telegram:
    - Use browser tool: navigate to http://localhost:4000, wait 3 seconds, take screenshot
    - Save screenshot to /Users/morty/Developer/neurabytelabs/modus/demo/screenshots/vX.Y.Z.png
    - Send to Telegram group -5191394304 with Turkish caption describing what's new
    - IMPORTANT: Do NOT screenshot the onboarding/landing page! Navigate past it:
      1. browser navigate to http://localhost:4000
      2. browser snapshot → find "CREATE WORLD" or "Skip" button → click it
      3. Wait 5 seconds for simulation to load
      4. THEN take the screenshot of the RUNNING SIMULATION
    - If browser tool unavailable, use: `curl -s http://localhost:4000 > /dev/null && echo 'App running'` and note in report
18. Iteration completion report format (TURKISH):
    ```
    ✅ vX.Y.Z [Codename] — Tamamlandı!
    
    🆕 Yeni özellikler:
    - [feature 1]
    - [feature 2]
    
    🧪 Test: X passed, Y failed
    📊 Modül: N | Satır: N
    🖼️ Ekran görüntüsü: [attached]
    ```

## Docker Volume Mount
The `src/` directory is mounted into the container. Edit files at:
`/Users/morty/Developer/neurabytelabs/modus/src/lib/modus/`

## Existing Modules Reference
- simulation/: agent, building, resource, wildlife, seasons, world_events, rules_engine, economy, ticker, world
- mind/: affect, conatus, culture, goals, learning, reasoning_engine, perception, context_builder
- intelligence/: llm_provider, antigravity_client, gemini_client, ollama_client, llm_scheduler
- persistence/: world_persistence, world_export, agent_memory
- protocol/: bridge modules for user↔agent communication

## Key Patterns
```elixir
# ETS table creation
:ets.new(:table_name, [:set, :public, :named_table])

# Safe float
defp ensure_float(val) when is_float(val), do: val
defp ensure_float(val) when is_integer(val), do: val * 1.0
defp ensure_float(_), do: 0.0

# LLM call pattern
case Modus.Intelligence.LlmProvider.chat(prompt, model) do
  {:ok, response} -> process(response)
  {:error, _} -> fallback_behavior()
end
```
