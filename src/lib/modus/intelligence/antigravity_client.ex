defmodule Modus.Intelligence.AntigravityClient do
  @moduledoc """
  AntigravityClient — OpenAI-compatible client for Antigravity Gateway.

  Sends chat completions to the gateway and parses structured responses.
  """
  require Logger

  @timeout 90_000
  @circuit_breaker_key :antigravity_circuit_breaker
  @max_failures 3
  @cooldown_ms 60_000

  # ── Circuit Breaker (persistent_term) ───────────────────

  defp circuit_open? do
    case :persistent_term.get(@circuit_breaker_key, nil) do
      {failures, last_failure_at} when failures >= @max_failures ->
        elapsed = System.monotonic_time(:millisecond) - last_failure_at
        elapsed < @cooldown_ms
      _ -> false
    end
  end

  defp record_failure do
    now = System.monotonic_time(:millisecond)
    case :persistent_term.get(@circuit_breaker_key, nil) do
      {failures, first_at} when now - first_at < @cooldown_ms ->
        :persistent_term.put(@circuit_breaker_key, {failures + 1, first_at})
      _ ->
        :persistent_term.put(@circuit_breaker_key, {1, now})
    end
  end

  defp record_success do
    :persistent_term.put(@circuit_breaker_key, {0, 0})
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  # ── Public API (called from LlmProvider) ────────────────

  def batch_decide(agents, context, config) do
    prompt = build_batch_prompt(agents, context)
    messages = [%{role: "user", content: prompt}]

    case chat_completion(messages, config, json_mode: true) do
      {:ok, text} -> parse_decisions(text, agents)
      {:error, reason} ->
        Logger.warning("AntigravityClient batch_decide failed: #{inspect(reason)}")
        :fallback
    end
  end

  def conversation(agent_a, agent_b, context, config) do
    prompt = build_conversation_prompt(agent_a, agent_b, context)
    messages = [%{role: "user", content: prompt}]

    case chat_completion(messages, config, json_mode: true) do
      {:ok, text} -> parse_conversation(text, agent_a.name, agent_b.name)
      {:error, reason} ->
        Logger.warning("AntigravityClient conversation failed: #{inspect(reason)}")
        :fallback
    end
  end

  def chat_with_agent(agent, user_message, config) do
    {px, py} = agent.position
    memories = agent |> Map.get(:memory, []) |> Enum.take(-3) |> Enum.map(fn
      {tick, {action, _params}} -> "- Tick #{tick}: #{action}"
      {tick, action} when is_atom(action) -> "- Tick #{tick}: #{action}"
      other -> "- #{inspect(other)}"
    end) |> Enum.join("\n")
    personality_desc = describe_personality_detailed(agent.personality)

    system = """
    You are #{agent.name}, a #{agent.occupation} living in a village simulation.
    You speak English. Give short, natural responses (1-3 sentences).

    Personality: #{personality_desc}
    You are currently at position #{px},#{py}.
    Status: hunger=#{round(agent.needs.hunger)}, social=#{round(agent.needs.social)}, rest=#{round(agent.needs.rest)}
    You are currently #{agent.current_action}.
    #{if memories != "", do: "\nRecent memories:\n#{memories}", else: ""}

    Stay in character. Be brief and friendly.
    """
    messages = [
      %{role: "system", content: system},
      %{role: "user", content: user_message}
    ]

    case chat_completion(messages, config) do
      {:ok, text} -> {:ok, String.trim(text)}
      {:error, reason} ->
        Logger.warning("AntigravityClient chat failed: #{inspect(reason)}")
        :fallback
    end
  end

  def chat_completion_direct(messages, config) do
    case chat_completion(messages, config) do
      {:ok, text} -> {:ok, String.trim(text)}
      {:error, reason} -> {:error, reason}
    end
  end

  def test_connection(config) do
    # Bypass circuit breaker for manual test — and reset it on success
    messages = [%{role: "user", content: "Say 'ok' in one word."}]
    case do_chat_completion(messages, config, []) do
      {:ok, _text} ->
        record_success()  # Reset circuit breaker on successful test
        :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Reset circuit breaker manually."
  def reset_circuit_breaker do
    record_success()
    :ok
  end

  # ── HTTP ────────────────────────────────────────────────

  defp chat_completion(messages, config, opts \\ []) do
    if circuit_open?() do
      Logger.debug("AntigravityClient circuit breaker OPEN — returning fallback")
      {:error, :circuit_open}
    else
      do_chat_completion(messages, config, opts)
    end
  end

  defp do_chat_completion(messages, config, opts) do
    url = "#{config.base_url}/v1/chat/completions"

    body = %{
      model: config.model,
      messages: messages,
      temperature: 0.7
    }

    body = if Keyword.get(opts, :json_mode, false) do
      Map.put(body, :response_format, %{type: "json_object"})
    else
      body
    end

    headers = if config.api_key do
      [{"authorization", "Bearer #{config.api_key}"}]
    else
      []
    end

    case Req.post(url,
           json: body,
           headers: headers,
           receive_timeout: @timeout,
           finch: Modus.Finch
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        record_success()
        {:ok, content}
      {:ok, %{status: status, body: body}} ->
        record_failure()
        {:error, {:http, status, body}}
      {:error, err} ->
        record_failure()
        {:error, err}
    end
  end

  # ── Prompt Building (shared with OllamaClient) ─────────

  defp build_batch_prompt(agents, context) do
    agent_descriptions =
      agents
      |> Enum.map(fn a ->
        """
        - id: "#{a.id}", name: "#{a.name}", pos: #{inspect(a.position)}, \
        occupation: #{a.occupation}, hunger: #{Float.round(ensure_float(a.needs.hunger), 1)}, \
        social: #{Float.round(ensure_float(a.needs.social), 1)}, rest: #{Float.round(ensure_float(a.needs.rest), 1)}, \
        action: #{a.current_action}, personality: O=#{Float.round(ensure_float(a.personality.openness), 2)} \
        C=#{Float.round(ensure_float(a.personality.conscientiousness), 2)} \
        E=#{Float.round(ensure_float(a.personality.extraversion), 2)} \
        A=#{Float.round(ensure_float(a.personality.agreeableness), 2)} \
        N=#{Float.round(ensure_float(a.personality.neuroticism), 2)}
        """
      end)
      |> Enum.join()

    tick = Map.get(context, :tick, 0)

    """
    You are the decision engine for a life simulation. Given these agents, choose actions.

    TICK: #{tick}
    AGENTS:
    #{agent_descriptions}

    Valid actions: idle, explore, gather, find_food, go_home_sleep, find_friend, help_nearby, flee, talk
    Respond with JSON: {"decisions": [{"id": "<agent_id>", "action": "<action>", "reason": "<short reason>"}]}
    Be creative but consistent with personality and needs. Hungry agents should find_food, tired should sleep, lonely should socialize.
    """
  end

  defp build_conversation_prompt(agent_a, agent_b, _context) do
    """
    Two characters meet in a village simulation. Write a short 3-turn conversation.

    #{agent_a.name}: #{describe_agent(agent_a)}
    #{agent_b.name}: #{describe_agent(agent_b)}

    Respond with JSON: {"dialogue": [{"speaker": "<name>", "line": "<text>"}, ...]}
    Keep each line under 50 words. Be natural and reflect their personalities.
    """
  end

  defp describe_personality_detailed(p) do
    traits = []
    traits = if p.openness > 0.7, do: ["curious and open-minded" | traits], else: if(p.openness < 0.3, do: ["traditional and set in their ways" | traits], else: traits)
    traits = if p.extraversion > 0.7, do: ["social and energetic" | traits], else: if(p.extraversion < 0.3, do: ["introverted and quiet" | traits], else: traits)
    traits = if p.agreeableness > 0.7, do: ["helpful and kind" | traits], else: if(p.agreeableness < 0.3, do: ["competitive and independent" | traits], else: traits)
    traits = if p.conscientiousness > 0.7, do: ["hardworking and organized" | traits], else: if(p.conscientiousness < 0.3, do: ["easygoing and spontaneous" | traits], else: traits)
    traits = if p.neuroticism > 0.7, do: ["anxious and emotional" | traits], else: if(p.neuroticism < 0.3, do: ["calm and composed" | traits], else: traits)
    if traits == [], do: "an ordinary person", else: Enum.join(traits, ", ")
  end

  defp describe_agent(a) do
    traits = []
    traits = if a.personality.openness > 0.7, do: ["curious" | traits], else: traits
    traits = if a.personality.extraversion > 0.7, do: ["outgoing" | traits], else: traits
    traits = if a.personality.agreeableness > 0.7, do: ["kind" | traits], else: traits
    traits = if a.personality.neuroticism > 0.7, do: ["anxious" | traits], else: traits
    traits = if a.personality.conscientiousness > 0.7, do: ["diligent" | traits], else: traits
    traits = if traits == [], do: ["ordinary"], else: traits

    "#{a.occupation}, #{Enum.join(traits, "/")}. Hunger: #{round(a.needs.hunger)}, Social: #{round(a.needs.social)}"
  end

  # ── Response Parsing ────────────────────────────────────

  @valid_actions ~w(idle explore gather find_food go_home_sleep find_friend help_nearby flee talk)

  defp parse_decisions(text, agents) do
    agent_ids = MapSet.new(Enum.map(agents, & &1.id))

    case Jason.decode(text) do
      {:ok, %{"decisions" => decisions}} when is_list(decisions) ->
        decisions
        |> Enum.filter(fn d -> MapSet.member?(agent_ids, d["id"]) end)
        |> Enum.map(fn d ->
          action = normalize_action(d["action"])
          {d["id"], action, %{reason: d["reason"] || "llm"}}
        end)
      _ ->
        Logger.warning("AntigravityClient: failed to parse decisions JSON")
        :fallback
    end
  end

  defp parse_conversation(text, name_a, name_b) do
    case Jason.decode(text) do
      {:ok, %{"dialogue" => lines}} when is_list(lines) ->
        lines
        |> Enum.take(6)
        |> Enum.filter(fn d -> d["speaker"] in [name_a, name_b] end)
        |> Enum.map(fn d -> {d["speaker"], d["line"] || ""} end)
      _ -> :fallback
    end
  end

  defp normalize_action(action_str) when is_binary(action_str) do
    if action_str in @valid_actions, do: String.to_atom(action_str), else: :idle
  end
  defp normalize_action(_), do: :idle
end
