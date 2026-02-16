defmodule Modus.Mind.Cerebro.AgentConversation do
  @moduledoc "LLM-powered agent-to-agent conversations"

  alias Modus.Mind.Cerebro.SocialNetwork
  alias Modus.Mind.{AffectMemory, Affect}
  alias Modus.Intelligence.LlmProvider
  alias Modus.Simulation.{Agent, EventLog}
  require Logger

  @cooldown_table :conversation_cooldowns
  @cooldown_ticks 50
  @max_concurrent 2

  def init do
    if :ets.whereis(@cooldown_table) == :undefined do
      :ets.new(@cooldown_table, [:set, :public, :named_table])
    end
    # Global concurrent counter (index 1)
    unless :persistent_term.get(:convo_counter, nil) do
      counter = :counters.new(1, [:atomics])
      :persistent_term.put(:convo_counter, counter)
    end
    :ok
  end

  @doc "Check if conversation should happen and trigger it async."
  def maybe_converse(agent, nearby_agent_ids, tick) do
    cond do
      agent.conatus_energy <= 0.3 -> :skipped
      nearby_agent_ids == [] -> :skipped
      agent.current_action not in [:talking, :exploring, :idle] -> :skipped
      true ->
        # Find eligible partner
        partner_id = Enum.find(nearby_agent_ids, fn id ->
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

  defp on_cooldown?(id1, id2, tick) do
    key = canonical_key(id1, id2)
    case :ets.lookup(@cooldown_table, key) do
      [{^key, last_tick}] -> tick - last_tick < @cooldown_ticks
      [] -> false
    end
  end

  defp under_concurrent_limit? do
    counter = :persistent_term.get(:convo_counter)
    :counters.get(counter, 1) < @max_concurrent
  end

  defp start_conversation(agent, partner_id, tick) do
    key = canonical_key(agent.id, partner_id)
    :ets.insert(@cooldown_table, {key, tick})
    counter = :persistent_term.get(:convo_counter)
    :counters.add(counter, 1, 1)

    Task.start(fn ->
      try do
        partner = Agent.get_state(partner_id)
        relationship = SocialNetwork.get_relationship(agent.id, partner_id)
        prompt = build_conversation_prompt(agent, partner, relationship)

        config = LlmProvider.get_config()
        response = case config.provider do
          :antigravity ->
            Modus.Intelligence.AntigravityClient.chat_with_agent(agent, prompt, config)
          _ ->
            Modus.Intelligence.OllamaClient.chat_with_agent(agent, prompt, config)
        end

        dialogue = case response do
          {:ok, text} -> text
          _ -> fallback_dialogue(agent.name, partner.name)
        end

        # Apply effects
        apply_conversation_effects(agent, partner, relationship, tick)

        # Log event
        EventLog.log(:conversation, tick, [agent.id, partner_id], %{
          type: :agent_chat,
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
    rel_desc = case relationship do
      nil -> "İlk kez karşılaşıyorsunuz."
      %{type: :stranger} -> "Birbirinizi pek tanımıyorsunuz."
      %{type: :acquaintance} -> "Birbirinizi tanıyorsunuz (tanıdık)."
      %{type: :friend} -> "Arkadaşsınız."
      %{type: :close_friend} -> "Yakın arkadaşsınız."
    end

    memories1 = AffectMemory.memories_for_llm_context(agent1.id, 3) |> Enum.join("; ")
    memories2 = AffectMemory.memories_for_llm_context(agent2.id, 3) |> Enum.join("; ")

    """
    Sen #{agent1.name} (#{agent1.occupation}). \
    Kişiliğin: dışadönüklük #{Float.round(agent1.personality.extraversion, 1)}, uyumluluk #{Float.round(agent1.personality.agreeableness, 1)}.
    Şu an #{agent1.affect_state} hissediyorsun (enerji: #{Float.round(agent1.conatus_energy, 2)}).
    #{agent2.name} ile karşılaştın. O bir #{agent2.occupation}.
    #{rel_desc}
    #{if memories1 != "", do: "Hatıraların: #{memories1}", else: ""}

    Kısa ve doğal bir diyalog yaz (2-4 satır, Türkçe):
    #{agent1.name}: ...
    #{agent2.name}: ...
    """
  end

  defp apply_conversation_effects(agent, partner, relationship, tick) do
    # Determine event type based on affect
    event_type = cond do
      agent.affect_state == :joy and partner.affect_state == :joy -> :conversation_joy
      agent.affect_state == :sadness or partner.affect_state == :sadness -> :conversation_sad
      true -> :conversation_neutral
    end

    # Update social network
    SocialNetwork.update_relationship(agent.id, partner.id, event_type)

    # Boost conatus and social need via casts
    rel_bonus = if relationship && relationship.strength > 0.5, do: 0.03, else: 0.0
    conatus_boost = 0.05 + rel_bonus

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

    # Form memories for both agents
    AffectMemory.form_memory(
      agent.id, tick, agent.position,
      agent.affect_state, agent.affect_state,
      "#{partner.name} ile konuşma", agent.conatus_energy
    )
    AffectMemory.form_memory(
      partner.id, tick, partner.position,
      partner.affect_state, partner.affect_state,
      "#{agent.name} ile konuşma", partner.conatus_energy
    )
  end

  defp fallback_dialogue(name1, name2) do
    lines = ["Merhaba!", "Nasılsın?", "Hava güzel bugün.", "Dikkat et!", "Birlikte çalışalım mı?"]
    "#{name1}: #{Enum.random(lines)}\n#{name2}: #{Enum.random(lines)}"
  end

  defp canonical_key(id1, id2) when id1 <= id2, do: {id1, id2}
  defp canonical_key(id1, id2), do: {id2, id1}
end
