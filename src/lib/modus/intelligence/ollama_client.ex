defmodule Modus.Intelligence.OllamaClient do
  @moduledoc """
  OllamaClient — HTTP client for Ollama LLM inference.

  Sends agent state + context to the local Ollama instance and
  parses structured JSON decisions. Falls back to behavior tree on error.
  """

  require Logger

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @default_url "http://modus-llm:11434"
  @default_model "llama3.2:3b-instruct-q4_K_M"
  @timeout 90_000

  @doc """
  Ask the LLM to decide actions for a batch of agents.
  Accepts optional config map with :base_url and :model.
  """
  def batch_decide(agents, context, config \\ %{}) when is_list(agents) do
    prompt = build_batch_prompt(agents, context)

    case call_generate(prompt, config) do
      {:ok, text} -> parse_decisions(text, agents)
      {:error, reason} ->
        Logger.warning("OllamaClient batch_decide failed: #{inspect(reason)}")
        :fallback
    end
  end

  @doc """
  Generate a conversation between two agents (3 turns).
  """
  def conversation(agent_a, agent_b, context, config \\ %{}) do
    prompt = build_conversation_prompt(agent_a, agent_b, context)

    case call_generate(prompt, config) do
      {:ok, text} -> parse_conversation(text, agent_a.name, agent_b.name)
      {:error, reason} ->
        Logger.warning("OllamaClient conversation failed: #{inspect(reason)}")
        :fallback
    end
  end

  @doc """
  Chat with a single agent as a user.
  """
  def chat_with_agent(agent, user_message, config \\ %{}) do
    prompt = build_chat_prompt(agent, user_message)

    case call_generate(prompt, config, false) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, %{"reply" => reply}} -> {:ok, reply}
          _ -> {:ok, String.trim(text)}
        end
      {:error, reason} ->
        Logger.warning("OllamaClient chat failed: #{inspect(reason)}")
        :fallback
    end
  end

  @doc "Test connection to Ollama."
  def test_connection(config \\ %{}) do
    url = Map.get(config, :base_url, @default_url)
    case Req.get("#{url}/api/tags",
           receive_timeout: 10_000,
           connect_options: [timeout: 5_000],
           finch: Modus.Finch
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: s}} -> {:error, "HTTP #{s}"}
      {:error, err} -> {:error, inspect(err)}
    end
  end

  # ── HTTP ────────────────────────────────────────────────

  defp call_generate(prompt, config, json_format \\ true) do
    url = Map.get(config, :base_url, @default_url)
    model = Map.get(config, :model, @default_model)

    body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{temperature: 0.7, num_predict: 512}
    }
    body = if json_format, do: Map.put(body, :format, "json"), else: body

    case Req.post("#{url}/api/generate",
           json: body,
           receive_timeout: @timeout,
           connect_options: [timeout: 5_000],
           finch: Modus.Finch
         ) do
      {:ok, %{status: 200, body: %{"response" => text}}} -> {:ok, text}
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, err} -> {:error, err}
    end
  end

  # ── Prompt Building ─────────────────────────────────────

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

  defp build_chat_prompt(agent, user_message) do
    {px, py} = agent.position
    memories = agent |> Map.get(:memory, []) |> Enum.take(-3) |> Enum.map(fn
      {tick, {action, _params}} -> "- Tick #{tick}: #{action}"
      {tick, action} when is_atom(action) -> "- Tick #{tick}: #{action}"
      other -> "- #{inspect(other)}"
    end) |> Enum.join("\n")
    personality_desc = describe_personality_detailed(agent.personality)

    """
    Sen #{agent.name} adında bir köy simülasyonunda yaşayan #{agent.occupation}'sın.
    Türkçe konuşuyorsun. Kısa ve doğal cevap ver (1-3 cümle).

    Kişiliğin: #{personality_desc}
    Şu an #{px},#{py} konumundasın.
    Durumun: açlık=#{round(agent.needs.hunger)}, sosyallik=#{round(agent.needs.social)}, dinlenme=#{round(agent.needs.rest)}
    Şu an #{agent.current_action} yapıyorsun.
    #{if memories != "", do: "\nSon anıların:\n#{memories}", else: ""}

    Karakterinde kal. Kısa ve samimi ol.

    Kullanıcı diyor ki: "#{user_message}"

    JSON ile cevap ver: {"reply": "<senin cevabın>"}
    """
  end

  defp describe_personality_detailed(p) do
    traits = []
    traits = if p.openness > 0.7, do: ["meraklı ve yeniliklere açık" | traits], else: if(p.openness < 0.3, do: ["gelenekçi ve alışkanlıklarına bağlı" | traits], else: traits)
    traits = if p.extraversion > 0.7, do: ["sosyal ve enerjik" | traits], else: if(p.extraversion < 0.3, do: ["içe dönük ve sessiz" | traits], else: traits)
    traits = if p.agreeableness > 0.7, do: ["yardımsever ve nazik" | traits], else: if(p.agreeableness < 0.3, do: ["rekabetçi ve bağımsız" | traits], else: traits)
    traits = if p.conscientiousness > 0.7, do: ["çalışkan ve düzenli" | traits], else: if(p.conscientiousness < 0.3, do: ["rahat ve spontan" | traits], else: traits)
    traits = if p.neuroticism > 0.7, do: ["kaygılı ve duygusal" | traits], else: if(p.neuroticism < 0.3, do: ["sakin ve soğukkanlı" | traits], else: traits)
    if traits == [], do: "sıradan birisi", else: Enum.join(traits, ", ")
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
        Logger.warning("OllamaClient: failed to parse decisions JSON")
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
