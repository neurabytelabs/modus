defmodule Modus.Intelligence.GeminiClient do
  @moduledoc """
  GeminiClient — Direct Google Gemini API client.

  Uses Gemini REST API directly (no gateway). Free tier: 15 req/min, 1M tokens/day.
  Primary LLM provider with same interface as OllamaClient.
  """
  require Logger

  @timeout 10_000
  @base_url "https://generativelanguage.googleapis.com/v1beta"
  @circuit_breaker_key :gemini_circuit_breaker
  @max_failures 3
  @cooldown_ms 60_000

  # Rate limiter: simple token bucket via persistent_term
  @rate_limit_key :gemini_rate_limiter
  @max_requests_per_minute 14  # stay under 15 RPM free tier

  # ── Circuit Breaker ─────────────────────────────────────

  defp circuit_open? do
    case :persistent_term.get(@circuit_breaker_key, nil) do
      {failures, last_failure_at} when failures >= @max_failures ->
        elapsed = System.monotonic_time(:millisecond) - last_failure_at
        elapsed < @cooldown_ms

      _ ->
        false
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

  # ── Rate Limiter ────────────────────────────────────────

  defp rate_limit_wait do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@rate_limit_key, nil) do
      {count, window_start} when now - window_start < 60_000 ->
        if count >= @max_requests_per_minute do
          wait = 60_000 - (now - window_start) + 100
          Logger.debug("GeminiClient rate limit: waiting #{wait}ms")
          Process.sleep(wait)
          :persistent_term.put(@rate_limit_key, {1, System.monotonic_time(:millisecond)})
        else
          :persistent_term.put(@rate_limit_key, {count + 1, window_start})
        end

      _ ->
        :persistent_term.put(@rate_limit_key, {1, now})
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  # ── Public API ──────────────────────────────────────────

  def batch_decide(agents, context, config) do
    prompt = build_batch_prompt(agents, context)
    messages = [%{role: "user", content: prompt}]

    case chat_completion(messages, config) do
      {:ok, text} ->
        parse_decisions(text, agents)

      {:error, reason} ->
        Logger.warning("GeminiClient batch_decide failed: #{inspect(reason)}")
        :fallback
    end
  end

  def conversation(agent_a, agent_b, context, config) do
    prompt = build_conversation_prompt(agent_a, agent_b, context)
    messages = [%{role: "user", content: prompt}]

    case chat_completion(messages, config) do
      {:ok, text} ->
        parse_conversation(text, agent_a.name, agent_b.name)

      {:error, reason} ->
        Logger.warning("GeminiClient conversation failed: #{inspect(reason)}")
        :fallback
    end
  end

  def chat_with_agent(agent, user_message, config) do
    {px, py} = agent.position

    memories =
      agent
      |> Map.get(:memory, [])
      |> Enum.take(-3)
      |> Enum.map(fn
        {tick, {action, _params}} -> "- Tick #{tick}: #{action}"
        {tick, action} when is_atom(action) -> "- Tick #{tick}: #{action}"
        other -> "- #{inspect(other)}"
      end)
      |> Enum.join("\n")

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
      {:ok, text} ->
        {:ok, String.trim(text)}

      {:error, reason} ->
        Logger.warning("GeminiClient chat failed: #{inspect(reason)}")
        :fallback
    end
  end

  def chat_completion_direct(messages, _config) do
    case chat(messages) do
      {:ok, text} -> {:ok, String.trim(text)}
      {:error, reason} -> {:error, reason}
    end
  end

  def test_connection(config) do
    messages = [%{role: "user", content: "Say 'ok' in one word."}]

    case do_gemini_request(messages, config) do
      {:ok, _text} ->
        record_success()
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Reset circuit breaker manually."
  def reset_circuit_breaker do
    record_success()
    :ok
  end

  @doc "Simple chat interface (used by FallbackChain directly)."
  def chat(messages) do
    config = %{
      model: "gemini-2.0-flash",
      api_key: System.get_env("GEMINI_API_KEY") || "***REMOVED***"
    }

    do_gemini_request(messages, config)
  end

  # ── HTTP (Gemini REST API) ──────────────────────────────

  defp chat_completion(messages, config) do
    if circuit_open?() do
      Logger.debug("GeminiClient circuit breaker OPEN — skipping")
      {:error, :circuit_open}
    else
      do_gemini_request(messages, config)
    end
  end

  defp do_gemini_request(messages, config) do
    rate_limit_wait()

    model = config[:model] || config.model || "gemini-2.0-flash"
    api_key = config[:api_key] || config.api_key || System.get_env("GEMINI_API_KEY") || ""

    url = "#{@base_url}/models/#{model}:generateContent?key=#{api_key}"

    # Convert OpenAI-format messages to Gemini format
    {system_text, conversation} = extract_system(messages)

    contents =
      Enum.map(conversation, fn msg ->
        role =
          if (msg[:role] || msg["role"]) in ["assistant", "model"], do: "model", else: "user"

        content = msg[:content] || msg["content"]
        %{"role" => role, "parts" => [%{"text" => content}]}
      end)

    body = %{"contents" => contents}

    body =
      if system_text,
        do: Map.put(body, "systemInstruction", %{"parts" => [%{"text" => system_text}]}),
        else: body

    case Req.post(url,
           json: body,
           receive_timeout: @timeout,
           
         ) do
      {:ok, %{status: 200, body: resp}} ->
        text =
          get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])

        if text do
          record_success()
          {:ok, text}
        else
          record_failure()
          {:error, :no_content}
        end

      {:ok, %{status: 429}} ->
        Logger.warning("GeminiClient: rate limited (429)")
        record_failure()
        {:error, :rate_limited}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("GeminiClient failed: #{status}")
        record_failure()
        {:error, {:http, status, inspect(resp_body)}}

      {:error, reason} ->
        record_failure()
        {:error, reason}
    end
  end

  defp extract_system(messages) do
    system = Enum.find(messages, fn m -> (m[:role] || m["role"]) == "system" end)
    rest = Enum.reject(messages, fn m -> (m[:role] || m["role"]) == "system" end)
    {system && (system[:content] || system["content"]), rest}
  end

  # ── Prompt Building ────────────────────────────────────

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

    traits =
      if p.openness > 0.7,
        do: ["curious and open-minded" | traits],
        else:
          if(p.openness < 0.3, do: ["traditional and set in their ways" | traits], else: traits)

    traits =
      if p.extraversion > 0.7,
        do: ["social and energetic" | traits],
        else: if(p.extraversion < 0.3, do: ["introverted and quiet" | traits], else: traits)

    traits =
      if p.agreeableness > 0.7,
        do: ["helpful and kind" | traits],
        else:
          if(p.agreeableness < 0.3, do: ["competitive and independent" | traits], else: traits)

    traits =
      if p.conscientiousness > 0.7,
        do: ["hardworking and organized" | traits],
        else:
          if(p.conscientiousness < 0.3, do: ["easygoing and spontaneous" | traits], else: traits)

    traits =
      if p.neuroticism > 0.7,
        do: ["anxious and emotional" | traits],
        else: if(p.neuroticism < 0.3, do: ["calm and composed" | traits], else: traits)

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
        Logger.warning("GeminiClient: failed to parse decisions JSON")
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

      _ ->
        :fallback
    end
  end

  defp normalize_action(action_str) when is_binary(action_str) do
    if action_str in @valid_actions, do: String.to_atom(action_str), else: :idle
  end

  defp normalize_action(_), do: :idle
end
