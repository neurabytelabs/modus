defmodule Modus.Protocol.PersonalityPromptBuilder do
  @moduledoc """
  Builds LLM system prompt modifiers based on agent's Big Five personality traits
  and current Affect state (Spinoza). Shapes how agents speak — their tone, vocabulary,
  sentence structure, and emotional expression.

  ## Big Five Dimensions
  - **Openness** — metaphors, creative language, curiosity
  - **Conscientiousness** — structured speech, precision, duty
  - **Extraversion** — verbosity, enthusiasm, social energy
  - **Agreeableness** — warmth, politeness, conflict avoidance
  - **Neuroticism** — anxiety, doubt, emotional volatility

  ## Affect States (Spinoza)
  - `:joy` (laetitia) — enthusiastic, exclamation marks, verbose
  - `:sadness` (tristitia) — hesitant, short sentences, worried
  - `:desire` (cupiditas) — persuasive, goal-oriented, urgent
  - `:fear` — cautious, fragmented, defensive
  - `:neutral` — balanced baseline
  """

  @type personality :: %{
          openness: float(),
          conscientiousness: float(),
          extraversion: float(),
          agreeableness: float(),
          neuroticism: float()
        }

  @type affect :: :joy | :sadness | :desire | :fear | :neutral


  @type context_map :: %{
          optional(:memories) => [String.t()],
          optional(:relationships) => [%{name: String.t(), type: atom(), sentiment: float()}],
          optional(:goals) => [%{description: String.t(), progress: float()}]
        }

  @doc """
  Build a complete speech style directive from personality + affect state + conatus energy.

  Returns a string to inject into LLM system prompts that shapes how the agent communicates.
  """
  @spec build(personality(), affect(), float()) :: String.t()
  def build(personality, affect_state, conatus_energy \\ 0.5) do
    [
      build_trait_directives(personality),
      build_affect_directive(affect_state, conatus_energy),
      build_combined_directive(personality, affect_state)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Build only the Big Five personality speech directives.
  """
  @spec build_trait_directives(personality()) :: [String.t()]
  def build_trait_directives(personality) do
    [
      openness_directive(personality.openness),
      conscientiousness_directive(personality.conscientiousness),
      extraversion_directive(personality.extraversion),
      agreeableness_directive(personality.agreeableness),
      neuroticism_directive(personality.neuroticism)
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Build the affect-state speech directive.
  """
  @spec build_affect_directive(affect(), float()) :: String.t() | nil
  def build_affect_directive(affect_state, conatus_energy \\ 0.5) do
    base = affect_directive(affect_state)
    energy_mod = energy_modifier(conatus_energy)

    case {base, energy_mod} do
      {nil, nil} -> nil
      {b, nil} -> b
      {nil, e} -> e
      {b, e} -> "#{b} #{e}"
    end
  end

  @doc """
  Build directives from interesting Big Five + Affect combinations.
  """
  @spec build_combined_directive(personality(), affect()) :: String.t() | nil
  def build_combined_directive(personality, affect_state) do
    cond do
      # High neuroticism + fear = panic mode
      personality.neuroticism > 0.7 and affect_state == :fear ->
        "You're spiraling — catastrophize, stammer, repeat yourself."

      # High extraversion + joy = infectious enthusiasm
      personality.extraversion > 0.7 and affect_state == :joy ->
        "You're BUZZING with energy — talk fast, laugh, pull people into your excitement!"

      # Low extraversion + sadness = withdrawn
      personality.extraversion < 0.3 and affect_state == :sadness ->
        "You've gone quiet — one-word answers, long pauses, avoiding eye contact."

      # High openness + desire = visionary
      personality.openness > 0.7 and affect_state == :desire ->
        "You're on fire with ideas — paint vivid pictures of what could be, inspire others."

      # High agreeableness + fear = people-pleasing under stress
      personality.agreeableness > 0.7 and affect_state == :fear ->
        "You're anxiously trying to keep everyone happy — over-apologize, defer, agree too quickly."

      # High conscientiousness + sadness = stoic suffering
      personality.conscientiousness > 0.7 and affect_state == :sadness ->
        "You push through the pain with duty — mention your responsibilities, suppress emotion."

      # Low agreeableness + desire = ruthlessly persuasive
      personality.agreeableness < 0.3 and affect_state == :desire ->
        "You want what you want and you don't sugarcoat it — be blunt, transactional, direct."

      true ->
        nil
    end
  end


  @doc """
  Build a fully conscious prompt that includes personality speech style,
  affect state, conatus energy, plus episodic memories, relationships, and goals.

  The context_map may contain:
    - `:memories` — list of episodic memory strings
    - `:relationships` — list of maps with :name, :type, :sentiment
    - `:goals` — list of maps with :description, :progress

  Returns a multi-section string suitable for LLM system prompt injection.
  """
  @spec build_conscious(personality(), affect(), float(), context_map()) :: String.t()
  def build_conscious(personality, affect_state, conatus_energy, context_map) do
    speech = build(personality, affect_state, conatus_energy)
    memories = build_memories_section(Map.get(context_map, :memories, []))
    relationships = build_relationships_section(Map.get(context_map, :relationships, []))
    goals = build_goals_section(Map.get(context_map, :goals, []))

    [speech, memories, relationships, goals]
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n\n")
  end

  defp build_memories_section([]), do: ""

  defp build_memories_section(memories) do
    lines = memories |> Enum.take(10) |> Enum.map(&("- #{&1}"))
    "MEMORIES:\n" <> Enum.join(lines, "\n")
  end

  defp build_relationships_section([]), do: ""

  defp build_relationships_section(relationships) do
    lines =
      relationships
      |> Enum.take(10)
      |> Enum.map(fn rel ->
        name = Map.get(rel, :name, "unknown")
        type = Map.get(rel, :type, :acquaintance)
        sentiment = Map.get(rel, :sentiment, 0.0)
        tone = relationship_sentiment_tone(sentiment)
        "- #{name} (#{type}) — #{tone}"
      end)

    "RELATIONSHIPS:\n" <> Enum.join(lines, "\n")
  end

  defp build_goals_section([]), do: ""

  defp build_goals_section(goals) do
    lines =
      goals
      |> Enum.take(5)
      |> Enum.map(fn goal ->
        desc = Map.get(goal, :description, "unnamed goal")
        progress = Map.get(goal, :progress, 0.0)
        pct = round(progress * 100)
        "- #{desc} (#{pct}% complete)"
      end)

    "GOALS:\n" <> Enum.join(lines, "\n")
  end

  defp relationship_sentiment_tone(sentiment) when sentiment > 0.6, do: "you feel warmly toward them"
  defp relationship_sentiment_tone(sentiment) when sentiment > 0.2, do: "you feel positively about them"
  defp relationship_sentiment_tone(sentiment) when sentiment < -0.6, do: "you feel hostile toward them"
  defp relationship_sentiment_tone(sentiment) when sentiment < -0.2, do: "you feel uneasy around them"
  defp relationship_sentiment_tone(_), do: "you feel neutral about them"

  # ── Openness ──────────────────────────────────────────

  defp openness_directive(val) when val > 0.7 do
    "Use metaphors and creative language. Draw unexpected comparisons. Wonder aloud."
  end

  defp openness_directive(val) when val > 0.5 do
    "Occasionally use colorful expressions and show curiosity about new things."
  end

  defp openness_directive(val) when val < 0.3 do
    "Stick to plain, concrete language. No flowery speech — say what you mean directly."
  end

  defp openness_directive(_), do: nil

  # ── Conscientiousness ─────────────────────────────────

  defp conscientiousness_directive(val) when val > 0.7 do
    "Speak precisely and structured. Reference plans, schedules, and responsibilities."
  end

  defp conscientiousness_directive(val) when val < 0.3 do
    "Be casual and loose with words. Don't bother with details or plans."
  end

  defp conscientiousness_directive(_), do: nil

  # ── Extraversion ──────────────────────────────────────

  defp extraversion_directive(val) when val > 0.7 do
    "Be talkative and energetic. Use exclamations, ask questions, keep the conversation flowing."
  end

  defp extraversion_directive(val) when val < 0.3 do
    "Keep it brief. Speak only when you have something meaningful to say. Prefer listening."
  end

  defp extraversion_directive(_), do: nil

  # ── Agreeableness ─────────────────────────────────────

  defp agreeableness_directive(val) when val > 0.7 do
    "Be warm and supportive. Validate others' feelings. Avoid conflict — find common ground."
  end

  defp agreeableness_directive(val) when val < 0.3 do
    "Don't sugarcoat anything. Challenge ideas you disagree with. Be skeptical."
  end

  defp agreeableness_directive(_), do: nil

  # ── Neuroticism ───────────────────────────────────────

  defp neuroticism_directive(val) when val > 0.7 do
    "Express anxiety and self-doubt. Second-guess yourself. Worry about what could go wrong."
  end

  defp neuroticism_directive(val) when val > 0.5 do
    "Show occasional nervousness — hedge your statements, express mild concern."
  end

  defp neuroticism_directive(val) when val < 0.3 do
    "Stay calm and unflappable. Nothing fazes you — speak with quiet confidence."
  end

  defp neuroticism_directive(_), do: nil

  # ── Affect State ──────────────────────────────────────

  defp affect_directive(:joy) do
    "You're feeling joyful! Be enthusiastic, use exclamation marks, smile through your words. Be more verbose and generous."
  end

  defp affect_directive(:sadness) do
    "You're feeling sad. Speak hesitantly... use shorter sentences. Express worry. Trail off sometimes..."
  end

  defp affect_directive(:desire) do
    "You're driven by strong desire. Be persuasive and goal-oriented. Everything connects to what you want. Create urgency."
  end

  defp affect_directive(:fear) do
    "You're afraid. Speak cautiously — short, fragmented sentences. Look over your shoulder. Seek reassurance."
  end

  defp affect_directive(:neutral), do: nil
  defp affect_directive(_), do: nil

  # ── Conatus Energy ────────────────────────────────────

  defp energy_modifier(energy) when energy < 0.2 do
    "You're exhausted — barely holding on. Words come slowly, sentences trail off."
  end

  defp energy_modifier(energy) when energy > 0.8 do
    "You're bursting with vitality — speak with vigor and confidence."
  end

  defp energy_modifier(_), do: nil
end
