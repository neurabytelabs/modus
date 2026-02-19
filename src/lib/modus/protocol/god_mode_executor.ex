defmodule Modus.Protocol.GodModeExecutor do
  @moduledoc """
  GodModeExecutor — Executes god-mode commands parsed from natural language.

  Bridges natural language intents (from IntentParser) to the existing
  DivineIntervention system. Supports:
  - weather_event: trigger weather/storm/rain/etc.
  - spawn_entity: create new agents in the world
  - terrain_modify: change terrain type at coordinates or globally
  - config_change: modify world rules (speed, danger, etc.)
  - rule_inject: apply rule presets or custom rule bundles

  ## Architecture
  - Reads from ETS (world state, rules) for validation
  - Writes via GenServer (DivineIntervention, RulesEngine, World)
  - Broadcasts results via PubSub for UI updates
  """

  require Logger

  alias Modus.Simulation.{DivineIntervention, World, RulesEngine}

  @type god_intent ::
          {:god_mode, :weather_event, map()}
          | {:god_mode, :spawn_entity, map()}
          | {:god_mode, :terrain_modify, map()}
          | {:god_mode, :config_change, map()}
          | {:god_mode, :rule_inject, map()}

  @type result :: {:ok, String.t()} | {:error, String.t()}

  # ── Public API ──────────────────────────────────────────────

  @doc """
  Execute a god-mode intent and return a human-readable response.

  Accepts parsed intents from IntentParser in the form:
  `{:god_mode, action_type, params_map}`
  """
  @spec execute(god_intent()) :: result()
  def execute({:god_mode, :weather_event, params}) do
    execute_weather_event(params)
  end

  def execute({:god_mode, :spawn_entity, params}) do
    execute_spawn_entity(params)
  end

  def execute({:god_mode, :terrain_modify, params}) do
    execute_terrain_modify(params)
  end

  def execute({:god_mode, :config_change, params}) do
    execute_config_change(params)
  end

  def execute({:god_mode, :rule_inject, params}) do
    execute_rule_inject(params)
  end

  def execute({:god_mode, action, _params}) do
    {:error, "Unknown god-mode action: #{inspect(action)}"}
  end

  # ── Weather Events ──────────────────────────────────────────

  @doc false
  @spec execute_weather_event(map()) :: result()
  defp execute_weather_event(%{event: event} = params) do
    severity = Map.get(params, :severity, 2)

    command =
      case event do
        e when e in [:storm, :earthquake, :flood, :drought, :fire, :meteor_shower] -> e
        :rain -> :flood
        :blizzard -> :storm
        :heatwave -> :drought
        :clear -> :golden_age
        :festival -> :festival
        _ -> :storm
      end

    case DivineIntervention.execute(command, %{severity: severity}) do
      {:ok, result} ->
        emoji = event_emoji(event)
        {:ok, "#{emoji} God mode: #{format_event_name(event)} triggered! (severity: #{severity}) #{inspect_result(result)}"}

      {:error, reason} ->
        {:error, "Failed to trigger #{event}: #{reason}"}
    end
  end

  defp execute_weather_event(_), do: {:error, "Weather event requires :event parameter"}

  # ── Spawn Entity ────────────────────────────────────────────

  @doc false
  @spec execute_spawn_entity(map()) :: result()
  defp execute_spawn_entity(%{count: count} = params) do
    count = min(max(count, 1), 20)
    name = Map.get(params, :name)
    occupation = Map.get(params, :occupation)

    results =
      for _i <- 1..count do
        divine_params = %{}
        divine_params = if name, do: Map.put(divine_params, :name, name), else: divine_params
        divine_params = if occupation, do: Map.put(divine_params, :occupation, occupation), else: divine_params
        DivineIntervention.execute(:spawn_agent, divine_params)
      end

    successes = Enum.count(results, &match?({:ok, _}, &1))
    {:ok, "👤 God mode: Spawned #{successes}/#{count} agents into the world."}
  end

  defp execute_spawn_entity(_), do: {:error, "Spawn entity requires :count parameter"}

  # ── Terrain Modify ──────────────────────────────────────────

  @doc false
  @spec execute_terrain_modify(map()) :: result()
  defp execute_terrain_modify(%{terrain: terrain} = params) do
    terrain_atom = parse_terrain(terrain)

    case params do
      %{x: x, y: y, radius: radius} ->
        modify_terrain_region({x, y}, radius, terrain_atom)

      %{x: x, y: y} ->
        World.paint_terrain({x, y}, terrain_atom)
        {:ok, "🗺️ God mode: Terrain at (#{x}, #{y}) changed to #{terrain_atom}."}

      _ ->
        # Modify a random region
        x = Enum.random(10..90)
        y = Enum.random(10..90)
        radius = Map.get(params, :radius, 5)
        modify_terrain_region({x, y}, radius, terrain_atom)
    end
  end

  defp execute_terrain_modify(_), do: {:error, "Terrain modify requires :terrain parameter"}

  defp modify_terrain_region({cx, cy}, radius, terrain_atom) do
    radius = min(max(radius, 1), 20)
    count =
      for x <- (cx - radius)..(cx + radius),
          y <- (cy - radius)..(cy + radius),
          x >= 0 and x < 100 and y >= 0 and y < 100,
          (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius,
          reduce: 0 do
        acc ->
          World.paint_terrain({x, y}, terrain_atom)
          acc + 1
      end

    {:ok, "🗺️ God mode: Changed #{count} cells around (#{cx}, #{cy}) to #{terrain_atom}."}
  end

  # ── Config Change ───────────────────────────────────────────

  @doc false
  @spec execute_config_change(map()) :: result()
  defp execute_config_change(%{changes: changes}) when is_map(changes) do
    RulesEngine.update(changes)
    keys = Map.keys(changes) |> Enum.map(&to_string/1) |> Enum.join(", ")
    {:ok, "⚙️ God mode: World config updated — #{keys}."}
  end

  defp execute_config_change(%{key: key, value: value}) do
    RulesEngine.update(%{key => value})
    {:ok, "⚙️ God mode: #{key} set to #{inspect(value)}."}
  end

  defp execute_config_change(_), do: {:error, "Config change requires :changes or :key/:value parameters"}

  # ── Rule Inject ─────────────────────────────────────────────

  @doc false
  @spec execute_rule_inject(map()) :: result()
  defp execute_rule_inject(%{preset: preset_name}) do
    case RulesEngine.apply_preset(preset_name) do
      {:ok, _rules} ->
        {:ok, "📜 God mode: Applied preset '#{preset_name}' to world rules."}

      {:error, :unknown_preset} ->
        available = RulesEngine.preset_names() |> Enum.join(", ")
        {:error, "Unknown preset '#{preset_name}'. Available: #{available}"}
    end
  end

  defp execute_rule_inject(%{rules: rules}) when is_map(rules) do
    RulesEngine.update(rules)
    {:ok, "📜 God mode: Custom rules injected."}
  end

  defp execute_rule_inject(_), do: {:error, "Rule inject requires :preset or :rules parameter"}

  # ── Helpers ─────────────────────────────────────────────────

  @spec parse_terrain(String.t() | atom()) :: atom()
  defp parse_terrain(t) when is_atom(t), do: t
  defp parse_terrain(t) when is_binary(t) do
    case String.downcase(t) do
      "desert" -> :desert
      "çöl" -> :desert
      "forest" -> :forest
      "orman" -> :forest
      "water" -> :water
      "su" -> :water
      "mountain" -> :mountain
      "dağ" -> :mountain
      "grass" -> :grass
      "çimen" -> :grass
      "swamp" -> :swamp
      "bataklık" -> :swamp
      "tundra" -> :tundra
      "sand" -> :sand
      "kum" -> :sand
      _ -> :grass
    end
  end

  defp event_emoji(:storm), do: "⛈️"
  defp event_emoji(:earthquake), do: "🌍"
  defp event_emoji(:flood), do: "🌊"
  defp event_emoji(:drought), do: "🏜️"
  defp event_emoji(:fire), do: "🔥"
  defp event_emoji(:meteor_shower), do: "☄️"
  defp event_emoji(:rain), do: "🌧️"
  defp event_emoji(:blizzard), do: "❄️"
  defp event_emoji(:heatwave), do: "🔥"
  defp event_emoji(:clear), do: "☀️"
  defp event_emoji(:festival), do: "🎉"
  defp event_emoji(_), do: "🌩️"

  defp format_event_name(event) do
    event
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp inspect_result(result) when is_map(result) do
    result
    |> Map.drop([:__struct__])
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp inspect_result(other), do: inspect(other)
end
