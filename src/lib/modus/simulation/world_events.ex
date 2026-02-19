defmodule Modus.Simulation.WorldEvents do
  @moduledoc """
  WorldEvents v2 — Dynamic world events with chains, probability, and recovery.

  v3.5.0 Eventus additions:
  - Event chains: drought→famine→migration→conflict
  - Player-triggered events via God Mode (expanded)
  - Discovery events: hidden locations/artifacts
  - Festival/celebration when happiness high
  - Migration waves: new agents arrive
  - Natural disasters with recovery period
  - Context-aware probability system

  ## Spinoza: *Natura naturans* — Nature creating itself through events.
  """
  use GenServer

  alias Modus.Simulation.{EventLog, Building, World, EventChain, EventProbability}

  @pubsub Modus.PubSub

  @event_types ~w(storm earthquake meteor_shower plague golden_age flood fire drought famine festival discovery migration_wave conflict)a

  @event_config %{
    storm: %{
      emoji: "🌩️",
      color: "grey",
      duration: 50,
      base_radius: 8,
      mood_effect: :fear,
      mood_delta: -0.15,
      category: :disaster
    },
    earthquake: %{
      emoji: "🌍",
      color: "brown",
      duration: 20,
      base_radius: 12,
      mood_effect: :fear,
      mood_delta: -0.25,
      category: :disaster
    },
    meteor_shower: %{
      emoji: "☄️",
      color: "orange",
      duration: 30,
      base_radius: 6,
      mood_effect: :desire,
      mood_delta: 0.1,
      category: :discovery
    },
    plague: %{
      emoji: "🦠",
      color: "green",
      duration: 80,
      base_radius: 10,
      mood_effect: :sadness,
      mood_delta: -0.2,
      category: :disaster
    },
    golden_age: %{
      emoji: "✨",
      color: "gold",
      duration: 100,
      base_radius: 15,
      mood_effect: :joy,
      mood_delta: 0.3,
      category: :celebration
    },
    flood: %{
      emoji: "🌊",
      color: "blue",
      duration: 40,
      base_radius: 10,
      mood_effect: :fear,
      mood_delta: -0.15,
      category: :disaster
    },
    fire: %{
      emoji: "🔥",
      color: "red",
      duration: 35,
      base_radius: 7,
      mood_effect: :fear,
      mood_delta: -0.2,
      category: :disaster
    },
    drought: %{
      emoji: "🏜️",
      color: "amber",
      duration: 120,
      base_radius: 15,
      mood_effect: :sadness,
      mood_delta: -0.1,
      category: :disaster
    },
    famine: %{
      emoji: "💀🌾",
      color: "red",
      duration: 100,
      base_radius: 20,
      mood_effect: :sadness,
      mood_delta: -0.25,
      category: :disaster
    },
    festival: %{
      emoji: "🎉",
      color: "gold",
      duration: 40,
      base_radius: 12,
      mood_effect: :joy,
      mood_delta: 0.2,
      category: :celebration
    },
    discovery: %{
      emoji: "🗺️",
      color: "cyan",
      duration: 10,
      base_radius: 5,
      mood_effect: :desire,
      mood_delta: 0.15,
      category: :discovery
    },
    migration_wave: %{
      emoji: "🚶",
      color: "green",
      duration: 30,
      base_radius: 10,
      mood_effect: :desire,
      mood_delta: 0.05,
      category: :migration
    },
    conflict: %{
      emoji: "⚔️",
      color: "red",
      duration: 60,
      base_radius: 8,
      mood_effect: :fear,
      mood_delta: -0.2,
      category: :disaster
    }
  }

  @discovery_artifacts [
    %{name: "Ancient Ruins", emoji: "🏛️", bonus: :knowledge},
    %{name: "Hidden Spring", emoji: "💧", bonus: :water},
    %{name: "Crystal Cave", emoji: "💎", bonus: :wealth},
    %{name: "Sacred Grove", emoji: "🌳", bonus: :healing},
    %{name: "Meteor Fragment", emoji: "🌠", bonus: :technology},
    %{name: "Old Map", emoji: "🗺️", bonus: :exploration}
  ]

  defstruct active_events: [],
            history: [],
            last_check_tick: 0,
            scheduled_chains: [],
            recovery_zones: [],
            last_event_tick: 0

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @spec active_events() :: [map()]
  def active_events do
    GenServer.call(__MODULE__, :active_events)
  end

  @spec trigger(atom(), keyword()) :: {:ok, map()}
  def trigger(event_type, opts \\ []) when event_type in @event_types do
    GenServer.call(__MODULE__, {:trigger, event_type, opts})
  end

  @spec tick(non_neg_integer()) :: :ok
  def tick(tick_number) do
    GenServer.cast(__MODULE__, {:tick, tick_number})
  end

  @spec serialize() :: [map()]
  def serialize do
    GenServer.call(__MODULE__, :serialize)
  end

  def event_types, do: @event_types
  def event_config, do: @event_config

  @doc "Get recovery zones (areas healing after disasters)."
  def recovery_zones do
    GenServer.call(__MODULE__, :recovery_zones)
  end

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
  def handle_call(:recovery_zones, _from, state) do
    {:reply, state.recovery_zones, state}
  end

  @impl true
  def handle_call({:trigger, event_type, opts}, _from, state) do
    tick = Keyword.get(opts, :tick, 0)
    severity = Keyword.get(opts, :severity, Enum.random(1..3))
    center = Keyword.get(opts, :center, random_center())

    event = create_event(event_type, tick, severity, center)
    apply_effects(event)
    broadcast_event(event)

    # Schedule chain reactions
    chains = EventChain.evaluate(event_type, tick, severity)

    new_scheduled =
      state.scheduled_chains ++
        Enum.map(chains, fn {type, trigger_tick, sev} ->
          %{
            type: type,
            tick: trigger_tick,
            severity: sev,
            center: random_center(),
            source: event_type
          }
        end)

    new_state = %{
      state
      | active_events: [event | state.active_events],
        scheduled_chains: new_scheduled,
        last_event_tick: tick
    }

    {:reply, {:ok, event}, new_state}
  end

  @impl true
  def handle_cast({:tick, tick_number}, state) do
    # 1. Expire finished events + create recovery zones
    {expired, active} =
      Enum.split_with(state.active_events, fn e ->
        tick_number >= e.start_tick + e.duration
      end)

    new_recovery =
      for e <- expired, e.config.category == :disaster do
        %{
          center: e.center,
          radius: e.radius,
          start_tick: tick_number,
          duration: e.duration * 2,
          type: e.type
        }
      end

    for e <- expired do
      Phoenix.PubSub.broadcast(@pubsub, "world_events", {:event_ended, serialize_event(e)})
    end

    # 2. Ongoing effects every 10 ticks
    if rem(tick_number, 10) == 0 do
      for event <- active, do: apply_ongoing_effects(event, tick_number)
    end

    # 3. Process scheduled chain events
    {ready_chains, pending_chains} =
      Enum.split_with(state.scheduled_chains, fn c ->
        tick_number >= c.tick
      end)

    {chain_events, chain_scheduled} =
      Enum.reduce(ready_chains, {[], []}, fn chain, {events, scheds} ->
        event = create_event(chain.type, tick_number, chain.severity, chain.center)
        apply_effects(event)
        broadcast_event(event, chain.source)

        # Nested chains
        new_chains = EventChain.evaluate(chain.type, tick_number, chain.severity)

        new_scheds =
          Enum.map(new_chains, fn {type, trigger_tick, sev} ->
            %{
              type: type,
              tick: trigger_tick,
              severity: sev,
              center: random_center(),
              source: chain.type
            }
          end)

        {[event | events], scheds ++ new_scheds}
      end)

    # 4. Probability-based random events (every 50 ticks)
    {new_random_events, new_random_chains} =
      if rem(tick_number, 50) == 0 do
        context = build_context(tick_number, state, active)

        case EventProbability.roll(context) do
          {event_type, severity} ->
            event = create_event(event_type, tick_number, severity, random_center())
            apply_effects(event)
            broadcast_event(event)
            chains = EventChain.evaluate(event_type, tick_number, severity)

            new_scheds =
              Enum.map(chains, fn {type, trigger_tick, sev} ->
                %{
                  type: type,
                  tick: trigger_tick,
                  severity: sev,
                  center: random_center(),
                  source: event_type
                }
              end)

            {[event], new_scheds}

          nil ->
            {[], []}
        end
      else
        {[], []}
      end

    # 5. Expire old recovery zones
    recovery =
      (state.recovery_zones ++ new_recovery)
      |> Enum.reject(fn r -> tick_number > r.start_tick + r.duration end)

    # 6. Recovery: slowly restore terrain in recovery zones (every 20 ticks)
    if rem(tick_number, 20) == 0 do
      for zone <- recovery, do: apply_recovery(zone)
    end

    all_active = new_random_events ++ chain_events ++ active
    all_scheduled = pending_chains ++ chain_scheduled ++ new_random_chains
    history = Enum.take(expired ++ state.history, 200)

    {:noreply,
     %{
       state
       | active_events: all_active,
         history: history,
         last_check_tick: tick_number,
         scheduled_chains: all_scheduled,
         recovery_zones: recovery,
         last_event_tick:
           if(new_random_events != [] or chain_events != [],
             do: tick_number,
             else: state.last_event_tick
           )
     }}
  end

  # ── Internal ────────────────────────────────────────────

  defp build_context(tick, state, active_events) do
    season =
      try do
        s = Modus.Simulation.Seasons.current_season()
        s.name
      catch
        _, _ -> :spring
      end

    {population, avg_happiness} =
      try do
        agents =
          Registry.select(Modus.AgentRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])

        pop = length(agents)

        happiness =
          if pop > 0 do
            total =
              Enum.reduce(agents, 0.0, fn {_id, pid}, acc ->
                try do
                  s = GenServer.call(pid, :get_state, 500)
                  acc + (s.conatus_energy || 0.5)
                catch
                  :exit, _ -> acc + 0.5
                end
              end)

            total / pop
          else
            0.5
          end

        {pop, happiness}
      catch
        _, _ -> {10, 0.5}
      end

    %{
      season: season,
      avg_happiness: avg_happiness,
      population: population,
      # Simplified
      food_ratio: 0.6,
      ticks_since_last_event: tick - (state.last_event_tick || 0),
      active_event_count: length(active_events || [])
    }
  end

  defp create_event(type, tick, severity, {cx, cy}) do
    config = Map.get(@event_config, type, Map.fetch!(@event_config, :storm))
    radius = config.base_radius + (severity - 1) * 3
    duration = config.duration * severity

    artifact = if type == :discovery, do: Enum.random(@discovery_artifacts), else: nil

    %{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower),
      type: type,
      severity: severity,
      center: {cx, cy},
      radius: radius,
      duration: duration,
      start_tick: tick,
      config: config,
      artifact: artifact
    }
  end

  defp random_center do
    grid_size =
      try do
        state = World.get_state()
        state.grid_size
      catch
        _, _ -> {100, 100}
      end

    {max_x, max_y} = grid_size
    {:rand.uniform(max_x) - 1, :rand.uniform(max_y) - 1}
  end

  defp apply_effects(event) do
    agents = get_agents_in_radius(event.center, event.radius)

    for {pid, _id} <- agents do
      try do
        GenServer.cast(pid, {:boost_need, :social, event.config.mood_delta * 10})

        case event.type do
          :plague ->
            GenServer.cast(pid, {:boost_need, :hunger, -15.0 * event.severity})

          :golden_age ->
            GenServer.cast(pid, {:boost_need, :hunger, 20.0})

          :fire ->
            GenServer.cast(pid, {:boost_need, :rest, -10.0 * event.severity})

          :flood ->
            GenServer.cast(pid, {:boost_need, :rest, -8.0 * event.severity})

          :drought ->
            GenServer.cast(pid, {:boost_need, :hunger, -8.0 * event.severity})

          :famine ->
            GenServer.cast(pid, {:boost_need, :hunger, -20.0 * event.severity})

          :festival ->
            GenServer.cast(pid, {:boost_need, :social, 15.0})

          :conflict ->
            GenServer.cast(pid, {:boost_need, :rest, -12.0 * event.severity})

          :discovery ->
            GenServer.cast(pid, {:boost_need, :social, 10.0})

          _ ->
            :ok
        end
      catch
        :exit, _ -> :ok
      end
    end

    # Damage buildings for destructive events
    if event.config.category == :disaster and event.type not in [:drought, :famine] do
      damage_buildings_in_radius(event.center, event.radius, event.severity * 15)
    end

    # Migration: spawn new agents
    if event.type == :migration_wave do
      spawn_migrants(event.severity)
    end

    apply_terrain_changes(event)
  end

  defp apply_ongoing_effects(event, _tick) do
    agents = get_agents_in_radius(event.center, event.radius)

    for {pid, _id} <- agents do
      try do
        case event.type do
          :plague -> GenServer.cast(pid, {:boost_need, :hunger, -2.0})
          :fire -> GenServer.cast(pid, {:boost_need, :rest, -3.0})
          :golden_age -> GenServer.cast(pid, {:boost_need, :hunger, 5.0})
          :drought -> GenServer.cast(pid, {:boost_need, :hunger, -1.5})
          :famine -> GenServer.cast(pid, {:boost_need, :hunger, -3.0})
          :festival -> GenServer.cast(pid, {:boost_need, :social, 2.0})
          :conflict -> GenServer.cast(pid, {:boost_need, :rest, -2.0})
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

    changes =
      case event.type do
        :fire ->
          for x <- (cx - radius)..(cx + radius),
              y <- (cy - radius)..(cy + radius),
              in_radius?({x, y}, event.center, radius),
              do: {{x, y}, :desert}

        :flood ->
          for x <- (cx - radius)..(cx + radius),
              y <- (cy - radius)..(cy + radius),
              in_radius?({x, y}, event.center, radius),
              do: {{x, y}, :water}

        :drought ->
          for x <- (cx - radius)..(cx + radius),
              y <- (cy - radius)..(cy + radius),
              in_radius?({x, y}, event.center, radius),
              do: {{x, y}, :desert}

        _ ->
          []
      end

    for {pos, terrain} <- changes do
      try do
        World.paint_terrain(pos, terrain)
      catch
        _, _ -> :ok
      end
    end
  end

  defp apply_recovery(zone) do
    {cx, cy} = zone.center
    radius = div(zone.radius, 3)
    # Slowly restore some tiles to grass
    spot =
      {:rand.uniform(radius * 2 + 1) - radius - 1 + cx,
       :rand.uniform(radius * 2 + 1) - radius - 1 + cy}

    try do
      World.paint_terrain(spot, :grass)
    catch
      _, _ -> :ok
    end
  end

  defp spawn_migrants(severity) do
    count = severity + :rand.uniform(2)

    try do
      Modus.Simulation.World.spawn_initial_agents(count)
    catch
      _, _ -> :ok
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

  defp broadcast_event(event, source \\ nil) do
    serialized = serialize_event(event)

    # Determine notification level
    level =
      cond do
        event.severity >= 3 -> :breaking
        event.config.category in [:disaster, :celebration] and event.severity >= 2 -> :breaking
        true -> :toast
      end

    serialized =
      Map.merge(serialized, %{
        level: to_string(level),
        category: to_string(event.config.category),
        chain_source: if(source, do: to_string(source), else: nil),
        artifact:
          if(event.artifact,
            do: %{
              name: event.artifact.name,
              emoji: event.artifact.emoji,
              bonus: to_string(event.artifact.bonus)
            },
            else: nil
          )
      })

    Phoenix.PubSub.broadcast(@pubsub, "world_events", {:world_event, serialized})

    EventLog.log(:world_event, event.start_tick, [], %{
      type: event.type,
      severity: event.severity,
      center: event.center,
      radius: event.radius,
      duration: event.duration,
      category: event.config.category,
      chain_source: source,
      artifact: event.artifact
    })
  end

  defp serialize_event(event) do
    {cx, cy} = event.center

    current_tick =
      try do
        Modus.Simulation.Ticker.current_tick()
      catch
        _, _ -> 0
      end

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
      category: to_string(event.config.category),
      remaining: max(0, event.start_tick + event.duration - current_tick)
    }
  end
end
