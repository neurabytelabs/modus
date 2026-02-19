defmodule Modus.Simulation.EventLog do
  @moduledoc """
  EventLog — Central event store for the simulation.

  Stores typed events, keeps max 100 recent, broadcasts via PubSub.

  ## v7.6: ETS Read Path

  Events are mirrored to ETS for O(1) reads from WorldChannel/Observatory.
  `recent/1` and `counts_by_type/0` read directly from ETS without GenServer.call.

  ## Event Types
  - :conversation — two agents talked
  - :resource_gathered — agent collected a resource
  - :conflict — agents clashed
  - :birth — new agent spawned
  - :death — agent died
  - :tick_lag — ticker performance degradation (v7.6)
  """
  use GenServer

  @max_events 100
  @pubsub Modus.PubSub
  @topic "events"
  @ets_table :event_log_cache

  defstruct events: [], counter: 0

  @type event_type :: :conversation | :resource_gathered | :conflict | :birth | :death | :tick_lag
  @type event :: %{
          id: integer(),
          type: event_type(),
          tick: integer(),
          agents: [String.t()],
          data: map(),
          timestamp: DateTime.t()
        }

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc "Log a new event and broadcast it."
  @spec log(event_type(), integer(), [String.t()], map()) :: :ok
  def log(type, tick, agent_ids, data \\ %{}) do
    GenServer.cast(__MODULE__, {:log, type, tick, agent_ids, data})
  end

  @doc "Get recent events, optionally filtered. Reads from ETS (v7.6 — no GenServer.call)."
  @spec recent(keyword()) :: [event()]
  def recent(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    type = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 20)

    case :ets.whereis(@ets_table) do
      :undefined -> []
      _ ->
        case :ets.lookup(@ets_table, :events) do
          [{:events, events}] ->
            events
            |> maybe_filter_agent(agent_id)
            |> maybe_filter_type(type)
            |> Enum.take(limit)
          [] -> []
        end
    end
  rescue
    _ -> []
  end

  @doc "Get event counts by type. Reads from ETS (v7.6)."
  @spec counts_by_type() :: %{event_type() => non_neg_integer()}
  def counts_by_type do
    case :ets.whereis(@ets_table) do
      :undefined -> %{}
      _ ->
        case :ets.lookup(@ets_table, :counts) do
          [{:counts, counts}] -> counts
          [] -> %{}
        end
    end
  rescue
    _ -> %{}
  end

  @doc "Get events since a given tick number (v7.7 — ordered_set O(log n) range query)."
  @spec since_tick(non_neg_integer(), non_neg_integer()) :: [event()]
  def since_tick(tick_number, limit \\ 50) do
    case :ets.whereis(:event_log_by_tick) do
      :undefined -> []
      _ ->
        key = {tick_number, 0}
        collect_from_key(:ets.next(:event_log_by_tick, key), [], limit)
    end
  rescue
    _ -> []
  end

  defp collect_from_key(:"$end_of_table", acc, _limit), do: Enum.reverse(acc)
  defp collect_from_key(_key, acc, limit) when length(acc) >= limit, do: Enum.reverse(acc)

  defp collect_from_key(key, acc, limit) do
    case :ets.lookup(:event_log_by_tick, key) do
      [{_k, event}] ->
        collect_from_key(:ets.next(:event_log_by_tick, key), [event | acc], limit)
      [] ->
        collect_from_key(:ets.next(:event_log_by_tick, key), acc, limit)
    end
  end

  @doc "Subscribe to event broadcasts."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(state) do
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.insert(@ets_table, {:events, []})
    :ets.insert(@ets_table, {:counts, %{}})
    # v7.7: ordered_set for efficient time-range queries by tick
    :ets.new(:event_log_by_tick, [:named_table, :ordered_set, :public, read_concurrency: true])
    {:ok, state}
  end

  @impl true
  def handle_cast({:log, type, tick, agent_ids, data}, state) do
    id = state.counter + 1

    event = %{
      id: id,
      type: type,
      tick: tick,
      agents: agent_ids,
      data: data,
      timestamp: DateTime.utc_now()
    }

    events = Enum.take([event | state.events], @max_events)

    # Update ETS cache
    :ets.insert(@ets_table, {:events, events})
    :ets.insert(@ets_table, {:counts, Enum.frequencies_by(events, & &1.type)})

    # v7.7: Insert into ordered_set for time-range queries (key = {tick, id} for uniqueness)
    try do
      :ets.insert(:event_log_by_tick, {{tick, id}, event})
    catch
      _, _ -> :ok
    end

    Phoenix.PubSub.broadcast(@pubsub, @topic, {:event, event})

    {:noreply, %{state | events: events, counter: id}}
  end

  defp maybe_filter_agent(events, nil), do: events

  defp maybe_filter_agent(events, agent_id) do
    Enum.filter(events, fn e -> agent_id in e.agents end)
  end

  defp maybe_filter_type(events, nil), do: events
  defp maybe_filter_type(events, type), do: Enum.filter(events, fn e -> e.type == type end)

  # Catch-all for unexpected messages
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
