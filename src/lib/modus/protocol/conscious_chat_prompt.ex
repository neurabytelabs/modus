defmodule Modus.Protocol.ConsciousChatPrompt do
  @moduledoc """
  Assembles ALL agent inner state into a structured LLM system prompt.

  Pulls personality, affect, conatus, episodic memories, conversation memories,
  goals, relationships, position, needs, culture, trust, world history, and seasons
  into a rich prompt where every line reflects real agent state.

  Supports two modes:
  - User-to-agent chat (default)
  - Agent-to-agent chat (when target_agent_id is provided)
  """

  alias Modus.Mind.{
    Perception,
    EpisodicMemory,
    ConversationMemory,
    AffectMemory,
    Goals,
    Cerebro.SocialInsight,
    Cerebro.SocialNetwork,
    Culture,
    Trust
  }

  alias Modus.Protocol.PersonalityPromptBuilder
  alias Modus.Simulation.{Seasons, WorldHistory, Agent}
  alias Modus.Mind.ContextBuilder
  alias Modus.I18n

  @doc """
  Build a conscious chat prompt from full agent state.

  ## Parameters
    - agent: The agent struct
    - user_message: The incoming message text
    - opts: Optional keyword list
      - :target_agent_id — if chatting with another agent (agent-to-agent mode)

  ## Returns
    A system prompt string enriched with all inner state.
  """
  @spec build(map(), String.t(), keyword()) :: String.t()
  def build(agent, user_message, opts \\ []) do
    target_agent_id = Keyword.get(opts, :target_agent_id)

    if target_agent_id do
      build_agent_chat(agent, target_agent_id, user_message)
    else
      build_user_chat(agent, user_message)
    end
  end

  # ── User-to-Agent Chat ─────────────────────────────────

  defp build_user_chat(agent, _user_message) do
    perception = Perception.snapshot(agent)
    energy_pct = round(ensure_float(perception.conatus_energy) * 100)
    lang = I18n.current_language()
    lang_instruction = I18n.language_instruction(lang)
    identity = I18n.identity_prompt(lang, agent.name, agent.occupation)

    sections = [
      lang_instruction,
      identity,
      identity_section(agent),
      personality_section(agent, perception),
      state_section(agent, perception, energy_pct),
      needs_section(perception.needs),
      nearby_section(perception.nearby_agents),
      social_section(agent.id),
      season_section(),
      episodic_memory_section(agent.id),
      conversation_memory_section(agent.id, nil),
      affect_memory_section(agent.id),
      goals_section(agent.id),
      desires_section(agent.id, perception),
      culture_section(agent.id),
      world_history_section(),
      trust_section(agent.id),
      rules_section(agent.name)
    ]

    sections
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n\n")
  end

  # ── Agent-to-Agent Chat ────────────────────────────────

  defp build_agent_chat(agent, target_agent_id, _user_message) do
    perception = Perception.snapshot(agent)
    energy_pct = round(ensure_float(perception.conatus_energy) * 100)
    lang = I18n.current_language()
    lang_instruction = I18n.language_instruction(lang)
    identity = I18n.identity_prompt(lang, agent.name, agent.occupation)

    # Get target agent info
    target = Agent.get_state(target_agent_id)
    target_name = if target, do: target.name, else: "someone"

    # Relationship context
    relationship_desc = SocialInsight.describe_relationship(agent.id, target_agent_id, target_name)
    relationship_data = SocialNetwork.get_relationship(agent.id, target_agent_id)
    rel_tone = relationship_tone(relationship_desc)

    # Shared memories
    shared = SocialInsight.shared_context(agent.id, target_agent_id)

    shared_section =
      if shared != [] do
        "Shared experiences with #{target_name}:\n" <>
          (shared |> Enum.map(&("- #{&1}")) |> Enum.join("\n"))
      else
        ""
      end

    # Conversation history with this specific agent
    interlocutor_convos = conversation_memory_section(agent.id, target_name)

    sections = [
      lang_instruction,
      identity,
      identity_section(agent),
      personality_section(agent, perception),
      state_section(agent, perception, energy_pct),
      needs_section(perception.needs),
      "You're talking to #{target_name}.",
      "Relationship: #{relationship_desc}",
      rel_tone,
      shared_section,
      interlocutor_convos,
      episodic_memory_section(agent.id),
      affect_memory_section(agent.id),
      goals_section(agent.id),
      desires_section(agent.id, perception),
      emotional_dynamic_section(agent, target),
      culture_section(agent.id),
      trust_section(agent.id),
      agent_chat_rules(agent.name, target_name, relationship_data)
    ]

    sections
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n\n")
  end

  # ── Prompt Sections ────────────────────────────────────

  defp identity_section(agent) do
    "You are #{agent.name}, a #{agent.occupation} in a living world."
  end

  defp personality_section(agent, perception) do
    personality_desc = ContextBuilder.describe_personality_rich(agent.personality)
    speech_style = PersonalityPromptBuilder.build(agent.personality, perception.affect_state, perception.conatus_energy)

    """
    Your personality: #{personality_desc}

    SPEECH STYLE: #{speech_style}
    """
    |> String.trim()
  end

  defp state_section(agent, perception, energy_pct) do
    action = ContextBuilder.action_name(perception.current_action)
    terrain = ContextBuilder.terrain_name(perception.terrain)
    affect = ContextBuilder.affect_name(perception.affect_state)

    "Right now you're #{action} in the #{terrain}.\nYour energy is #{energy_pct}% and you're feeling #{affect}."
  end

  defp needs_section(needs) do
    hunger = ensure_float(needs.hunger)
    rest = ensure_float(needs.rest)
    social = ensure_float(needs.social)

    parts = []

    parts =
      if hunger > 70,
        do: ["You're starving — food is all you can think about." | parts],
        else: if(hunger > 40, do: ["Your stomach is starting to growl." | parts], else: parts)

    parts =
      if rest > 70,
        do: ["You're exhausted and could collapse any moment." | parts],
        else: if(rest > 40, do: ["You're getting tired." | parts], else: parts)

    parts =
      if social > 70,
        do: ["You're desperately lonely and craving company." | parts],
        else: if(social > 40, do: ["You could use some company." | parts], else: parts)

    Enum.join(parts, " ")
  end

  defp nearby_section([]), do: "You're alone — nobody in sight."

  defp nearby_section(agents) do
    descriptions =
      agents
      |> Enum.take(3)
      |> Enum.map(fn a ->
        rel_label =
          case a.relationship_type do
            :friend -> "your friend"
            :close_friend -> "your close friend"
            :rival -> "someone you don't get along with"
            :stranger -> "a stranger"
            _ -> "an acquaintance"
          end

        "#{a.name} (#{rel_label}, looking #{ContextBuilder.affect_name(a.affect)}) is #{a.distance} steps away."
      end)

    "Nearby: " <> Enum.join(descriptions, " ")
  end

  defp social_section(agent_id) do
    SocialInsight.describe_relationships(agent_id) |> ContextBuilder.compress_text()
  end

  @doc false
  @spec episodic_memory_section(String.t()) :: String.t()
  def episodic_memory_section(agent_id) do
    memories = EpisodicMemory.recall(agent_id, limit: 5)

    if memories == [] do
      ""
    else
      lines =
        Enum.map(memories, fn m ->
          content = m.content |> String.slice(0..100)

          emotion_part = if m.emotion, do: " (felt #{m.emotion})", else: ""
          agent_part = if m.related_agent_id, do: " involving #{m.related_agent_id}", else: ""

          "- You remember: #{content}#{emotion_part}#{agent_part}"
        end)

      "Things you remember from your past:\n#{Enum.join(lines, "\n")}"
    end
  end

  @doc false
  @spec conversation_memory_section(String.t(), String.t() | nil) :: String.t()
  def conversation_memory_section(agent_id, interlocutor_name) do
    if interlocutor_name do
      # Get conversations specifically with this interlocutor
      all_convos = ConversationMemory.get_recent(agent_id, 20)

      relevant =
        all_convos
        |> Enum.filter(fn e -> Map.get(e, :partner) == interlocutor_name end)
        |> Enum.take(3)

      if relevant == [] do
        ""
      else
        lines =
          Enum.map(relevant, fn m ->
            msgs =
              Map.get(m, :messages)
              |> Enum.take(3)
              |> Enum.map(fn {speaker, line} -> "#{speaker}: #{line}" end)
              |> Enum.join(" / ")

            "- #{msgs}"
          end)

        "Past conversations with #{interlocutor_name}:\n#{Enum.join(lines, "\n")}"
      end
    else
      # General recent conversations for user chat
      convos = ConversationMemory.format_for_context(agent_id)
      memories = Modus.Persistence.AgentMemory.format_for_context(agent_id)

      parts = []

      parts =
        if convos != "" and convos != nil do
          summarized = ContextBuilder.summarize_memories(convos)
          ["Recent conversations:\n#{summarized}" | parts]
        else
          parts
        end

      parts =
        if memories != "" and memories != nil do
          summarized = ContextBuilder.summarize_memories(memories)
          ["Things you remember:\n#{summarized}" | parts]
        else
          parts
        end

      Enum.join(parts, "\n\n")
    end
  end

  defp affect_memory_section(agent_id) do
    memories = AffectMemory.memories_for_llm_context(agent_id, 3)

    if memories == [] do
      ""
    else
      lines = Enum.map(memories, &("- #{&1}"))
      "Recent emotional experiences:\n#{Enum.join(lines, "\n")}"
    end
  end

  defp goals_section(agent_id) do
    goals = Goals.active_goals(agent_id)

    if goals == [] do
      ""
    else
      lines =
        Enum.map(goals, fn g ->
          pct = round(Goals.ensure_float_pub(g.progress) * 100)
          "- #{Goals.describe(g)} (#{pct}% done)"
        end)

      "Your current goals:\n#{Enum.join(lines, "\n")}"
    end
  end

  @doc false
  @spec desires_section(String.t(), map()) :: String.t()
  def desires_section(agent_id, perception) do
    goals = Goals.active_goals(agent_id)
    affect = perception.affect_state

    if goals == [] and affect != :desire do
      ""
    else
      parts = []

      # Active goals become desires
      parts =
        if goals != [] do
          goal_desires =
            goals
            |> Enum.take(2)
            |> Enum.map(fn g ->
              "You've been wanting to #{String.downcase(Goals.describe(g))}"
            end)

          goal_desires ++ parts
        else
          parts
        end

      # Affect-driven desires
      parts =
        case affect do
          :desire ->
            ["You feel a strong restless drive — you NEED to act on something important." | parts]

          :joy ->
            ["You're in high spirits and want to share your good mood." | parts]

          :sadness ->
            ["You're yearning for comfort and connection." | parts]

          :fear ->
            ["You're looking for safety and reassurance." | parts]

          _ ->
            parts
        end

      if parts == [] do
        ""
      else
        "What's driving you right now:\n" <> (parts |> Enum.map(&("- #{&1}")) |> Enum.join("\n"))
      end
    end
  end

  defp emotional_dynamic_section(agent, target) when is_nil(target), do: ""

  defp emotional_dynamic_section(agent, target) do
    cond do
      agent.affect_state == :sadness and target.affect_state == :joy ->
        "#{target.name} is happy and might try to cheer you up."

      agent.affect_state == :joy and target.affect_state == :sadness ->
        "#{target.name} seems sad — you might want to cheer them up."

      agent.affect_state == :fear ->
        "You're scared — you might seek comfort from #{target.name}."

      agent.affect_state == :sadness and target.affect_state == :sadness ->
        "You're both going through a hard time — you might bond over shared struggle."

      agent.affect_state == :joy and target.affect_state == :joy ->
        "You're both in good spirits — the energy between you is light and playful."

      true ->
        ""
    end
  end

  defp culture_section(agent_id) do
    phrases = Culture.get_catchphrases(agent_id)
    traditions = Culture.list_traditions()

    parts = []

    parts =
      if phrases != [] do
        phrase_lines = Enum.map(phrases, fn p -> "- \"#{p.text}\"" end) |> Enum.join("\n")
        ["Your catchphrases (use them naturally in conversation):\n#{phrase_lines}" | parts]
      else
        parts
      end

    parts =
      if traditions != [] do
        trad_lines =
          traditions
          |> Enum.filter(fn t -> t.strength > 0.2 end)
          |> Enum.take(3)
          |> Enum.map(fn t -> "- #{t.name}: #{t.description}" end)
          |> Enum.join("\n")

        if trad_lines != "",
          do: ["Your community traditions:\n#{trad_lines}" | parts],
          else: parts
      else
        parts
      end

    Enum.join(parts, "\n\n")
  end

  defp season_section do
    try do
      state = Seasons.get_state()
      config = state.config
      season_name = config.name

      tod =
        try do
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

  defp world_history_section do
    try do
      ctx = WorldHistory.history_context()
      if ctx != "" and ctx != nil, do: ctx, else: ""
    catch
      _, _ -> ""
    end
  end

  defp trust_section(agent_id) do
    try do
      Trust.context_for_prompt(agent_id)
    catch
      _, _ -> ""
    end
  end

  defp rules_section(name) do
    """
    RULES:
    - Speak naturally as #{name} would — use your personality
    - If you have goals, mention them naturally when relevant ("I've been wanting to...")
    - Reference your REAL surroundings, feelings, and relationships
    - If hungry, mention it naturally. If tired, sound it. If happy, show it
    - Keep responses 1-3 sentences but make them ALIVE
    - Never say "I'm currently [action]" robotically — weave it into natural speech
    - If someone asks about your world, describe what you actually see
    - Remember past conversations and reference them naturally
    - Your desires and drives should color everything you say
    """
    |> String.trim()
  end

  defp agent_chat_rules(name, target_name, relationship_data) do
    familiarity =
      if relationship_data do
        count = Map.get(relationship_data, :convo_count, 0)

        cond do
          count > 10 -> "You've talked many times — speak with the ease of old friends."
          count > 3 -> "You've spoken a few times — you're getting comfortable."
          count > 0 -> "You've met before but are still getting to know each other."
          true -> "This feels like a fresh encounter."
        end
      else
        "This feels like a fresh encounter."
      end

    """
    RULES:
    - Speak naturally as #{name} would — use your personality
    - #{familiarity}
    - Adjust your tone based on your relationship with #{target_name}
    - Reference shared experiences if you have them
    - Your goals and desires should influence the conversation
    - Keep responses 1-3 sentences but make them feel real
    - Never break character or mention being an AI
    """
    |> String.trim()
  end

  defp relationship_tone(rel) do
    cond do
      String.contains?(rel, "close friend") ->
        "You're close friends — be warm, joke around, share openly."

      String.contains?(rel, "friend") ->
        "You're friends — be friendly, relaxed, open."

      String.contains?(rel, "rival") or String.contains?(rel, "negative") ->
        "There's tension — be guarded, maybe sarcastic."

      true ->
        "You don't know each other well — be curious but cautious."
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0
end
