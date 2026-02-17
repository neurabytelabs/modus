defmodule Modus.Simulation.NatureEvents do
  @moduledoc """
  NatureEvents — Ecological disasters that affect wildlife and terrain.

  Events:
  - `:forest_fire`   — burns trees, kills animals in area
  - `:flood`         — displaces creatures, changes terrain to water temporarily
  - `:locust_swarm`  — destroys crops on farm tiles

  Integrates with Wildlife for animal casualties and World for terrain changes.

  ## Spinoza: *Natura naturata* — Nature as the unfolding of necessary events.
  """

  alias Modus.Simulation.{EventLog, Wildlife}

  @event_types [:forest_fire, :flood, :locust_swarm]

  @event_config %{
    forest_fire: %{
      emoji: "🔥🌲",
      radius: 6,
      duration: 40,
      kills_animals: [:deer, :rabbit, :bear],
      kill_count: 3,
      terrain_change: :desert,
      description: "A forest fire rages through the woodland!"
    },
    flood: %{
      emoji: "🌊🏕️",
      radius: 8,
      duration: 30,
      kills_animals: [],
      kill_count: 0,
      terrain_change: :water,
      description: "Floodwaters surge across the land!"
    },
    locust_swarm: %{
      emoji: "🦗🌾",
      radius: 10,
      duration: 25,
      kills_animals: [],
      kill_count: 0,
      terrain_change: nil,
      description: "A swarm of locusts devours the crops!"
    }
  }

  @doc "List of valid nature event types."
  def event_types, do: @event_types

  @doc "Get config for an event type."
  def event_config(type), do: Map.get(@event_config, type)

  @doc "Trigger a nature event at a given center position."
  @spec trigger(atom(), {integer(), integer()}, non_neg_integer()) :: {:ok, map()}
  def trigger(event_type, center, tick \\ 0) when event_type in @event_types do
    config = Map.fetch!(@event_config, event_type)

    event = %{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower),
      type: event_type,
      center: center,
      radius: config.radius,
      duration: config.duration,
      start_tick: tick,
      config: config
    }

    # Apply effects
    apply_nature_effects(event)

    # Log
    {cx, cy} = center
    EventLog.log(:nature_event, tick, [], %{
      type: event_type,
      center_x: cx,
      center_y: cy,
      radius: config.radius,
      description: config.description
    })

    # Broadcast
    try do
      Phoenix.PubSub.broadcast(Modus.PubSub, "world_events", {:nature_event, %{
        type: to_string(event_type),
        emoji: config.emoji,
        description: config.description,
        center_x: cx,
        center_y: cy
      }})
    catch
      _, _ -> :ok
    end

    {:ok, event}
  end

  @doc "Apply effects of a nature event (pure logic, testable)."
  @spec apply_nature_effects(map()) :: :ok
  def apply_nature_effects(event) do
    config = event.config
    {cx, cy} = event.center

    # Kill animals
    if config.kill_count > 0 and length(config.kills_animals) > 0 do
      try do
        GenServer.cast(Wildlife, {:kill_animals_in_area, config.kills_animals, config.kill_count})
      catch
        _, _ -> :ok
      end
    end

    # Terrain changes
    if config.terrain_change do
      radius = div(config.radius, 2)
      for x <- (cx - radius)..(cx + radius),
          y <- (cy - radius)..(cy + radius),
          in_radius?({x, y}, event.center, radius) do
        try do
          Modus.Simulation.World.paint_terrain({x, y}, config.terrain_change)
        catch
          _, _ -> :ok
        end
      end
    end

    # Locust swarm: destroy crops
    if event.type == :locust_swarm do
      destroy_crops(event.center, config.radius)
    end

    :ok
  end

  @doc "Destroy crops in radius (set farm resources to 0)."
  def destroy_crops({cx, cy}, radius) do
    for x <- (cx - radius)..(cx + radius),
        y <- (cy - radius)..(cy + radius),
        in_radius?({x, y}, {cx, cy}, radius) do
      try do
        case Modus.Simulation.World.get_cell({x, y}) do
          {:ok, %{terrain: :farm}} ->
            Modus.Simulation.World.set_cell({x, y}, %{resources: %{crops: 0, food: 0}})
          _ -> :ok
        end
      catch
        _, _ -> :ok
      end
    end
    :ok
  end

  defp in_radius?({x, y}, {cx, cy}, radius) do
    dx = x - cx
    dy = y - cy
    dx * dx + dy * dy <= radius * radius
  end
end
