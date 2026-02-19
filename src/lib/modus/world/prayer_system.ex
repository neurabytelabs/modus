defmodule Modus.World.PrayerSystem do
  @moduledoc """
  PrayerSystem — Agents cry out to God; God may answer.

  Spinoza: "Prayer is the mind's intellectual love of God."

  Agents pray based on their state:
  - Low conatus / high fear / desperate needs → help prayer
  - Joy / gratitude → gratitude prayer
  - High openness / neuroticism → existential prayer

  Prayers are stored in ETS for fast reads, GenServer for writes.
  God (the user) can respond via WorldChannel, affecting agent affect state.
  """
  use GenServer
  require Logger

  @pubsub Modus.PubSub
  @prayer_topic "prayers"
  @ets_table :modus_prayers
  @max_prayers 200

  @type prayer_type :: :help | :gratitude | :existential
  @type prayer_status :: :unanswered | :answered_positive | :answered_negative | :silence

  @type prayer :: %{
          id: integer(),
          agent_id: String.t(),
          agent_name: String.t(),
          type: prayer_type(),
          message: String.t(),
          status: prayer_status(),
          tick: non_neg_integer(),
          timestamp: integer(),
          response: String.t() | nil
        }

  # ── Public API ──────────────────────────────────────────

  @doc "Start the PrayerSystem GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "An agent sends a prayer. Returns the prayer map."
  @spec pray(String.t(), String.t(), prayer_type(), non_neg_integer()) :: prayer()
  def pray(agent_id, agent_name, type, tick) do
    GenServer.call(__MODULE__, {:pray, agent_id, agent_name, type, tick})
  end

  @doc "God responds to a prayer. Returns :ok or {:error, reason}."
  @spec respond(integer(), :positive | :negative) :: :ok | {:error, String.t()}
  def respond(prayer_id, response_type) do
    GenServer.call(__MODULE__, {:respond, prayer_id, response_type})
  end

  @doc "Get all prayers (from ETS, fast read). Options: limit, status, agent_id."
  @spec list_prayers(keyword()) :: [prayer()]
  def list_prayers(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status_filter = Keyword.get(opts, :status)
    agent_filter = Keyword.get(opts, :agent_id)

    prayers =
      try do
        :ets.tab2list(@ets_table)
        |> Enum.map(fn {_id, prayer} -> prayer end)
        |> Enum.sort_by(& &1.timestamp, :desc)
      catch
        :error, :badarg -> []
      end

    prayers
    |> maybe_filter_status(status_filter)
    |> maybe_filter_agent(agent_filter)
    |> Enum.take(limit)
  end

  @doc "Get a single prayer by ID (ETS read)."
  @spec get_prayer(integer()) :: prayer() | nil
  def get_prayer(prayer_id) do
    case :ets.lookup(@ets_table, prayer_id) do
      [{^prayer_id, prayer}] -> prayer
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc """
  Check if an agent should pray this tick. Returns {:pray, type} or :no_prayer.
  Call this from the agent tick cycle.
  """
  @spec maybe_pray(map(), non_neg_integer()) :: {:pray, prayer_type()} | :no_prayer
  def maybe_pray(agent_state, _tick) do
    base_prob = 0.005
    desperation = calculate_desperation(agent_state)
    probability = min(base_prob + desperation * 0.05, 0.15)

    if :rand.uniform() < probability do
      {:pray, determine_prayer_type(agent_state)}
    else
      :no_prayer
    end
  end

  @doc "Subscribe to prayer broadcasts."
  @spec subscribe() :: :ok
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @prayer_topic)
  end

  @doc "Get prayer count."
  @spec count() :: non_neg_integer()
  def count do
    try do
      :ets.info(@ets_table, :size) || 0
    catch
      :error, :badarg -> 0
    end
  end

  # ── GenServer Callbacks ─────────────────────────────────

  @impl true
  def init(_) do
    table = :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table, counter: 0}}
  end

  @impl true
  def handle_call({:pray, agent_id, agent_name, type, tick}, _from, state) do
    id = state.counter + 1
    message = generate_prayer_message(agent_name, type)

    prayer = %{
      id: id,
      agent_id: agent_id,
      agent_name: agent_name,
      type: type,
      message: message,
      status: :unanswered,
      tick: tick,
      timestamp: System.system_time(:second),
      response: nil
    }

    :ets.insert(@ets_table, {id, prayer})
    trim_old_prayers()

    # Broadcast to UI
    Phoenix.PubSub.broadcast(@pubsub, @prayer_topic, {:new_prayer, prayer})
    Phoenix.PubSub.broadcast(@pubsub, "world_events", {:world_event, %{
      type: "prayer",
      emoji: prayer_emoji(type),
      severity: 0,
      category: "prayer",
      level: "toast",
      agent_id: agent_id,
      agent_name: agent_name,
      prayer_id: id,
      prayer_type: to_string(type),
      message: message
    }})

    {:reply, prayer, %{state | counter: id}}
  end

  @impl true
  def handle_call({:respond, prayer_id, response_type}, _from, state) do
    case :ets.lookup(@ets_table, prayer_id) do
      [{^prayer_id, prayer}] ->
        status = if response_type == :positive, do: :answered_positive, else: :answered_negative
        response_text = if response_type == :positive, do: "God has answered with grace.", else: "God has turned away."
        updated = %{prayer | status: status, response: response_text}
        :ets.insert(@ets_table, {prayer_id, updated})

        # Apply divine effect to agent
        apply_divine_response(prayer.agent_id, response_type)

        # Broadcast response
        Phoenix.PubSub.broadcast(@pubsub, @prayer_topic, {:prayer_answered, updated})
        Phoenix.PubSub.broadcast(@pubsub, "world_events", {:world_event, %{
          type: "prayer_answered",
          emoji: if(response_type == :positive, do: "✨", else: "🌑"),
          severity: 0,
          category: "prayer",
          level: "toast",
          agent_id: prayer.agent_id,
          agent_name: prayer.agent_name,
          prayer_id: prayer_id,
          response_type: to_string(response_type)
        }})

        {:reply, :ok, state}

      _ ->
        {:reply, {:error, "Prayer not found"}, state}
    end
  end

  # ── Prayer Generation ───────────────────────────────────

  @spec generate_prayer_message(String.t(), prayer_type()) :: String.t()
  defp generate_prayer_message(name, :help) do
    messages = [
      "#{name} cries out: 'O God, I am in need... please help me!'",
      "#{name} kneels and whispers: 'I cannot endure alone...'",
      "#{name} raises trembling hands: 'Have mercy upon me!'",
      "#{name} pleads: 'Grant me strength to survive this trial.'"
    ]
    Enum.random(messages)
  end

  defp generate_prayer_message(name, :gratitude) do
    messages = [
      "#{name} smiles and says: 'Thank you, Creator, for this day.'",
      "#{name} sings softly: 'All praise to the one who sustains us.'",
      "#{name} gazes at the sky: 'I am grateful for what I have.'"
    ]
    Enum.random(messages)
  end

  defp generate_prayer_message(name, :existential) do
    messages = [
      "#{name} ponders: 'Why was I made? What is my purpose?'",
      "#{name} stares into the void: 'Does God hear me?'",
      "#{name} whispers: 'Am I more than my striving?'",
      "#{name} asks: 'Is there meaning beyond survival?'"
    ]
    Enum.random(messages)
  end

  # ── Desperation & Type Logic ────────────────────────────

  @spec calculate_desperation(map()) :: float()
  defp calculate_desperation(agent) do
    conatus_factor = max(0.0, (5.0 - (agent.conatus_score || 5.0)) / 5.0)
    energy_factor = max(0.0, 1.0 - (agent.conatus_energy || 0.7))

    hunger_factor =
      if agent.needs do
        max(0.0, ((agent.needs.hunger || 50.0) - 70.0) / 30.0)
      else
        0.0
      end

    affect_factor =
      case agent.affect_state do
        :fear -> 0.6
        :sadness -> 0.4
        :tristitia -> 0.5
        :anger -> 0.3
        _ -> 0.0
      end

    (conatus_factor + energy_factor + hunger_factor + affect_factor) / 4.0
  end

  @spec determine_prayer_type(map()) :: prayer_type()
  defp determine_prayer_type(agent) do
    desperation = calculate_desperation(agent)

    cond do
      desperation > 0.5 -> :help
      agent.affect_state in [:joy, :neutral] and (agent.conatus_score || 5.0) > 6.0 -> :gratitude
      (agent.personality || %{})[:openness] && agent.personality.openness > 0.7 -> :existential
      (agent.personality || %{})[:neuroticism] && agent.personality.neuroticism > 0.7 -> :existential
      true -> :help
    end
  end

  # ── Divine Response Effects ─────────────────────────────

  @spec apply_divine_response(String.t(), :positive | :negative) :: :ok
  defp apply_divine_response(agent_id, :positive) do
    try do
      case Registry.lookup(Modus.AgentRegistry, agent_id) do
        [{pid, _}] ->
          GenServer.cast(pid, {:divine_intervention, :boost_mood})
          GenServer.cast(pid, {:divine_intervention, :heal})
        _ -> :ok
      end
    catch
      _, _ -> :ok
    end
    :ok
  end

  defp apply_divine_response(agent_id, :negative) do
    try do
      case Registry.lookup(Modus.AgentRegistry, agent_id) do
        [{pid, _}] ->
          GenServer.cast(pid, {:divine_intervention, :drain_mood})
        _ -> :ok
      end
    catch
      _, _ -> :ok
    end
    :ok
  end

  # ── Helpers ─────────────────────────────────────────────

  defp prayer_emoji(:help), do: "🙏"
  defp prayer_emoji(:gratitude), do: "🙌"
  defp prayer_emoji(:existential), do: "🤔"

  defp maybe_filter_status(prayers, nil), do: prayers
  defp maybe_filter_status(prayers, status), do: Enum.filter(prayers, &(&1.status == status))

  defp maybe_filter_agent(prayers, nil), do: prayers
  defp maybe_filter_agent(prayers, agent_id), do: Enum.filter(prayers, &(&1.agent_id == agent_id))

  defp trim_old_prayers do
    size = :ets.info(@ets_table, :size) || 0
    if size > @max_prayers do
      # Remove oldest prayers
      all = :ets.tab2list(@ets_table)
            |> Enum.sort_by(fn {_id, p} -> p.timestamp end)
      to_remove = Enum.take(all, size - @max_prayers)
      Enum.each(to_remove, fn {id, _} -> :ets.delete(@ets_table, id) end)
    end
  end
end
