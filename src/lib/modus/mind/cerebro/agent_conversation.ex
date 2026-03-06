defmodule Modus.Mind.Cerebro.AgentConversation do
  @moduledoc "LLM-powered agent-to-agent conversations"

  alias Modus.Mind.Cerebro.SocialNetwork
  alias Modus.Mind.AffectMemory
  alias Modus.Intelligence.LlmProvider
  alias Modus.Simulation.{Agent, EventLog}
  alias Modus.Protocol.ConsciousChatPrompt

  alias Modus.Protocol.{
    DialogueSystem,
    Persuasion,
    InformationSharing,
    RumorSystem,
    SecretKeeping
  }

  require Logger

  @cooldown_table :conversation_cooldowns
  @cooldown_ticks 50
  @max_concurrent 2
  @error_backoff_key :convo_error_backoff
  @error_backoff_ticks 200
  @max_consecutive_errors 3

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  def init do
    try do
      if :ets.whereis(@cooldown_table) == :undefined do
        :ets.new(@cooldown_table, [:set, :public, :named_table])
      end
    rescue
      ArgumentError -> :ok
    end

    # Global concurrent counter (index 1)
    unless :persistent_term.get(:convo_counter, nil) do
      counter = :counters.new(1, [:atomics])
      :persistent_term.put(:convo_counter, counter)
    end

    :ok
  end

  @doc "Check if a pair is on cooldown (public for world_channel dedup)."
  def on_cooldown_public?(id1, id2, tick), do: on_cooldown?(id1, id2, tick)

  @doc "Check if conversation should happen and trigger it async."
  def maybe_converse(nil, _nearby_agent_ids, _tick), do: :skipped
  def maybe_converse(_agent, nil, _tick), do: :skipped
  def maybe_converse(%{id: nil}, _nearby_agent_ids, _tick), do: :skipped

  def maybe_converse(agent, nearby_agent_ids, tick) do
    cond do
      in_error_backoff?(tick) ->
        :skipped

      agent.conatus_energy <= 0.3 ->
        :skipped

      nearby_agent_ids == [] ->
        :skipped

      agent.current_action not in [:talking, :exploring, :idle] ->
        :skipped

      true ->
        # Find eligible partner
        partner_id =
          Enum.find(nearby_agent_ids, fn id ->
            id != agent.id and not on_cooldown?(agent.id, id, tick)
          end)

        if partner_id && under_concurrent_limit?() do
          start_conversation(agent, partner_id, tick)
          :ok
        else
          :skipped
        end
    end
  end

  defp in_error_backoff?(tick) do
    case :persistent_term.get(@error_backoff_key, nil) do
      {errors, backoff_since} when errors >= @max_consecutive_errors ->
        tick - backoff_since < @error_backoff_ticks

      _ ->
        false
    end
  end

  defp record_convo_error(tick) do
    case :persistent_term.get(@error_backoff_key, nil) do
      {errors, since} -> :persistent_term.put(@error_backoff_key, {errors + 1, since || tick})
      nil -> :persistent_term.put(@error_backoff_key, {1, tick})
    end
  end

  defp record_convo_success do
    :persistent_term.put(@error_backoff_key, {0, 0})
  end

  defp on_cooldown?(id1, id2, tick) do
    key = canonical_key(id1, id2)

    try do
      case :ets.lookup(@cooldown_table, key) do
        [{^key, last_tick}] -> tick - last_tick < @cooldown_ticks
        [] -> false
      end
    rescue
      ArgumentError -> false
    end
  end

  defp under_concurrent_limit? do
    counter = :persistent_term.get(:convo_counter, nil)
    if counter, do: :counters.get(counter, 1) < @max_concurrent, else: true
  end

  defp start_conversation(agent, partner_id, tick) do
    key = canonical_key(agent.id, partner_id)
    :ets.insert(@cooldown_table, {key, tick})
    counter = :persistent_term.get(:convo_counter)
    :counters.add(counter, 1, 1)

    Task.start(fn ->
      try do
        # Guard: skip if partner agent process is dead (prevents :noproc loop)
        case Registry.lookup(Modus.AgentRegistry, partner_id) do
          [] ->
            Logger.debug("Skipping conversation: partner #{partner_id} not registered")
            throw(:partner_not_registered)

          _ ->
            :ok
        end

        partner = Agent.get_state(partner_id)

        if is_nil(partner) do
          Logger.debug("Skipping conversation: partner #{partner_id} state is nil")
          throw(:partner_state_nil)
        end

        relationship = SocialNetwork.get_relationship(agent.id, partner_id)
        prompt = ConsciousChatPrompt.build(agent, "conversation", target_agent_id: partner.id)

        config = LlmProvider.get_config()

        response =
          case config.provider do
            :gemini ->
              Modus.Intelligence.GeminiClient.chat_with_agent(agent, prompt, config)

            _ ->
              Modus.Intelligence.OllamaClient.chat_with_agent(agent, prompt, config)
          end

        dialogue =
          case response do
            {:ok, text} ->
              record_convo_success()
              text

            _ ->
              record_convo_error(tick)
              fallback_dialogue(agent.name, partner.name)
          end

        # v3.4.0 Nexus: Structured dialogue with topic
        topic = DialogueSystem.determine_topic(agent, partner)
        DialogueSystem.start_dialogue(agent, partner, tick)

        # v3.4.0: Share spatial knowledge based on trust
        trust = if relationship, do: ensure_float(relationship.strength), else: 0.0
        InformationSharing.share_knowledge(agent.id, partner.id, trust)
        InformationSharing.share_knowledge(partner.id, agent.id, trust)

        # v3.4.0: Spread rumors during gossip
        if topic == :gossip do
          spreadable = RumorSystem.get_spreadable(agent.id)

          case List.first(spreadable) do
            nil -> :ok
            rumor -> RumorSystem.spread_rumor(agent.id, partner.id, rumor.id, tick)
          end
        end

        # v3.4.0: Share secrets with close friends
        if trust > 0.6 do
          shareable = SecretKeeping.shareable_secrets(agent.id, trust)

          case List.first(shareable) do
            nil -> :ok
            secret -> SecretKeeping.try_share(agent.id, partner.id, secret.id, trust)
          end
        end

        # v3.4.0: Persuasion during trade/alliance topics
        if topic in [:trade, :alliance] do
          Persuasion.attempt(agent, partner, topic)
        end

        # Record to AgentChatViewer for real-time streaming
        try do
          Modus.World.AgentChatViewer.record_chat(%{
            agent_a_id: agent.id,
            agent_b_id: partner.id,
            agent_a_name: agent.name,
            agent_b_name: partner.name,
            messages: dialogue,
            topic: topic,
            tick: tick,
            affect_a: agent.affect_state,
            affect_b: partner.affect_state
          })
        catch
          :exit, _ -> :ok
        end

        # Apply effects
        apply_conversation_effects(agent, partner, relationship, tick)

        # Log event with topic info
        EventLog.log(:conversation, tick, [agent.id, partner_id], %{
          type: :structured_dialogue,
          topic: topic,
          icon: DialogueSystem.topic_icon(topic),
          dialogue: dialogue
        })

        Logger.debug("Cerebro conversation: #{agent.name} <-> #{partner.name}")
      catch
        kind, reason ->
          Logger.warning("Conversation failed: #{inspect({kind, reason})}")
      after
        :counters.sub(counter, 1, 1)
      end
    end)
  end

  def build_conversation_prompt(agent1, agent2, relationship) do
    rel_desc =
      case relationship do
        nil -> "You're meeting for the first time."
        %{type: :stranger} -> "You barely know each other."
        %{type: :acquaintance} -> "You're acquaintances."
        %{type: :friend} -> "You're friends."
        %{type: :close_friend} -> "You're close friends."
      end

    memories1 = AffectMemory.memories_for_llm_context(agent1.id, 3) |> Enum.join("; ")
    _memories2 = AffectMemory.memories_for_llm_context(agent2.id, 3) |> Enum.join("; ")

    speech_style = Modus.Protocol.PersonalityPromptBuilder.build(
      agent1.personality, agent1.affect_state, agent1.conatus_energy
    )

    """
    You are #{agent1.name} (#{agent1.occupation}). \
    Personality: extraversion #{Float.round(ensure_float(agent1.personality.extraversion), 1)}, agreeableness #{Float.round(ensure_float(agent1.personality.agreeableness), 1)}.
    You're feeling #{agent1.affect_state} (energy: #{Float.round(ensure_float(agent1.conatus_energy), 2)}).

    SPEECH STYLE: #{speech_style}

    You run into #{agent2.name}. They're a #{agent2.occupation}.
    #{rel_desc}
    #{if memories1 != "", do: "Your memories: #{memories1}", else: ""}

    Write a short, natural dialogue (2-4 lines, English):
    #{agent1.name}: ...
    #{agent2.name}: ...
    """
  end

  defp apply_conversation_effects(agent, partner, relationship, tick) do
    # Determine event type based on affect
    event_type =
      cond do
        agent.affect_state == :joy and partner.affect_state == :joy -> :conversation_joy
        agent.affect_state == :sadness or partner.affect_state == :sadness -> :conversation_sad
        true -> :conversation_neutral
      end

    # Update social network
    SocialNetwork.update_relationship(agent.id, partner.id, event_type)

    # Spread culture between conversing agents
    Modus.Mind.Culture.spread_culture(agent.id, partner.id, tick)

    # Boost conatus and social need via casts
    rel_bonus = if relationship && relationship.strength > 0.5, do: 0.03, else: 0.0
    _conatus_boost = 0.05 + rel_bonus

    for id <- [agent.id, partner.id] do
      try do
        GenServer.cast(
          {:via, Registry, {Modus.AgentRegistry, id}},
          {:boost_need, :social, -15.0}
        )
      catch
        :exit, _ -> :ok
      end
    end

    # Record to persistent long-term memory if emotionally significant
    if agent.affect_state in [:joy, :fear, :sadness, :desire] do
      Modus.Persistence.AgentMemory.maybe_record_from_event(
        agent.id,
        agent.name,
        :conversation,
        tick,
        %{partner: partner.name, affect: agent.affect_state}
      )
    end

    # Form memories for both agents
    AffectMemory.form_memory(
      agent.id,
      tick,
      agent.position,
      agent.affect_state,
      agent.affect_state,
      "Conversation with #{partner.name}",
      agent.conatus_energy
    )

    AffectMemory.form_memory(
      partner.id,
      tick,
      partner.position,
      partner.affect_state,
      partner.affect_state,
      "Conversation with #{agent.name}",
      partner.conatus_energy
    )
  end

  defp fallback_dialogue(name1, name2) do
    lines = [
      "Hello!",
      "How are you?",
      "Nice weather today.",
      "Watch out!",
      "Want to work together?"
    ]

    "#{name1}: #{Enum.random(lines)}\n#{name2}: #{Enum.random(lines)}"
  end

  defp canonical_key(id1, id2) when id1 <= id2, do: {id1, id2}
  defp canonical_key(id1, id2), do: {id2, id1}
end
