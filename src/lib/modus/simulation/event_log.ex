defmodule Modus.Simulation.EventLog do
  @moduledoc """
  EventLog — Central event store for the simulation.

  Stores typed events, keeps max 100 recent, broadcasts via PubSub.

  ## Event Types
  - :conversation — two agents talked
  - :resource_gathered — agent collected a resource
  - :conflict — agents clashed
  - :birth — new agent spawned
  - :death — agent died
  """
  use GenServer

  @max_events 100
  @pubsub Modus.PubSub
  @topic "events"

  defstruct events: [], counter: 0

  @type event_type :: :conversation | :resource_gathered | :conflict | :birth | :death
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

  @doc "Get recent events, optionally filtered by agent_id and/or type."
  @spec recent(keyword()) :: [event()]
  def recent(opts \\ []) do
    GenServer.call(__MODULE__, {:recent, opts})
  end

  @doc "Get event counts by type (v7.3 — for dashboard stats)."
  @spec counts_by_type() :: %{event_type() => non_neg_integer()}
  def counts_by_type do
    GenServer.call(__MODULE__, :counts_by_type)
  catch
    :exit, _ -> %{}
  end

  @doc "Subscribe to event broadcasts."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(state), do: {:ok, state}

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

    Phoenix.PubSub.broadcast(@pubsub, @topic, {:event, event})

    {:noreply, %{state | events: events, counter: id}}
  end

  @impl true
  def handle_call({:recent, opts}, _from, state) do
    agent_id = Keyword.get(opts, :agent_id)
    type = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 20)

    result =
      state.events
      |> maybe_filter_agent(agent_id)
      |> maybe_filter_type(type)
      |> Enum.take(limit)

    {:reply, result, state}
  end

  def handle_call(:counts_by_type, _from, state) do
    counts = Enum.frequencies_by(state.events, & &1.type)
    {:reply, counts, state}
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
