defmodule Modus.Protocol.DialogueSystem do
  @moduledoc """
  Structured dialogue system for agent communication v2.
  Supports conversation topics: trade, alliance, gossip, warning.
  Topics are driven by agent needs and goals.
  """

  alias Modus.Mind.Cerebro.SocialNetwork
  alias Modus.Simulation.EventLog
  require Logger

  @table :dialogue_history
  @max_history_per_agent 20

  @conversation_topics [:trade, :alliance, :gossip, :warning, :general]

  @topic_icons %{
    trade: "💰",
    alliance: "🤝",
    gossip: "👂",
    warning: "⚠️",
    general: "💬"
  }

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  @doc "Get icon for a conversation topic."
  @spec topic_icon(atom()) :: String.t()
  def topic_icon(topic), do: Map.get(@topic_icons, topic, "💬")

  @doc "All valid conversation topics."
  @spec topics() :: [atom()]
  def topics, do: @conversation_topics

  @doc "Determine conversation topic based on agent needs and goals."
  @spec determine_topic(map(), map()) :: atom()
  def determine_topic(agent, partner) do
    cond do
      # Urgent warning — agent has seen danger
      has_danger_knowledge?(agent) ->
        :warning

      # Trade — agent has surplus and partner has deficit
      wants_to_trade?(agent, partner) ->
        :trade

      # Alliance — high social need or shared group potential
      wants_alliance?(agent, partner) ->
        :alliance

      # Gossip — knows something interesting about others
      has_gossip?(agent) ->
        :gossip

      true ->
        :general
    end
  end

  @doc "Start a structured dialogue between two agents."
  @spec start_dialogue(map(), map(), integer()) :: {:ok, map()} | {:error, term()}
  def start_dialogue(agent, partner, tick) do
    init()
    topic = determine_topic(agent, partner)
    relationship = SocialNetwork.get_relationship(agent.id, partner.id)
    trust = if relationship, do: ensure_float(relationship.strength), else: 0.0

    dialogue = %{
      id: "dlg_#{:erlang.unique_integer([:positive])}",
      topic: topic,
      icon: topic_icon(topic),
      initiator_id: agent.id,
      initiator_name: agent.name,
      partner_id: partner.id,
      partner_name: partner.name,
      trust_level: trust,
      tick: tick,
      messages: [],
      outcome: nil,
      timestamp: System.system_time(:second)
    }

    # Generate opening message based on topic
    opening = generate_opening(agent, partner, topic, trust)
    dialogue = %{dialogue | messages: [opening]}

    # Store in history
    store_dialogue(agent.id, dialogue)
    store_dialogue(partner.id, dialogue)

    # Log event
    EventLog.log(:conversation, tick, [agent.id, partner.id], %{
      type: :structured_dialogue,
      topic: topic,
      icon: topic_icon(topic)
    })

    Logger.debug("[DialogueSystem] #{agent.name} started #{topic} dialogue with #{partner.name}")
    {:ok, dialogue}
  end

  @doc "Get dialogue history for an agent."
  @spec get_history(String.t()) :: [map()]
  def get_history(agent_id) do
    init()
    case :ets.lookup(@table, agent_id) do
      [{_, history}] -> history
      [] -> []
    end
  end

  @doc "Get recent dialogues for an agent."
  @spec get_recent(String.t(), integer()) :: [map()]
  def get_recent(agent_id, count \\ 5) do
    Enum.take(get_history(agent_id), count)
  end

  # ── Topic Determination Helpers ────────────────────────

  defp has_danger_knowledge?(agent) do
    # Check spatial memory or recent memories for danger
    memories = agent.memory || []
    Enum.any?(memories, fn
      {_tick, %{type: :danger}} -> true
      {_tick, %{type: :wildlife_attack}} -> true
      {_tick, event} when is_binary(event) -> String.contains?(event, ["wolf", "danger", "attack"])
      _ -> false
    end)
  end

  defp wants_to_trade?(agent, partner) do
    inv = agent.inventory || %{}
    partner_inv = partner.inventory || %{}
    needs = agent.needs || %{}

    # Agent has surplus of something and is hungry
    has_surplus = Enum.any?(inv, fn {_k, v} -> ensure_float(v) > 5 end)
    is_hungry = ensure_float(Map.get(needs, :hunger, 50)) > 60

    has_surplus or (is_hungry and map_size(partner_inv) > 0)
  end

  defp wants_alliance?(agent, _partner) do
    needs = agent.needs || %{}
    social_need = ensure_float(Map.get(needs, :social, 50))
    social_need > 65
  end

  defp has_gossip?(agent) do
    # Agent knows about other agents' activities
    relationships = agent.relationships || %{}
    map_size(relationships) > 2
  end

  # ── Message Generation ─────────────────────────────────

  defp generate_opening(agent, partner, topic, trust) do
    text = case topic do
      :trade ->
        surplus = agent.inventory |> Map.to_list() |> Enum.max_by(fn {_k, v} -> ensure_float(v) end, fn -> {:nothing, 0} end) |> elem(0)
        "#{agent.name}: I have some #{surplus} to spare. Interested in a trade?"

      :alliance ->
        if trust > 0.5 do
          "#{agent.name}: Friend, we should work together. What do you say?"
        else
          "#{agent.name}: These are tough times. Perhaps we could help each other?"
        end

      :gossip ->
        "#{agent.name}: Have you heard what's been happening around here?"

      :warning ->
        "#{agent.name}: Watch out! I've seen danger nearby."

      :general ->
        greetings = ["Hello there!", "How are you doing?", "Nice to see you!", "What brings you here?"]
        "#{agent.name}: #{Enum.random(greetings)}"
    end

    %{
      speaker: agent.name,
      speaker_id: agent.id,
      text: text,
      topic: topic,
      tick: 0,
      mood: agent.affect_state || :neutral
    }
  end

  # ── Storage ────────────────────────────────────────────

  defp store_dialogue(agent_id, dialogue) do
    existing = get_history(agent_id)
    updated = Enum.take([dialogue | existing], @max_history_per_agent)
    :ets.insert(@table, {agent_id, updated})
  end
end
