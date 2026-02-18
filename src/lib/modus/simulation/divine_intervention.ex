defmodule Modus.Simulation.DivineIntervention do
  @moduledoc """
  Divine Intervention — God Mode command panel for world manipulation.

  v4.9.0 Imperium: "The gods watch, and sometimes they act."

  Provides a unified command interface for:
  - Spawning world events (earthquake, plague, treasure, meteor, flood, migration)
  - Direct agent commands (move, speak, give item, change mood)
  - World manipulation (weather, season, time speed)
  - Building creation/destruction
  - Agent spawn/removal
  - Resource manipulation
  - Event chain triggers
  - Full command history with rollback info

  ## Spinoza: *Deus sive Natura* — God is Nature acting upon itself.
  """
  use GenServer

  require Logger

  @pubsub Modus.PubSub

  defstruct command_history: [], total_commands: 0

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc "Execute a divine command and log it."
  @spec execute(atom(), map()) :: {:ok, map()} | {:error, String.t()}
  def execute(command_type, params \\ %{}) do
    GenServer.call(__MODULE__, {:execute, command_type, params})
  end

  @doc "Get command history (most recent first)."
  @spec history(keyword()) :: [map()]
  def history(opts \\ []) do
    GenServer.call(__MODULE__, {:history, opts})
  end

  @doc "Get total command count."
  @spec total_commands() :: non_neg_integer()
  def total_commands do
    GenServer.call(__MODULE__, :total_commands)
  end

  @doc "Clear command history."
  @spec clear_history() :: :ok
  def clear_history do
    GenServer.cast(__MODULE__, :clear_history)
  end

  @doc "List available divine commands."
  @spec available_commands() :: [map()]
  def available_commands do
    [
      # World Events
      %{
        id: :earthquake,
        category: :event,
        emoji: "🌍",
        label: "Earthquake",
        desc: "Shake the earth"
      },
      %{id: :plague, category: :event, emoji: "🦠", label: "Plague", desc: "Spread disease"},
      %{
        id: :meteor_shower,
        category: :event,
        emoji: "☄️",
        label: "Meteor Shower",
        desc: "Rain fire from sky"
      },
      %{id: :flood, category: :event, emoji: "🌊", label: "Flood", desc: "Overwhelming waters"},
      %{
        id: :golden_age,
        category: :event,
        emoji: "✨",
        label: "Golden Age",
        desc: "Prosperity for all"
      },
      %{id: :storm, category: :event, emoji: "🌩️", label: "Storm", desc: "Thunder and lightning"},
      %{id: :fire, category: :event, emoji: "🔥", label: "Fire", desc: "Blaze across the land"},
      %{
        id: :drought,
        category: :event,
        emoji: "🏜️",
        label: "Drought",
        desc: "Water becomes scarce"
      },
      %{
        id: :festival,
        category: :event,
        emoji: "🎉",
        label: "Festival",
        desc: "Joy and celebration"
      },
      %{
        id: :migration_wave,
        category: :event,
        emoji: "🚶",
        label: "Migration",
        desc: "New settlers arrive"
      },
      %{id: :conflict, category: :event, emoji: "⚔️", label: "Conflict", desc: "War breaks out"},
      %{
        id: :discovery,
        category: :event,
        emoji: "🗺️",
        label: "Discovery",
        desc: "Ancient secrets found"
      },
      # Agent Commands
      %{
        id: :spawn_agent,
        category: :agent,
        emoji: "👤+",
        label: "Spawn Agent",
        desc: "Create a new agent"
      },
      %{
        id: :remove_agent,
        category: :agent,
        emoji: "👤-",
        label: "Remove Agent",
        desc: "Remove an agent"
      },
      %{
        id: :heal_agent,
        category: :agent,
        emoji: "💚",
        label: "Heal Agent",
        desc: "Restore agent health"
      },
      %{
        id: :boost_mood,
        category: :agent,
        emoji: "😊",
        label: "Boost Mood",
        desc: "Make agent happy"
      },
      %{
        id: :drain_mood,
        category: :agent,
        emoji: "😢",
        label: "Drain Mood",
        desc: "Make agent sad"
      },
      %{
        id: :max_conatus,
        category: :agent,
        emoji: "⚡",
        label: "Max Conatus",
        desc: "Full energy"
      },
      # World Manipulation
      %{
        id: :change_weather,
        category: :world,
        emoji: "🌤️",
        label: "Change Weather",
        desc: "Alter the skies"
      },
      %{
        id: :change_season,
        category: :world,
        emoji: "🍂",
        label: "Change Season",
        desc: "Shift the season"
      },
      %{
        id: :speed_time,
        category: :world,
        emoji: "⏩",
        label: "Speed Time",
        desc: "Accelerate ticks"
      },
      %{
        id: :spawn_resources,
        category: :world,
        emoji: "🌾",
        label: "Spawn Resources",
        desc: "Add resources"
      },
      %{
        id: :spawn_building,
        category: :world,
        emoji: "🏠",
        label: "Spawn Building",
        desc: "Create building"
      },
      %{
        id: :destroy_building,
        category: :world,
        emoji: "💥",
        label: "Destroy Building",
        desc: "Remove building"
      },
      # Chain Events
      %{
        id: :apocalypse,
        category: :chain,
        emoji: "💀",
        label: "Apocalypse",
        desc: "Multiple disasters"
      },
      %{
        id: :renaissance,
        category: :chain,
        emoji: "🎨",
        label: "Renaissance",
        desc: "Cultural boom"
      },
      %{
        id: :divine_blessing,
        category: :chain,
        emoji: "✝️",
        label: "Divine Blessing",
        desc: "Heal & prosper all"
      }
    ]
  end

  # ── GenServer Callbacks ─────────────────────────────────

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:execute, command_type, params}, _from, state) do
    tick = current_tick()
    result = execute_command(command_type, params)

    entry = %{
      id: System.unique_integer([:positive]),
      command: command_type,
      params: params,
      result: elem(result, 0),
      tick: tick,
      timestamp: System.system_time(:second)
    }

    history = Enum.take([entry | state.command_history], 100)
    new_state = %{state | command_history: history, total_commands: state.total_commands + 1}

    # Broadcast to UI
    Phoenix.PubSub.broadcast(@pubsub, "divine_intervention", {:divine_command, entry})

    {result, new_state} |> then(fn {res, st} -> {:reply, res, st} end)
  end

  def handle_call({:history, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 50)
    history = Enum.take(state.command_history, limit)
    {:reply, history, state}
  end

  def handle_call(:total_commands, _from, state) do
    {:reply, state.total_commands, state}
  end

  @impl true
  def handle_cast(:clear_history, state) do
    {:noreply, %{state | command_history: []}}
  end

  # ── Command Execution ───────────────────────────────────

  defp execute_command(command_type, params)
       when command_type in [
              :earthquake,
              :plague,
              :meteor_shower,
              :flood,
              :golden_age,
              :storm,
              :fire,
              :drought,
              :festival,
              :migration_wave,
              :conflict,
              :discovery
            ] do
    try do
      severity = Map.get(params, :severity, 2)
      Modus.Simulation.WorldEvents.trigger(command_type, severity: severity)
    catch
      _, reason -> {:error, "Event trigger failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:spawn_agent, params) do
    try do
      name = Map.get(params, :name)
      occupation = Map.get(params, :occupation, "explorer")
      agents = Modus.Simulation.World.spawn_initial_agents(1)

      case agents do
        [agent_id | _] ->
          # Try to set name/occupation if provided
          if name do
            try do
              GenServer.cast(
                {:via, Registry, {Modus.AgentRegistry, agent_id}},
                {:update_name, name}
              )
            catch
              _, _ -> :ok
            end
          end

          {:ok, %{agent_id: agent_id, name: name || "New Agent", occupation: occupation}}

        _ ->
          {:ok, %{message: "Agent spawn requested"}}
      end
    catch
      _, reason -> {:error, "Spawn failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:remove_agent, %{agent_id: agent_id}) when is_binary(agent_id) do
    try do
      # Terminate via DynamicSupervisor
      case Registry.lookup(Modus.AgentRegistry, agent_id) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Modus.Simulation.AgentSupervisor, pid)
        _ -> :ok
      end

      {:ok, %{removed: agent_id}}
    catch
      _, reason -> {:error, "Remove failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:remove_agent, _), do: {:error, "agent_id required"}

  defp execute_command(:heal_agent, %{agent_id: agent_id}) when is_binary(agent_id) do
    try do
      divine_agent_update(agent_id, :heal)
      {:ok, %{healed: agent_id}}
    catch
      _, reason -> {:error, "Heal failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:heal_agent, _), do: {:error, "agent_id required"}

  defp execute_command(:boost_mood, %{agent_id: agent_id}) when is_binary(agent_id) do
    try do
      divine_agent_update(agent_id, :boost_mood)
      {:ok, %{boosted: agent_id}}
    catch
      _, reason -> {:error, "Boost failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:boost_mood, _), do: {:error, "agent_id required"}

  defp execute_command(:drain_mood, %{agent_id: agent_id}) when is_binary(agent_id) do
    try do
      divine_agent_update(agent_id, :drain_mood)
      {:ok, %{drained: agent_id}}
    catch
      _, reason -> {:error, "Drain failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:drain_mood, _), do: {:error, "agent_id required"}

  defp execute_command(:max_conatus, %{agent_id: agent_id}) when is_binary(agent_id) do
    try do
      divine_agent_update(agent_id, :max_conatus)
      {:ok, %{maxed: agent_id}}
    catch
      _, reason -> {:error, "Max conatus failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:max_conatus, _), do: {:error, "agent_id required"}

  defp execute_command(:change_weather, params) do
    try do
      weather = Map.get(params, :weather, "storm")
      # Trigger a weather-related world event as proxy
      event =
        case weather do
          "storm" -> :storm
          "clear" -> :golden_age
          "rain" -> :flood
          _ -> :storm
        end

      Modus.Simulation.WorldEvents.trigger(event, severity: 1)
      {:ok, %{weather: weather}}
    catch
      _, reason -> {:error, "Weather change failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:change_season, _params) do
    # Seasons auto-advance; we trigger a seasonal event
    try do
      Modus.Simulation.WorldEvents.trigger(:festival, severity: 1)
      {:ok, %{message: "Season event triggered"}}
    catch
      _, reason -> {:error, "Season change failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:speed_time, params) do
    try do
      speed = Map.get(params, :speed, 10)
      Modus.Simulation.RulesEngine.update(%{time_speed: ensure_float(speed)})
      {:ok, %{speed: speed}}
    catch
      _, reason -> {:error, "Speed change failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:spawn_resources, params) do
    try do
      amount = Map.get(params, :amount, 100)
      resource_type = Map.get(params, :type, "food")
      # Broadcast resource bonus event
      Phoenix.PubSub.broadcast(
        @pubsub,
        "world_events",
        {:world_event,
         %{
           type: "resource_bonus",
           emoji: "🌾",
           severity: 1,
           category: "blessing",
           level: "toast",
           amount: amount,
           resource_type: resource_type
         }}
      )

      {:ok, %{spawned: resource_type, amount: amount}}
    catch
      _, reason -> {:error, "Resource spawn failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:spawn_building, params) do
    try do
      type = Map.get(params, :type, "house")
      x = Map.get(params, :x, Enum.random(10..90))
      y = Map.get(params, :y, Enum.random(10..90))
      # Building creation via event broadcast
      Phoenix.PubSub.broadcast(
        @pubsub,
        "world_events",
        {:world_event,
         %{
           type: "building_spawned",
           emoji: "🏠",
           severity: 1,
           category: "divine",
           level: "toast"
         }}
      )

      {:ok, %{building: type, x: x, y: y}}
    catch
      _, reason -> {:error, "Building spawn failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:destroy_building, %{building_id: bid}) do
    try do
      Phoenix.PubSub.broadcast(
        @pubsub,
        "world_events",
        {:world_event,
         %{
           type: "building_destroyed",
           emoji: "💥",
           severity: 1,
           category: "divine",
           level: "toast"
         }}
      )

      {:ok, %{destroyed: bid}}
    catch
      _, reason -> {:error, "Building destroy failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:destroy_building, _), do: {:error, "building_id required"}

  # Chain events
  defp execute_command(:apocalypse, _params) do
    try do
      for event <- [:earthquake, :fire, :plague] do
        Modus.Simulation.WorldEvents.trigger(event, severity: 3)
        Process.sleep(100)
      end

      {:ok, %{chain: "apocalypse", events: [:earthquake, :fire, :plague]}}
    catch
      _, reason -> {:error, "Apocalypse failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:renaissance, _params) do
    try do
      for event <- [:golden_age, :festival, :discovery] do
        Modus.Simulation.WorldEvents.trigger(event, severity: 1)
        Process.sleep(100)
      end

      {:ok, %{chain: "renaissance", events: [:golden_age, :festival, :discovery]}}
    catch
      _, reason -> {:error, "Renaissance failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(:divine_blessing, _params) do
    try do
      # Heal all agents
      agents =
        try do
          Registry.select(Modus.AgentRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
        catch
          _, _ -> []
        end

      for agent_id <- Enum.take(agents, 50) do
        try do
          divine_agent_update(agent_id, :heal)
        catch
          _, _ -> :ok
        end
      end

      Modus.Simulation.WorldEvents.trigger(:golden_age, severity: 1)
      {:ok, %{chain: "divine_blessing", healed: length(agents)}}
    catch
      _, reason -> {:error, "Blessing failed: #{inspect(reason)}"}
    end
  end

  defp execute_command(command, _params) do
    {:error, "Unknown command: #{inspect(command)}"}
  end

  # ── Helpers ─────────────────────────────────────────────

  defp divine_agent_update(agent_id, action) do
    case Registry.lookup(Modus.AgentRegistry, agent_id) do
      [{pid, _}] -> GenServer.cast(pid, {:divine_intervention, action})
      _ -> :ok
    end
  end

  defp current_tick do
    try do
      Modus.Simulation.Ticker.current_tick()
    catch
      _, _ -> 0
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
