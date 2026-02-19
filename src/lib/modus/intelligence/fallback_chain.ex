defmodule Modus.Intelligence.FallbackChain do
  @moduledoc """
  FallbackChain — Cascading LLM provider fallback.

  Order: Antigravity → Gemini Direct → Ollama → Hardcoded Behavior Tree.
  Each provider is tried in order; on failure, falls through to next.
  """
  require Logger

  alias Modus.Intelligence.{
    AntigravityClient,
    GeminiClient,
    OllamaClient,
    BehaviorTree,
    LlmMetrics
  }

  @doc "Execute a batch decision with fallback chain."
  def batch_decide(agents, context) do
    tick = Map.get(context, :tick, 0)
    config = get_config()

    start = System.monotonic_time(:millisecond)

    result =
      try_antigravity(agents, context, config)
      |> or_try(fn -> try_gemini_batch(agents, tick) end)
      |> or_try(fn -> try_ollama(agents, context, config) end)
      |> or_fallback(fn -> behavior_tree_fallback(agents, tick) end)

    elapsed = System.monotonic_time(:millisecond) - start

    model =
      case result do
        {:ok, _, model} -> model
        _ -> "behavior_tree"
      end

    LlmMetrics.record_call(elapsed, model)

    case result do
      {:ok, decisions, _model} -> decisions
      :fallback -> :fallback
    end
  end

  @doc "Execute a chat with fallback chain."
  def chat(agent, message) do
    config = get_config()
    start = System.monotonic_time(:millisecond)

    result =
      case config.provider do
        :antigravity ->
          case AntigravityClient.chat_with_agent(agent, message, config) do
            {:ok, text} -> {:ok, text}
            _ -> try_gemini_chat(agent, message)
          end

        :ollama ->
          case OllamaClient.chat_with_agent(agent, message, config) do
            {:ok, text} -> {:ok, text}
            _ -> {:ok, "I'm thinking... (LLM unavailable)"}
          end

        _ ->
          {:ok, "I'm thinking... (no provider)"}
      end

    elapsed = System.monotonic_time(:millisecond) - start
    LlmMetrics.record_call(elapsed)
    result
  end

  # ── Private ────────────────────────────────────────────

  defp try_antigravity(agents, context, %{provider: :antigravity} = config) do
    case AntigravityClient.batch_decide(agents, context, config) do
      :fallback -> :fallback
      decisions when is_list(decisions) -> {:ok, decisions, config.model}
      _ -> :fallback
    end
  rescue
    e ->
      Logger.warning("FallbackChain: Antigravity failed: #{inspect(e)}")
      :fallback
  end

  defp try_antigravity(_agents, _context, _config), do: :fallback

  defp try_gemini_batch(agents, tick) do
    prompt = Modus.Intelligence.PromptCompressor.compress_batch(agents, tick)
    messages = [%{role: "user", content: prompt}]

    case GeminiClient.chat(messages) do
      {:ok, text} ->
        case parse_decisions(text, agents) do
          :fallback -> :fallback
          decisions -> {:ok, decisions, "gemini-flash"}
        end

      _ ->
        :fallback
    end
  rescue
    _ -> :fallback
  end

  defp try_ollama(agents, context, config) do
    case OllamaClient.batch_decide(agents, context, config) do
      :fallback -> :fallback
      decisions when is_list(decisions) -> {:ok, decisions, config.model}
      _ -> :fallback
    end
  rescue
    _ -> :fallback
  end

  defp behavior_tree_fallback(agents, tick) do
    decisions =
      Enum.map(agents, fn agent ->
        action =
          try do
            BehaviorTree.evaluate(agent, tick)
          rescue
            _ -> fallback_action(agent)
          end

        {agent.id, action, %{reason: "behavior_tree", target: nil}}
      end)

    {:ok, decisions, "behavior_tree"}
  end

  defp fallback_action(%{needs: %{hunger: h}}) when h > 70, do: :find_food
  defp fallback_action(%{needs: %{rest: r}}) when r < 25, do: :go_home_sleep
  defp fallback_action(%{needs: %{social: s}}) when s < 20, do: :find_friend
  defp fallback_action(_), do: :explore

  defp try_gemini_chat(_agent, _message) do
    # Simple fallback — just return a generic response
    {:ok, "I'm thinking... (connection issues)"}
  end

  defp or_try(:fallback, next_fn), do: next_fn.()
  defp or_try(result, _next_fn), do: result

  defp or_fallback(:fallback, fallback_fn), do: fallback_fn.()
  defp or_fallback(result, _fallback_fn), do: result

  defp get_config do
    try do
      Modus.Intelligence.LlmProvider.get_config()
    rescue
      _ ->
        %{
          provider: :ollama,
          model: "llama3.2:3b-instruct-q4_K_M",
          base_url: "http://modus-llm:11434",
          api_key: nil
        }
    end
  end

  @valid_actions ~w(idle explore gather find_food go_home_sleep find_friend help_nearby flee talk)

  defp parse_decisions(text, agents) do
    agent_ids = MapSet.new(Enum.map(agents, & &1.id))

    case Jason.decode(text) do
      {:ok, %{"decisions" => decisions}} when is_list(decisions) ->
        decisions
        |> Enum.filter(fn d -> MapSet.member?(agent_ids, d["id"]) end)
        |> Enum.map(fn d ->
          action = if d["action"] in @valid_actions, do: String.to_atom(d["action"]), else: :idle
          {d["id"], action, %{reason: d["reason"] || "llm"}}
        end)

      _ ->
        :fallback
    end
  end
end
