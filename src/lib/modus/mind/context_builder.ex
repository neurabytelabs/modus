defmodule Modus.Mind.ContextBuilder do
  @moduledoc "Builds dynamic LLM system prompts enriched with real agent state"

  alias Modus.Mind.{Perception, Cerebro.SocialInsight}
  alias Modus.Persistence.AgentMemory
  alias Modus.Simulation.Seasons

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @doc "Build a full system prompt for chat with real context."
  def build_chat_prompt(agent, _user_message \\ nil) do
    perception = Perception.snapshot(agent)
    social = SocialInsight.describe_relationships(agent.id)
    energy_pct = round(ensure_float(perception.conatus_energy) * 100)

    """
    You are #{agent.name}, a #{agent.occupation} in a living world.

    Your personality: #{describe_personality_rich(agent.personality)}

    Right now you're #{action_name(perception.current_action)} in the #{terrain_name(perception.terrain)}.
    Your energy is #{energy_pct}% and you're feeling #{affect_name(perception.affect_state)}.
    #{hunger_context(perception.needs)}

    #{nearby_context(perception.nearby_agents)}
    #{social}

    #{season_context()}

    #{memory_context(agent.id)}

    #{goals_context(agent.id)}

    RULES:
    - Speak naturally as #{agent.name} would — use your personality
    - If you have goals, mention them naturally when relevant
    - Reference your REAL surroundings, feelings, and relationships
    - If hungry, mention it naturally. If tired, sound it. If happy, show it
    - Keep responses 1-3 sentences but make them ALIVE
    - Never say "I'm currently [action]" robotically — weave it into natural speech
    - If someone asks about your world, describe what you actually see
    - Remember past conversations and reference them
    """
  end

  @doc "Build prompt for agent-to-agent conversation."
  def build_conversation_prompt(agent_a, agent_b, _context) do
    rel = SocialInsight.describe_relationship(agent_a.id, agent_b.id, agent_b.name)
    terrain = try do
      Perception.get_terrain_at(agent_a.position)
    catch
      _, _ -> :grass
    end

    rel_tone = relationship_tone(rel)
    emotional_dynamic = emotional_dynamic(agent_a.affect_state, agent_b.affect_state, agent_a.name, agent_b.name)

    """
    Two people meet in a #{terrain_name(terrain)}. Write a short, natural 3-turn conversation.

    #{agent_a.name}: #{agent_a.occupation}. #{describe_personality_rich(agent_a.personality)}
    Energy: #{round(ensure_float(agent_a.conatus_energy) * 100)}%, feeling #{affect_name(agent_a.affect_state)}.

    #{agent_b.name}: #{agent_b.occupation}. #{describe_personality_rich(agent_b.personality)}
    Energy: #{round(ensure_float(agent_b.conatus_energy) * 100)}%, feeling #{affect_name(agent_b.affect_state)}.

    Relationship: #{rel}
    #{rel_tone}
    #{emotional_dynamic}

    Respond with JSON: {"dialogue": [{"speaker": "<name>", "line": "<text>"}, ...]}
    Keep each line under 50 words. Make it feel like real people talking — awkward pauses, warmth, tension, whatever fits.
    """
  end

  # Public helpers (used by Bridge)
  def terrain_name(:forest), do: "forest"
  def terrain_name(:water), do: "waterside"
  def terrain_name(:mountain), do: "mountain"
  def terrain_name(:desert), do: "desert"
  def terrain_name(_), do: "grassland"

  def affect_name(:joy), do: "happy 😊"
  def affect_name(:sadness), do: "sad 😢"
  def affect_name(:fear), do: "scared 😨"
  def affect_name(:desire), do: "eager 🔥"
  def affect_name(_), do: "calm 😐"

  def action_name(:exploring), do: "exploring"
  def action_name(:gathering), do: "gathering food"
  def action_name(:sleeping), do: "sleeping"
  def action_name(:talking), do: "talking to someone"
  def action_name(:fleeing), do: "fleeing"
  def action_name(_), do: "idling"

  @doc false
  def describe_personality_rich(p) do
    high_o = p.openness > 0.65
    low_o = p.openness < 0.35
    high_e = p.extraversion > 0.65
    low_e = p.extraversion < 0.35
    high_a = p.agreeableness > 0.65
    low_a = p.agreeableness < 0.35
    high_c = p.conscientiousness > 0.65
    low_c = p.conscientiousness < 0.35
    high_n = p.neuroticism > 0.65
    low_n = p.neuroticism < 0.35

    # Build description from dominant trait combinations
    parts =
      []
      |> maybe_add(high_o and high_e, "You're a free spirit who loves meeting new people and exploring wild ideas.")
      |> maybe_add(high_o and low_e, "You're a deep thinker — imaginative and creative, but you need your alone time to recharge.")
      |> maybe_add(low_e and high_n, "You're a quiet worrier who prefers solitude but cares deeply about the people close to you.")
      |> maybe_add(high_a and high_c, "You're a reliable helper who takes pride in your work and always shows up for others.")
      |> maybe_add(high_e and low_n, "You're the life of the party — confident, upbeat, and hard to rattle.")
      |> maybe_add(low_a and low_c, "You're a bit of a rebel — you do things your own way and don't care much for rules.")
      |> maybe_add(high_n and high_a, "You feel things intensely and you worry about everyone — sometimes too much for your own good.")
      |> maybe_add(high_c and low_o, "You're practical and disciplined — you stick to what works and don't chase fads.")
      |> maybe_add(high_o and high_a, "You're warm-hearted and endlessly curious — always asking questions and genuinely caring about the answers.")
      |> maybe_add(low_e and low_n, "You're quiet and steady — unbothered by drama, content in your own company.")
      |> maybe_add(high_e and high_n, "You crave connection but your emotions run hot — highs are high, lows are low.")
      |> maybe_add(high_c and high_n, "You're a perfectionist who stresses about getting everything just right.")

    case parts do
      [] -> personality_fallback(p)
      _ -> Enum.join(parts, " ")
    end
  end

  defp maybe_add(list, true, text), do: [text | list]
  defp maybe_add(list, false, _text), do: list

  defp personality_fallback(p) do
    traits = []
    traits = if p.openness > 0.5, do: ["curious" | traits], else: ["practical" | traits]
    traits = if p.extraversion > 0.5, do: ["outgoing" | traits], else: ["reserved" | traits]
    traits = if p.agreeableness > 0.5, do: ["kind" | traits], else: ["blunt" | traits]
    traits = if p.neuroticism > 0.5, do: ["sensitive" | traits], else: ["easygoing" | traits]
    "You're #{Enum.join(traits, ", ")} — a complex person like everyone else."
  end

  defp hunger_context(needs) do
    hunger = ensure_float(needs.hunger)
    rest = ensure_float(needs.rest)
    social = ensure_float(needs.social)

    parts = []
    parts = if hunger > 70, do: ["You're starving — food is all you can think about." | parts], else: if(hunger > 40, do: ["Your stomach is starting to growl." | parts], else: parts)
    parts = if rest > 70, do: ["You're exhausted and could collapse any moment." | parts], else: if(rest > 40, do: ["You're getting tired." | parts], else: parts)
    parts = if social > 70, do: ["You're desperately lonely and craving company." | parts], else: if(social > 40, do: ["You could use some company." | parts], else: parts)

    Enum.join(parts, " ")
  end

  defp nearby_context([]), do: "You're alone — nobody in sight."
  defp nearby_context(agents) do
    descriptions =
      agents
      |> Enum.take(3)
      |> Enum.map(fn a ->
        rel_label = case a.relationship_type do
          :friend -> "your friend"
          :close_friend -> "your close friend"
          :rival -> "someone you don't get along with"
          :stranger -> "a stranger"
          _ -> "an acquaintance"
        end
        "#{a.name} (#{rel_label}, looking #{affect_name(a.affect)}) is #{a.distance} steps away."
      end)

    "Nearby: " <> Enum.join(descriptions, " ")
  end

  defp memory_context(agent_id) do
    convos = Modus.Mind.ConversationMemory.format_for_context(agent_id)
    memories = AgentMemory.format_for_context(agent_id)

    parts = []
    parts = if convos != "" and convos != nil, do: ["Recent conversations:\n#{convos}" | parts], else: parts
    parts = if memories != "" and memories != nil, do: ["Things you remember:\n#{memories}" | parts], else: parts

    Enum.join(parts, "\n\n")
  end

  defp relationship_tone(rel) do
    cond do
      String.contains?(rel, "friend") or String.contains?(rel, "close") ->
        "They're friends — be warm, joke around, share openly."
      String.contains?(rel, "rival") or String.contains?(rel, "negative") ->
        "There's tension between them — be guarded, maybe sarcastic."
      true ->
        "They don't know each other well — be curious but cautious, feel each other out."
    end
  end

  defp season_context do
    try do
      state = Seasons.get_state()
      config = state.config
      season_name = config.name
      tod = try do
        Modus.Simulation.Environment.time_of_day()
      catch
        _, _ -> :day
      end
      time_str = if tod == :night, do: "night", else: "daytime"

      "It's #{season_name} (#{time_str}). " <>
        case state.season do
          :spring -> "The world is blooming — fresh green everywhere, new growth."
          :summer -> "It's hot and bright — the sun beats down, energy drains faster."
          :autumn -> "Leaves are falling, the air is crisp. Harvest time."
          :winter -> "It's cold and barren — resources are scarce, survival is harder."
          _ -> ""
        end
    catch
      _, _ -> ""
    end
  end

  defp goals_context(agent_id) do
    goals = Modus.Mind.Goals.active_goals(agent_id)
    if goals == [] do
      ""
    else
      lines = Enum.map(goals, fn g ->
        pct = round(Modus.Mind.Goals.ensure_float_pub(g.progress) * 100)
        "- #{Modus.Mind.Goals.describe(g)} (#{pct}% done)"
      end)
      "Your current goals:\n#{Enum.join(lines, "\n")}"
    end
  end

  defp emotional_dynamic(affect_a, affect_b, name_a, name_b) do
    cond do
      affect_a == :sadness and affect_b == :joy ->
        "#{name_b} is happy and might try to cheer #{name_a} up."
      affect_b == :sadness and affect_a == :joy ->
        "#{name_a} is happy and might try to cheer #{name_b} up."
      affect_a == :fear ->
        "#{name_a} is scared — they might seek comfort or act jumpy."
      affect_a == :sadness and affect_b == :sadness ->
        "They're both sad — they might bond over shared struggle."
      affect_a == :joy and affect_b == :joy ->
        "They're both in good spirits — the energy is light and playful."
      true -> ""
    end
  end

end
