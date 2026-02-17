defmodule Modus.Persistence.WorldExport do
  @moduledoc """
  WorldExport — Export/Import/Share world state as portable JSON.

  v2.2.1 Speculum — Export & Share
  - Export: full JSON (terrain, agents, buildings, wildlife, rules, history)
  - Import: validate + create world from JSON
  - Share: base64-encoded URL fragment
  """
  require Logger

  alias Modus.Simulation.{World, Agent, AgentSupervisor, Ticker, Building, RulesEngine}

  @export_version "2.2.1"

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @doc "Export current world state as a portable JSON-encodable map."
  def export do
    try do
      world_state = World.get_state()
      tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0
      {gw, gh} = world_state.grid_size

      %{
        modus_version: @export_version,
        exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        world: %{
          name: world_state.name,
          config: %{
            template: to_string(world_state.config.template),
            danger_level: to_string(world_state.config.danger_level),
            resource_abundance: to_string(world_state.config.resource_abundance),
            seed: world_state.config.seed,
            grid_size: %{x: gw, y: gh}
          },
          tick: tick
        },
        terrain: export_terrain(world_state),
        agents: export_agents(),
        buildings: export_buildings(),
        rules: export_rules(),
        history: export_history(world_state.name),
        timeline: export_timeline()
      }
    catch
      kind, reason ->
        Logger.error("World export failed: #{inspect({kind, reason})}")
        {:error, "Export failed: #{inspect(reason)}"}
    end
  end

  @doc "Export world as JSON string."
  def export_json do
    case export() do
      {:error, _} = err -> err
      data -> {:ok, Jason.encode!(data, pretty: true)}
    end
  end

  @doc "Export world as base64-encoded string for URL sharing."
  def export_base64 do
    case export() do
      {:error, _} = err -> err
      data ->
        json = Jason.encode!(data)
        compressed = :zlib.compress(json)
        {:ok, Base.url_encode64(compressed)}
    end
  end

  @doc "Import world from a JSON map (already decoded). Validates and creates world."
  def import_world(data) when is_map(data) do
    with :ok <- validate_import(data),
         :ok <- do_import(data) do
      {:ok, %{
        name: get_in(data, ["world", "name"]) || "Imported World",
        agents: length(data["agents"] || []),
        buildings: length(data["buildings"] || []),
        tick: get_in(data, ["world", "tick"]) || 0
      }}
    end
  end

  @doc "Import world from a JSON string."
  def import_json(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> import_world(data)
      {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end

  @doc "Import world from base64-encoded string (URL share)."
  def import_base64(base64_string) when is_binary(base64_string) do
    try do
      compressed = Base.url_decode64!(base64_string)
      json = :zlib.uncompress(compressed)
      import_json(json)
    rescue
      e -> {:error, "Invalid share data: #{inspect(e)}"}
    end
  end

  # ── Validation ─────────────────────────────────────────────

  defp validate_import(data) do
    cond do
      !is_map(data) ->
        {:error, "Data must be a JSON object"}
      !is_map(data["world"]) ->
        {:error, "Missing 'world' section"}
      !is_map(get_in(data, ["world", "config"])) ->
        {:error, "Missing 'world.config' section"}
      !is_list(data["agents"]) && data["agents"] != nil ->
        {:error, "'agents' must be an array"}
      true ->
        :ok
    end
  end

  # ── Import Logic ───────────────────────────────────────────

  defp do_import(data) do
    try do
      world_data = data["world"]
      config = world_data["config"] || %{}

      # Stop current simulation
      if Process.whereis(Ticker), do: Ticker.pause()
      AgentSupervisor.terminate_all()
      if Process.whereis(World), do: GenServer.stop(World)

      # Create new world
      template = safe_atom(config["template"], :village)
      danger = safe_atom(config["danger_level"], :normal)
      abundance = safe_atom(config["resource_abundance"], :medium)
      grid_x = get_in(config, ["grid_size", "x"]) || 100
      grid_y = get_in(config, ["grid_size", "y"]) || 100

      world = World.new(
        world_data["name"] || "Imported World",
        template: template,
        danger_level: danger,
        resource_abundance: abundance,
        seed: config["seed"] || :rand.uniform(1_000_000),
        grid_size: {grid_x, grid_y}
      )

      {:ok, _pid} = World.start_link(world)

      # Apply terrain overrides if provided
      apply_terrain(data["terrain"])

      # Restore agents
      agents_data = data["agents"] || []
      restored = restore_agents(agents_data)

      # Restore buildings
      restore_buildings(data["buildings"] || [])

      # Restore rules
      restore_rules(data["rules"])

      Logger.info("World imported: #{world_data["name"]} (#{length(restored)} agents)")
      :ok
    catch
      kind, reason ->
        Logger.error("World import failed: #{inspect({kind, reason})}")
        {:error, "Import failed: #{inspect(reason)}"}
    end
  end

  # ── Export Helpers ──────────────────────────────────────────

  defp export_terrain(world_state) do
    {max_x, max_y} = world_state.grid_size

    # Only export non-default terrain to keep exports small
    for x <- 0..(max_x - 1), y <- 0..(max_y - 1), reduce: [] do
      acc ->
        case :ets.lookup(world_state.grid_table, {x, y}) do
          [{{^x, ^y}, %{terrain: terrain} = cell}] ->
            nodes = Map.get(cell, :resource_nodes, [])
            entry = %{x: x, y: y, t: to_string(terrain)}
            entry = if nodes != [], do: Map.put(entry, :r, Enum.map(nodes, &to_string/1)), else: entry
            [entry | acc]
          _ -> acc
        end
    end
  end

  defp export_agents do
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.reduce([], fn {_id, pid}, acc ->
      try do
        state = GenServer.call(pid, :get_state, 2_000)
        agent_map = %{
          id: state.id,
          name: state.name,
          position: %{x: elem(state.position, 0), y: elem(state.position, 1)},
          occupation: to_string(state.occupation),
          personality: %{
            openness: ensure_float(state.personality.openness),
            conscientiousness: ensure_float(state.personality.conscientiousness),
            extraversion: ensure_float(state.personality.extraversion),
            agreeableness: ensure_float(state.personality.agreeableness),
            neuroticism: ensure_float(state.personality.neuroticism)
          },
          needs: %{
            hunger: ensure_float(state.needs.hunger),
            social: ensure_float(state.needs.social),
            rest: ensure_float(state.needs.rest),
            shelter: ensure_float(state.needs.shelter)
          },
          relationships: serialize_relationships(state.relationships),
          current_action: to_string(state.current_action),
          conatus_score: ensure_float(state.conatus_score),
          conatus_energy: ensure_float(state.conatus_energy),
          affect_state: to_string(state.affect_state),
          alive: state.alive?,
          age: state.age,
          inventory: state.inventory || %{}
        }
        [agent_map | acc]
      catch
        :exit, _ -> acc
      end
    end)
  end

  defp export_buildings do
    try do
      Building.serialize_all()
    catch
      _, _ -> []
    end
  end

  defp export_rules do
    try do
      RulesEngine.serialize()
    catch
      _, _ -> %{}
    end
  end

  defp export_history(world_name) do
    try do
      Modus.Simulation.WorldHistory.export_chronicle(world_name)
    catch
      _, _ -> ""
    end
  end

  defp export_timeline do
    try do
      Modus.Simulation.StoryEngine.get_timeline(limit: 100)
      |> Enum.map(fn entry ->
        %{
          tick: entry.tick,
          type: to_string(entry.type),
          text: entry.text
        }
      end)
    catch
      _, _ -> []
    end
  end

  # ── Import Helpers ─────────────────────────────────────────

  defp apply_terrain(nil), do: :ok
  defp apply_terrain(terrain) when is_list(terrain) do
    for tile <- terrain do
      x = tile["x"]
      y = tile["y"]
      t = tile["t"]
      if x && y && t do
        try do
          World.paint_terrain({x, y}, String.to_existing_atom(t))
        catch
          _, _ -> :ok
        end
      end

      # Restore resource nodes
      for node <- (tile["r"] || []) do
        try do
          World.place_resource_node({x, y}, String.to_existing_atom(node))
        catch
          _, _ -> :ok
        end
      end
    end
    :ok
  end
  defp apply_terrain(_), do: :ok

  defp restore_agents(agents_data) do
    Enum.reduce(agents_data, [], fn data, acc ->
      try do
        agent = %Agent{
          id: data["id"] || (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)),
          name: data["name"] || "Unknown",
          position: {data["position"]["x"] || 25, data["position"]["y"] || 25},
          occupation: safe_atom(data["occupation"], :explorer),
          personality: %{
            openness: get_in(data, ["personality", "openness"]) || :rand.uniform(),
            conscientiousness: get_in(data, ["personality", "conscientiousness"]) || :rand.uniform(),
            extraversion: get_in(data, ["personality", "extraversion"]) || :rand.uniform(),
            agreeableness: get_in(data, ["personality", "agreeableness"]) || :rand.uniform(),
            neuroticism: get_in(data, ["personality", "neuroticism"]) || :rand.uniform()
          },
          needs: %{
            hunger: get_in(data, ["needs", "hunger"]) || 50.0,
            social: get_in(data, ["needs", "social"]) || 50.0,
            rest: get_in(data, ["needs", "rest"]) || 80.0,
            shelter: get_in(data, ["needs", "shelter"]) || 70.0
          },
          relationships: deserialize_relationships(data["relationships"]),
          memory: [],
          current_action: safe_atom(data["current_action"], :idle),
          conatus_score: data["conatus_score"] || 5.0,
          alive?: data["alive"] != false,
          age: data["age"] || 0,
          inventory: data["inventory"] || %{}
        }

        case AgentSupervisor.spawn_agent(agent) do
          {:ok, _pid} -> [agent | acc]
          _ -> acc
        end
      catch
        _, _ -> acc
      end
    end)
  end

  defp restore_buildings(buildings) when is_list(buildings) do
    tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0
    for b <- buildings do
      try do
        type = safe_atom(b["type"] || b[:type], :hut)
        x = b["x"] || b[:x] || 0
        y = b["y"] || b[:y] || 0
        Building.place(type, {x, y}, nil, tick)
      catch
        _, _ -> :ok
      end
    end
  end
  defp restore_buildings(_), do: :ok

  defp restore_rules(nil), do: :ok
  defp restore_rules(rules) when is_map(rules) do
    changes = %{}
    changes = if rules["time_speed"], do: Map.put(changes, :time_speed, ensure_float(rules["time_speed"])), else: changes
    changes = if rules["resource_abundance"], do: Map.put(changes, :resource_abundance, safe_atom(rules["resource_abundance"], :medium)), else: changes
    changes = if rules["danger_level"], do: Map.put(changes, :danger_level, safe_atom(rules["danger_level"], :normal)), else: changes
    changes = if rules["social_tendency"], do: Map.put(changes, :social_tendency, ensure_float(rules["social_tendency"])), else: changes
    changes = if rules["birth_rate"], do: Map.put(changes, :birth_rate, ensure_float(rules["birth_rate"])), else: changes
    changes = if rules["building_speed"], do: Map.put(changes, :building_speed, ensure_float(rules["building_speed"])), else: changes
    if map_size(changes) > 0, do: RulesEngine.update(changes)
    :ok
  end
  defp restore_rules(_), do: :ok

  # ── Shared Helpers ─────────────────────────────────────────

  defp serialize_relationships(rels) when is_map(rels) do
    Enum.map(rels, fn {id, {type, strength}} ->
      %{agent_id: id, type: to_string(type), strength: ensure_float(strength)}
    end)
  end
  defp serialize_relationships(_), do: []

  defp deserialize_relationships(nil), do: %{}
  defp deserialize_relationships(rels) when is_list(rels) do
    Enum.reduce(rels, %{}, fn rel, acc ->
      Map.put(acc, rel["agent_id"], {safe_atom(rel["type"], :acquaintance), rel["strength"] || 0.0})
    end)
  end
  defp deserialize_relationships(_), do: %{}

  @valid_atoms ~w(village desert island arctic forest grassland normal easy hard peaceful medium scarce abundant
    farmer merchant explorer healer builder guard hunter fisher artist scholar
    idle exploring gathering building socializing resting trading
    deer rabbit wolf
    grass water mountain sand farm flowers
    food_source water_well wood_pile stone_quarry
    acquaintance friend close_friend rival enemy
    calm joy sadness anger fear surprise
    hut house market well watchtower)a

  defp safe_atom(nil, default), do: default
  defp safe_atom(val, default) when is_binary(val) do
    atom = String.to_atom(val)
    if atom in @valid_atoms, do: atom, else: default
  rescue
    _ -> default
  end
  defp safe_atom(val, _default) when is_atom(val), do: val
  defp safe_atom(_, default), do: default
end
