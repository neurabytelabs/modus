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
