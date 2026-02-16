defmodule Modus.Intelligence.OllamaClient do
  @moduledoc """
  OllamaClient — HTTP client for Ollama LLM inference.

  Sends agent state + context to the local Ollama instance and
  parses structured JSON decisions. Falls back to behavior tree on error.
  """

  require Logger

  @base_url "http://modus-llm:11434"
  @model "llama3.2:3b-instruct-q4_K_M"
  @timeout 30_000

  @doc """
  Ask the LLM to decide actions for a batch of agents.

  Returns a list of `{agent_id, action_atom, params_map}` tuples.
  On any error, returns `:fallback` so the caller can use behavior tree.
  """
  @spec batch_decide([map()], map()) :: [{String.t(), atom(), map()}] | :fallback
  def batch_decide(agents, context) when is_list(agents) do
    prompt = build_batch_prompt(agents, context)

    case call_generate(prompt) do
      {:ok, text} -> parse_decisions(text, agents)
      {:error, reason} ->
        Logger.warning("OllamaClient batch_decide failed: #{inspect(reason)}")
        :fallback
    end
  end

  @doc """
  Generate a conversation between two agents (3 turns).
  Returns a list of `{speaker_name, dialogue_line}` tuples.
  """
  @spec conversation(map(), map(), map()) :: [{String.t(), String.t()}] | :fallback
  def conversation(agent_a, agent_b, context) do
    prompt = build_conversation_prompt(agent_a, agent_b, context)

    case call_generate(prompt) do
      {:ok, text} -> parse_conversation(text, agent_a.name, agent_b.name)
      {:error, reason} ->
        Logger.warning("OllamaClient conversation failed: #{inspect(reason)}")
        :fallback
    end
  end

  @doc """
  Chat with a single agent as a user. Returns the agent's reply string.
  """
  @spec chat_with_agent(map(), String.t()) :: {:ok, String.t()} | :fallback
  def chat_with_agent(agent, user_message) do
    prompt = build_chat_prompt(agent, user_message)

    case call_generate(prompt, false) do
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

  # ── HTTP ────────────────────────────────────────────────────

  defp call_generate(prompt, json_format \\ true)

  defp call_generate(prompt, json_format) do
    body = %{
      model: @model,
      prompt: prompt,
      stream: false,
      options: %{temperature: 0.7, num_predict: 512}
    }
    body = if json_format, do: Map.put(body, :format, "json"), else: body

    case Req.post("#{@base_url}/api/generate",
           json: body,
           receive_timeout: @timeout,
           connect_options: [timeout: 5_000]
         ) do
      {:ok, %{status: 200, body: %{"response" => text}}} -> {:ok, text}
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, err} -> {:error, err}
    end
  end

  # ── Prompt Building ─────────────────────────────────────────

  defp build_batch_prompt(agents, context) do
    agent_descriptions =
      agents
      |> Enum.map(fn a ->
        """
        - id: "#{a.id}", name: "#{a.name}", pos: #{inspect(a.position)}, \
        occupation: #{a.occupation}, hunger: #{Float.round(a.needs.hunger, 1)}, \
        social: #{Float.round(a.needs.social, 1)}, rest: #{Float.round(a.needs.rest, 1)}, \
        action: #{a.current_action}, personality: O=#{Float.round(a.personality.openness, 2)} \
        C=#{Float.round(a.personality.conscientiousness, 2)} \
        E=#{Float.round(a.personality.extraversion, 2)} \
        A=#{Float.round(a.personality.agreeableness, 2)} \
        N=#{Float.round(a.personality.neuroticism, 2)}
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
    """
    You are #{agent.name}, a #{agent.occupation} in a village simulation.
    Your personality: #{describe_agent(agent)}
    Your current state: hunger=#{round(agent.needs.hunger)}, social=#{round(agent.needs.social)}, rest=#{round(agent.needs.rest)}
    You are currently #{agent.current_action}.

    Stay in character. Be brief (1-3 sentences). Respond naturally as this character would.

    The user says: "#{user_message}"

    Respond with JSON: {"reply": "<your response>"}
    """
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

  # ── Response Parsing ────────────────────────────────────────

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

      _ ->
        :fallback
    end
  end

  defp normalize_action(action_str) when is_binary(action_str) do
    if action_str in @valid_actions do
      String.to_atom(action_str)
    else
      :idle
    end
  end

  defp normalize_action(_), do: :idle
end
