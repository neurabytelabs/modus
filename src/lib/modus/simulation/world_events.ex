defmodule Modus.Simulation.WorldEvents do
  @moduledoc """
  WorldEvents — Natural disasters and blessings that shape the world.

  Events: storm, earthquake, meteor_shower, plague, golden_age, flood, fire.
  Each has duration, severity (1-3), and an affected area radius.

  Triggered randomly (1% per 100 ticks) or manually via God Mode.

  ## Spinoza: *Natura naturans* — Nature creating itself through events.
  """
  use GenServer

  alias Modus.Simulation.{EventLog, Building, World}

  @pubsub Modus.PubSub

  @event_types ~w(storm earthquake meteor_shower plague golden_age flood fire)a

  @event_config %{
    storm:         %{emoji: "🌩️", color: "grey",   duration: 50,  base_radius: 8,  mood_effect: :fear,     mood_delta: -0.15},
    earthquake:    %{emoji: "🌍", color: "brown",  duration: 20,  base_radius: 12, mood_effect: :fear,     mood_delta: -0.25},
    meteor_shower: %{emoji: "☄️",  color: "orange", duration: 30,  base_radius: 6,  mood_effect: :desire,   mood_delta: 0.1},
    plague:        %{emoji: "🦠", color: "green",  duration: 80,  base_radius: 10, mood_effect: :sadness,  mood_delta: -0.2},
    golden_age:    %{emoji: "✨", color: "gold",   duration: 100, base_radius: 15, mood_effect: :joy,      mood_delta: 0.3},
    flood:         %{emoji: "🌊", color: "blue",   duration: 40,  base_radius: 10, mood_effect: :fear,     mood_delta: -0.15},
    fire:          %{emoji: "🔥", color: "red",    duration: 35,  base_radius: 7,  mood_effect: :fear,     mood_delta: -0.2}
  }

  defstruct active_events: [], history: [], last_check_tick: 0

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc "Get all currently active events."
  @spec active_events() :: [map()]
  def active_events do
    GenServer.call(__MODULE__, :active_events)
  end

  @doc "Manually trigger a world event (God Mode)."
  @spec trigger(atom(), keyword()) :: {:ok, map()}
  def trigger(event_type, opts \\ []) when event_type in @event_types do
    GenServer.call(__MODULE__, {:trigger, event_type, opts})
  end

  @doc "Called by Ticker each tick to update event durations and maybe spawn new ones."
  @spec tick(non_neg_integer()) :: :ok
  def tick(tick_number) do
    GenServer.cast(__MODULE__, {:tick, tick_number})
  end

  @doc "Get serialized active events for the client."
  @spec serialize() :: [map()]
  def serialize do
    GenServer.call(__MODULE__, :serialize)
  end

  @doc "List of valid event type atoms."
  def event_types, do: @event_types

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:active_events, _from, state) do
    {:reply, state.active_events, state}
  end

  @impl true
  def handle_call(:serialize, _from, state) do
    serialized = Enum.map(state.active_events, &serialize_event/1)
    {:reply, serialized, state}
  end

  @impl true
  def handle_call({:trigger, event_type, opts}, _from, state) do
    tick = Keyword.get(opts, :tick, 0)
    severity = Keyword.get(opts, :severity, Enum.random(1..3))
    center = Keyword.get(opts, :center, random_center())

    event = create_event(event_type, tick, severity, center)

    # Apply immediate effects
    apply_effects(event)

    # Broadcast toast + story
    broadcast_event(event)

    new_state = %{state | active_events: [event | state.active_events]}
    {:reply, {:ok, event}, new_state}
  end

  @impl true
  def handle_cast({:tick, tick_number}, state) do
    # Expire finished events
    {expired, active} = Enum.split_with(state.active_events, fn e ->
      tick_number >= e.start_tick + e.duration
    end)

    # Broadcast expiry for each
    for e <- expired do
      Phoenix.PubSub.broadcast(@pubsub, "world_events", {:event_ended, serialize_event(e)})
    end

    # Apply ongoing effects for active events (every 10 ticks)
    if rem(tick_number, 10) == 0 do
      for event <- active, do: apply_ongoing_effects(event, tick_number)
    end

    # Random event check: 1% chance every 100 ticks
    active =
      if rem(tick_number, 100) == 0 and :rand.uniform(100) == 1 do
        event_type = Enum.random(@event_types)
        event = create_event(event_type, tick_number, Enum.random(1..3), random_center())
        apply_effects(event)
        broadcast_event(event)
        [event | active]
      else
        active
      end

    history = expired ++ state.history
    {:noreply, %{state | active_events: active, history: Enum.take(history, 100), last_check_tick: tick_number}}
  end

  # ── Internal ────────────────────────────────────────────

  defp create_event(type, tick, severity, {cx, cy}) do
    config = Map.fetch!(@event_config, type)
    radius = config.base_radius + (severity - 1) * 3
    duration = config.duration * severity

    %{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower),
      type: type,
      severity: severity,
      center: {cx, cy},
      radius: radius,
      duration: duration,
      start_tick: tick,
      config: config
    }
  end

  defp random_center do
    grid_size = try do
      state = World.get_state()
      state.grid_size
    catch
      _, _ -> {100, 100}
    end
    {max_x, max_y} = grid_size
    {:rand.uniform(max_x) - 1, :rand.uniform(max_y) - 1}
  end

  defp apply_effects(event) do
    # Affect agents in radius
    agents = get_agents_in_radius(event.center, event.radius)

    for {pid, _id} <- agents do
      try do
        GenServer.cast(pid, {:boost_need, :social, event.config.mood_delta * 10})

        case event.type do
          :plague -> GenServer.cast(pid, {:boost_need, :hunger, -15.0 * event.severity})
          :golden_age -> GenServer.cast(pid, {:boost_need, :hunger, 20.0})
          :fire -> GenServer.cast(pid, {:boost_need, :rest, -10.0 * event.severity})
          :flood -> GenServer.cast(pid, {:boost_need, :rest, -8.0 * event.severity})
          _ -> :ok
        end
      catch
        :exit, _ -> :ok
      end
    end

    # Damage buildings in radius for destructive events
    if event.type in [:earthquake, :fire, :flood, :storm, :meteor_shower] do
      damage_buildings_in_radius(event.center, event.radius, event.severity * 15)
    end

    # Terrain changes for some events
    apply_terrain_changes(event)
  end

  defp apply_ongoing_effects(event, _tick) do
    # Ongoing: plague drains hunger, fire drains rest
    agents = get_agents_in_radius(event.center, event.radius)
    for {pid, _id} <- agents do
      try do
        case event.type do
          :plague -> GenServer.cast(pid, {:boost_need, :hunger, -2.0})
          :fire -> GenServer.cast(pid, {:boost_need, :rest, -3.0})
          :golden_age -> GenServer.cast(pid, {:boost_need, :hunger, 5.0})
          _ -> :ok
        end
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp apply_terrain_changes(event) do
    {cx, cy} = event.center
    radius = div(event.radius, 2)

    changes = case event.type do
      :fire -> for x <- (cx - radius)..(cx + radius), y <- (cy - radius)..(cy + radius),
                   in_radius?({x, y}, event.center, radius), do: {{x, y}, :desert}
      :flood -> for x <- (cx - radius)..(cx + radius), y <- (cy - radius)..(cy + radius),
                    in_radius?({x, y}, event.center, radius), do: {{x, y}, :water}
      _ -> []
    end

    for {pos, terrain} <- changes do
      try do
        World.paint_terrain(pos, terrain)
      catch
        _, _ -> :ok
      end
    end
  end

  defp damage_buildings_in_radius(center, radius, damage) do
    try do
      buildings = Building.all()
      for b <- buildings, in_radius?(b.position, center, radius) do
        Building.damage(b.id, damage)
      end
    catch
      _, _ -> :ok
    end
  end

  defp get_agents_in_radius({cx, cy}, radius) do
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.filter(fn {_id, pid} ->
      try do
        state = GenServer.call(pid, :get_state, 1_000)
        {ax, ay} = state.position
        in_radius?({ax, ay}, {cx, cy}, radius)
      catch
        :exit, _ -> false
      end
    end)
    |> Enum.map(fn {id, pid} -> {pid, id} end)
  end

  defp in_radius?({x, y}, {cx, cy}, radius) do
    dx = x - cx
    dy = y - cy
    dx * dx + dy * dy <= radius * radius
  end

  defp broadcast_event(event) do
    serialized = serialize_event(event)

    # Toast notification
    Phoenix.PubSub.broadcast(@pubsub, "world_events", {:world_event, serialized})

    # Story engine entry
    EventLog.log(:world_event, event.start_tick, [], %{
      type: event.type,
      severity: event.severity,
      center: event.center,
      radius: event.radius,
      duration: event.duration
    })
  end

  defp serialize_event(event) do
    {cx, cy} = event.center
    %{
      id: event.id,
      type: to_string(event.type),
      severity: event.severity,
      center_x: cx,
      center_y: cy,
      radius: event.radius,
      duration: event.duration,
      start_tick: event.start_tick,
      emoji: event.config.emoji,
      color: event.config.color,
      remaining: max(0, event.start_tick + event.duration - (try do Modus.Simulation.Ticker.current_tick() catch _, _ -> 0 end))
    }
  end
end
