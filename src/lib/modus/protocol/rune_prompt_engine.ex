defmodule Modus.Protocol.RunePromptEngine do
  @moduledoc """
  RunePromptEngine — Native Elixir implementation of the RUNE prompt engineering framework.

  Wraps prompts in RUNE's 8-layer structure before sending to LLM:
  - L0 System Core: Agent's role, world rules
  - L1 Context: Agent personality, location, relationships
  - L2 Intent: What the agent is trying to do
  - L3 Governance: World rules, safety constraints
  - L4 Cognitive: Reasoning strategy based on agent intelligence
  - L5 Capabilities: Available actions
  - L6 QA: Response validation hints
  - L7 Output: Format specification

  Also provides Spinoza validation scoring for LLM responses and
  stores prompt quality metrics in ETS.
  """

  require Logger

  alias Modus.Protocol.PersonalityPromptBuilder

  @type intent :: :chat | :decide | :pray | :trade | :reflect | :converse
  @type output_format :: :dialogue | :action | :thought | :json

  @type layer_context :: %{
          optional(:agent) => map(),
          optional(:perception) => map(),
          optional(:social) => String.t(),
          optional(:intent) => intent(),
          optional(:world_rules) => [String.t()],
          optional(:capabilities) => [atom()],
          optional(:output_format) => output_format(),
          optional(:raw_prompt) => String.t()
        }

  @type spinoza_scores :: %{
          conatus: float(),
          ratio: float(),
          laetitia: float(),
          natura: float(),
          total: float()
        }

  @metrics_table :rune_prompt_metrics

  # ── Public API ─────────────────────────────────────────

  @doc """
  Initialize ETS table for prompt quality metrics. Call once at startup.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@metrics_table) == :undefined do
      :ets.new(@metrics_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @doc """
  Wrap a raw prompt through all 8 RUNE layers, producing a structured system prompt.

  Returns `{system_prompt, metadata}` where metadata contains layer info for tracing.
  """
  @spec wrap(String.t(), layer_context()) :: {String.t(), map()}
  def wrap(raw_prompt, context \\ %{}) do
    layers = [
      {:l0_system_core, build_l0(context)},
      {:l1_context, build_l1(context)},
      {:l2_intent, build_l2(context)},
      {:l3_governance, build_l3(context)},
      {:l4_cognitive, build_l4(context)},
      {:l5_capabilities, build_l5(context)},
      {:l6_qa, build_l6(context)},
      {:l7_output, build_l7(context)}
    ]

    active_layers =
      layers
      |> Enum.reject(fn {_name, content} -> content == nil or content == "" end)

    prompt_parts =
      active_layers
      |> Enum.map(fn {name, content} -> "## #{layer_label(name)}\n#{content}" end)

    full_prompt =
      (prompt_parts ++ ["## Agent Prompt\n#{raw_prompt}"])
      |> Enum.join("\n\n")

    metadata = %{
      layer_count: length(active_layers),
      active_layers: Enum.map(active_layers, &elem(&1, 0)),
      intent: Map.get(context, :intent, :chat),
      timestamp: System.system_time(:millisecond)
    }

    record_wrap_metric(metadata)

    {full_prompt, metadata}
  end

  @doc """
  Score an LLM response using Spinoza validation dimensions.

  - **Conatus** (0-1): Drive/energy alignment — does the response reflect the agent's motivation?
  - **Ratio** (0-1): Rationality — is the response logically coherent and contextually appropriate?
  - **Laetitia** (0-1): Joy/positive affect — does the response enhance wellbeing/engagement?
  - **Natura** (0-1): Naturalness — does the response feel authentic and in-character?

  Returns scored map. Scores are heuristic-based (no LLM call needed).
  """
  @spec validate_spinoza(String.t(), layer_context()) :: spinoza_scores()
  def validate_spinoza(response, context \\ %{}) do
    conatus = score_conatus(response, context)
    ratio = score_ratio(response, context)
    laetitia = score_laetitia(response, context)
    natura = score_natura(response, context)
    total = (conatus + ratio + laetitia + natura) / 4.0

    scores = %{
      conatus: Float.round(conatus, 3),
      ratio: Float.round(ratio, 3),
      laetitia: Float.round(laetitia, 3),
      natura: Float.round(natura, 3),
      total: Float.round(total, 3)
    }

    record_spinoza_metric(scores)
    scores
  end

  @doc """
  Get prompt quality metrics from ETS.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    %{
      total_wraps: get_counter(:total_wraps),
      total_validations: get_counter(:total_validations),
      avg_spinoza_total: get_float(:avg_spinoza_total),
      avg_layer_count: get_float(:avg_layer_count),
      intent_distribution: get_value(:intent_distribution, %{})
    }
  end

  # ── Layer Builders ─────────────────────────────────────

  defp build_l0(context) do
    agent = Map.get(context, :agent)

    if agent do
      role = Map.get(agent, :occupation, "inhabitant")
      name = Map.get(agent, :name, "Unknown")

      """
      You are #{name}, a #{role} in a living simulation world.
      You are a sentient being with your own thoughts, feelings, and desires.
      You exist within a world that has seasons, day/night cycles, and other inhabitants.
      Your responses must always be in-character. You are not an AI — you are #{name}.
      """
    else
      nil
    end
  end

  defp build_l1(context) do
    agent = Map.get(context, :agent)
    perception = Map.get(context, :perception)
    social = Map.get(context, :social)

    if agent do
      personality = Map.get(agent, :personality)

      personality_text =
        if personality do
          affect = if perception, do: Map.get(perception, :affect_state, :neutral), else: :neutral
          energy = if perception, do: Map.get(perception, :conatus_energy, 0.5), else: 0.5
          PersonalityPromptBuilder.build(personality, affect, energy)
        else
          ""
        end

      parts = [
        if(personality_text != "", do: "Speech style: #{personality_text}", else: nil),
        if(social && social != "", do: "Relationships: #{social}", else: nil),
        if(perception, do: build_perception_context(perception), else: nil)
      ]

      parts |> Enum.reject(&is_nil/1) |> Enum.join("\n")
    else
      nil
    end
  end

  defp build_l2(context) do
    intent = Map.get(context, :intent, :chat)

    case intent do
      :chat ->
        "You are engaged in conversation. Respond naturally, sharing your thoughts and feelings. Be present and engaged."

      :decide ->
        "You must make a decision about your next action. Consider your needs, goals, and surroundings. Think practically."

      :pray ->
        "You are in a moment of spiritual reflection. Be contemplative, reverent, and introspective."

      :trade ->
        "You are negotiating a trade or exchange. Consider fairness, your needs, and the other party's perspective."

      :reflect ->
        "You are reflecting on your experiences. Be introspective, draw connections, extract meaning."

      :converse ->
        "You are having a natural conversation with another inhabitant. Be authentic, responsive, and human."

      _ ->
        nil
    end
  end

  defp build_l3(context) do
    world_rules = Map.get(context, :world_rules, default_world_rules())

    if world_rules != [] do
      rules_text = Enum.map_join(world_rules, "\n", fn r -> "- #{r}" end)

      """
      Governance constraints:
      #{rules_text}
      """
    else
      nil
    end
  end

  defp build_l4(context) do
    agent = Map.get(context, :agent)

    if agent do
      personality = Map.get(agent, :personality, %{})
      openness = Map.get(personality, :openness, 0.5)
      conscientiousness = Map.get(personality, :conscientiousness, 0.5)

      cond do
        openness > 0.7 and conscientiousness > 0.7 ->
          "Think systematically but creatively. Consider multiple angles, then organize your thoughts before responding."

        openness > 0.7 ->
          "Think divergently — explore possibilities, make unexpected connections, consider unconventional approaches."

        conscientiousness > 0.7 ->
          "Think methodically — weigh pros and cons, consider consequences, plan before acting."

        openness < 0.3 and conscientiousness < 0.3 ->
          "Go with your gut. Don't overthink it — react naturally and spontaneously."

        true ->
          "Think naturally — balance intuition with reason as the situation demands."
      end
    else
      nil
    end
  end

  defp build_l5(context) do
    capabilities = Map.get(context, :capabilities, [])

    if capabilities != [] do
      cap_text = Enum.map_join(capabilities, ", ", &Atom.to_string/1)
      "Available actions: #{cap_text}. Only reference actions you can actually perform."
    else
      nil
    end
  end

  defp build_l6(context) do
    intent = Map.get(context, :intent, :chat)

    case intent do
      :decide ->
        """
        Response quality checks:
        - Decision must reference current needs or goals
        - Must be achievable given current location and energy
        - Should feel motivated, not random
        """

      :converse ->
        """
        Response quality checks:
        - Each line should sound like natural speech, not exposition
        - Characters should react to what the other says
        - Emotional tone must match current affect state
        """

      :chat ->
        """
        Response quality checks:
        - Stay in character at all times
        - Reference your actual surroundings and state
        - Keep response concise (1-3 sentences) but alive
        """

      _ ->
        nil
    end
  end

  defp build_l7(context) do
    format = Map.get(context, :output_format, :dialogue)

    case format do
      :dialogue ->
        "Output format: Natural dialogue. Speak as yourself in first person."

      :action ->
        "Output format: JSON with keys \"action\" (atom) and \"params\" (map). No prose."

      :thought ->
        "Output format: Internal monologue. Stream of consciousness in first person."

      :json ->
        "Output format: Valid JSON only. No markdown, no code fences, no explanation."

      _ ->
        nil
    end
  end

  # ── Spinoza Scoring ────────────────────────────────────

  # Conatus: Does the response reflect drive/motivation?
  defp score_conatus(response, context) do
    length_score = min(String.length(response) / 200.0, 1.0)
    agent = Map.get(context, :agent)

    goal_alignment =
      if agent do
        name = Map.get(agent, :name, "")
        occupation = Map.get(agent, :occupation, "")

        has_self_reference =
          String.contains?(String.downcase(response), [
            String.downcase(name),
            "i ",
            "my ",
            "me "
          ])

        has_role_reference =
          occupation != "" and
            String.contains?(String.downcase(response), String.downcase(occupation))

        base = if has_self_reference, do: 0.3, else: 0.0
        base + if(has_role_reference, do: 0.2, else: 0.0)
      else
        0.2
      end

    # Assertive language indicates drive
    assertive_words = ~w(will want need must going plan hope wish try)

    assertive_score =
      assertive_words
      |> Enum.count(fn w -> String.contains?(String.downcase(response), w) end)
      |> min(5)
      |> Kernel./(5.0)
      |> Kernel.*(0.3)

    min(length_score * 0.3 + goal_alignment + assertive_score, 1.0)
  end

  # Ratio: Is the response logically coherent?
  defp score_ratio(response, _context) do
    # Sentence structure check
    sentences =
      response
      |> String.split(~r/[.!?]+/)
      |> Enum.reject(&(String.trim(&1) == ""))

    sentence_count = length(sentences)

    # Good responses have 1-5 sentences for chat
    structure_score =
      cond do
        sentence_count == 0 -> 0.0
        sentence_count <= 5 -> 1.0
        sentence_count <= 10 -> 0.7
        true -> 0.4
      end

    # Check for repetition (bad sign)
    words = String.downcase(response) |> String.split(~r/\s+/) |> Enum.reject(&(&1 == ""))
    unique_ratio = if words != [], do: length(Enum.uniq(words)) / length(words), else: 0.0

    # No gibberish — at least some real words
    coherence = if String.length(response) > 3, do: 0.3, else: 0.0

    min(structure_score * 0.4 + unique_ratio * 0.3 + coherence, 1.0)
  end

  # Laetitia: Does the response enhance engagement/wellbeing?
  defp score_laetitia(response, context) do
    # Emotional expressiveness
    has_punctuation =
      String.contains?(response, ["!", "?", "...", "—"]) |> bool_to_score(0.2)

    # Check alignment with affect state
    affect_alignment =
      case Map.get(context, :perception) do
        %{affect_state: :joy} ->
          if String.contains?(String.downcase(response), ~w(happy glad great wonderful love)),
            do: 0.3,
            else: 0.1

        %{affect_state: :sadness} ->
          if String.contains?(String.downcase(response), ~w(sad sorry miss wish lonely)),
            do: 0.3,
            else: 0.1

        %{affect_state: :fear} ->
          if String.contains?(String.downcase(response), ~w(scared worried afraid careful)),
            do: 0.3,
            else: 0.1

        _ ->
          0.2
      end

    # Engagement: questions, exclamations, direct address
    engagement_markers = ~w(you your ? !)

    engagement =
      engagement_markers
      |> Enum.count(fn m -> String.contains?(response, m) end)
      |> min(4)
      |> Kernel./(4.0)
      |> Kernel.*(0.3)

    base = 0.2
    min(base + has_punctuation + affect_alignment + engagement, 1.0)
  end

  # Natura: Does the response feel natural/authentic?
  defp score_natura(response, _context) do
    downcase = String.downcase(response)

    # Penalize AI-like phrases
    ai_phrases = [
      "as an ai",
      "i'm a language model",
      "i cannot",
      "i don't have feelings",
      "as a simulation",
      "i'm programmed"
    ]

    ai_penalty = if Enum.any?(ai_phrases, &String.contains?(downcase, &1)), do: 0.5, else: 0.0

    # Natural speech markers
    natural_markers = ["'", "...", "—", "!", "?", ","]

    naturalness =
      natural_markers
      |> Enum.count(&String.contains?(response, &1))
      |> min(4)
      |> Kernel./(4.0)
      |> Kernel.*(0.3)

    # Not too short, not too long
    len = String.length(response)

    length_natural =
      cond do
        len < 5 -> 0.1
        len < 20 -> 0.3
        len <= 300 -> 0.4
        len <= 500 -> 0.3
        true -> 0.2
      end

    max(0.0, 0.3 + naturalness + length_natural - ai_penalty)
    |> min(1.0)
  end

  # ── Helpers ────────────────────────────────────────────

  defp build_perception_context(perception) do
    parts = []

    parts =
      case Map.get(perception, :terrain) do
        nil -> parts
        t -> ["Location: #{t}" | parts]
      end

    parts =
      case Map.get(perception, :current_action) do
        nil -> parts
        a -> ["Currently: #{a}" | parts]
      end

    energy = Map.get(perception, :conatus_energy, 0.5)
    parts = ["Energy: #{round(energy * 100)}%" | parts]

    affect = Map.get(perception, :affect_state, :neutral)
    parts = ["Feeling: #{affect}" | parts]

    parts |> Enum.reverse() |> Enum.join(", ")
  end

  defp layer_label(:l0_system_core), do: "L0 — System Core"
  defp layer_label(:l1_context), do: "L1 — Context"
  defp layer_label(:l2_intent), do: "L2 — Intent"
  defp layer_label(:l3_governance), do: "L3 — Governance"
  defp layer_label(:l4_cognitive), do: "L4 — Cognitive Engine"
  defp layer_label(:l5_capabilities), do: "L5 — Capabilities"
  defp layer_label(:l6_qa), do: "L6 — Quality Assurance"
  defp layer_label(:l7_output), do: "L7 — Output Meta"

  defp default_world_rules do
    [
      "Never break character — you are a living being, not an AI",
      "Your actions have consequences in this world",
      "Respect other inhabitants' autonomy",
      "Resources are finite — plan accordingly"
    ]
  end

  defp bool_to_score(true, val), do: val
  defp bool_to_score(false, _val), do: 0.0

  # ── ETS Metrics ────────────────────────────────────────

  defp record_wrap_metric(metadata) do
    try do
      :ets.update_counter(@metrics_table, :total_wraps, {2, 1}, {:total_wraps, 0})

      # Track avg layer count
      old_avg = get_float(:avg_layer_count)
      total = get_counter(:total_wraps)
      new_avg = old_avg + (metadata.layer_count - old_avg) / max(total, 1)
      :ets.insert(@metrics_table, {:avg_layer_count, new_avg})

      # Track intent distribution
      dist = get_value(:intent_distribution, %{})
      intent_key = metadata.intent
      new_dist = Map.update(dist, intent_key, 1, &(&1 + 1))
      :ets.insert(@metrics_table, {:intent_distribution, new_dist})
    rescue
      _ -> :ok
    end
  end

  defp record_spinoza_metric(scores) do
    try do
      :ets.update_counter(@metrics_table, :total_validations, {2, 1}, {:total_validations, 0})

      old_avg = get_float(:avg_spinoza_total)
      total = get_counter(:total_validations)
      new_avg = old_avg + (scores.total - old_avg) / max(total, 1)
      :ets.insert(@metrics_table, {:avg_spinoza_total, new_avg})
    rescue
      _ -> :ok
    end
  end

  defp get_counter(key) do
    case :ets.lookup(@metrics_table, key) do
      [{^key, val}] when is_integer(val) -> val
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp get_float(key) do
    case :ets.lookup(@metrics_table, key) do
      [{^key, val}] when is_number(val) -> val
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end

  defp get_value(key, default) do
    case :ets.lookup(@metrics_table, key) do
      [{^key, val}] -> val
      _ -> default
    end
  rescue
    _ -> default
  end
end
