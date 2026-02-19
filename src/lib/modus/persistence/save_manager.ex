defmodule Modus.Persistence.SaveManager do
  @moduledoc """
  SaveManager — Manages save slots, auto-save, gzip compression, and crash recovery.

  v3.7.0 Persistentia features:
  - 5 named save slots per world
  - Auto-save every N ticks (configurable, default 500)
  - Gzip compression for save files
  - Crash recovery from last auto-save
  - World seed for reproducible worlds
  - JSON import/export (portable)
  """
  use GenServer
  require Logger

  @max_slots 5
  @default_autosave_interval 500
  @save_dir "priv/saves"
  @autosave_file "autosave.json.gz"

  defstruct autosave_interval: @default_autosave_interval,
            last_autosave_tick: 0,
            last_autosave_at: nil,
            enabled: true,
            slot_cache: nil

  # ── Public API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Save to a named slot (1-5). Returns {:ok, info} or {:error, reason}."
  def save_slot(slot, name \\ nil) when slot in 1..@max_slots do
    GenServer.call(__MODULE__, {:save_slot, slot, name}, 30_000)
  end

  @doc "Load from a named slot (1-5)."
  def load_slot(slot) when slot in 1..@max_slots do
    GenServer.call(__MODULE__, {:load_slot, slot}, 30_000)
  end

  @doc "List all save slots with metadata."
  def list_slots do
    GenServer.call(__MODULE__, :list_slots)
  end

  @doc "Delete a save slot."
  def delete_slot(slot) when slot in 1..@max_slots do
    GenServer.call(__MODULE__, {:delete_slot, slot})
  end

  @doc "Export current world as portable JSON string."
  def export_json do
    state = collect_full_state()
    json = Jason.encode!(state, pretty: true)
    {:ok, json}
  catch
    kind, reason ->
      Logger.error("Export failed: #{inspect({kind, reason})}")
      {:error, "Export failed"}
  end

  @doc "Import world from JSON string."
  def import_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} -> restore_full_state(data)
      {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
    end
  end

  @doc "Trigger auto-save (called from Ticker)."
  def autosave(tick) do
    GenServer.cast(__MODULE__, {:autosave, tick})
  end

  @doc "Get auto-save status for UI."
  def autosave_status do
    GenServer.call(__MODULE__, :autosave_status)
  catch
    :exit, _ ->
      %{enabled: false, last_tick: 0, last_at: nil, interval: @default_autosave_interval}
  end

  @doc "Set auto-save interval."
  def set_autosave_interval(ticks) when is_integer(ticks) and ticks > 0 do
    GenServer.call(__MODULE__, {:set_interval, ticks})
  end

  @doc "Try crash recovery from last auto-save."
  def recover do
    path = autosave_path()

    if File.exists?(path) do
      case read_gzip(path) do
        {:ok, data} ->
          Logger.info("Crash recovery: found auto-save, restoring...")
          restore_full_state(data)

        {:error, reason} ->
          Logger.warning("Crash recovery failed: #{reason}")
          {:error, reason}
      end
    else
      {:error, :no_autosave}
    end
  end

  # ── GenServer Callbacks ─────────────────────────────────────

  @impl true
  def init(opts) do
    ensure_save_dir()
    interval = Keyword.get(opts, :autosave_interval, @default_autosave_interval)
    {:ok, %__MODULE__{autosave_interval: interval, slot_cache: nil}}
  end

  @impl true
  def handle_call({:save_slot, slot, name}, _from, state) do
    result = do_save_slot(slot, name)
    {:reply, result, %{state | slot_cache: nil}}
  end

  def handle_call({:load_slot, slot}, _from, state) do
    result = do_load_slot(slot)
    {:reply, result, state}
  end

  def handle_call(:list_slots, _from, %{slot_cache: cached} = state) when cached != nil do
    {:reply, cached, state}
  end

  def handle_call(:list_slots, _from, state) do
    slots = build_slot_list()
    {:reply, slots, %{state | slot_cache: slots}}
  end

  def handle_call({:delete_slot, slot}, _from, state) do
    path = slot_path(slot)
    if File.exists?(path), do: File.rm(path)
    {:reply, :ok, %{state | slot_cache: nil}}
  end

  def handle_call(:autosave_status, _from, state) do
    {:reply,
     %{
       enabled: state.enabled,
       last_tick: state.last_autosave_tick,
       last_at: state.last_autosave_at,
       interval: state.autosave_interval
     }, state}
  end

  def handle_call({:set_interval, ticks}, _from, state) do
    {:reply, :ok, %{state | autosave_interval: ticks}}
  end

  @impl true
  def handle_cast({:autosave, tick}, state) do
    if state.enabled and tick - state.last_autosave_tick >= state.autosave_interval do
      Task.start(fn -> do_autosave(tick) end)
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      {:noreply, %{state | last_autosave_tick: tick, last_autosave_at: now}}
    else
      {:noreply, state}
    end
  end

  # ── Private ─────────────────────────────────────────────────

  defp build_slot_list do
    Enum.map(1..@max_slots, fn slot ->
      path = slot_path(slot)

      if File.exists?(path) do
        case read_gzip(path) do
          {:ok, data} ->
            %{
              slot: slot,
              name: data["meta"]["name"] || "Slot #{slot}",
              world_name: get_in(data, ["world", "name"]) || "Unknown",
              tick: get_in(data, ["world", "tick"]) || 0,
              population: length(data["agents"] || []),
              day_count: div(get_in(data, ["world", "tick"]) || 0, 100) + 1,
              saved_at: data["meta"]["saved_at"],
              seed: get_in(data, ["world", "config", "seed"]),
              size_bytes: File.stat!(path).size
            }

          _ ->
            %{slot: slot, empty: true}
        end
      else
        %{slot: slot, empty: true}
      end
    end)
  end

  defp do_save_slot(slot, name) do
    try do
      state = collect_full_state()

      state =
        put_in(state, [:meta], %{
          name: name || "Slot #{slot}",
          saved_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          slot: slot
        })

      write_gzip(slot_path(slot), state)

      info = %{
        slot: slot,
        name: name || "Slot #{slot}",
        tick: get_in(state, [:world, :tick]) || 0,
        population: length(state[:agents] || [])
      }

      Logger.info("Saved to slot #{slot}: #{info.name}")
      {:ok, info}
    catch
      kind, reason ->
        Logger.error("Save slot #{slot} failed: #{inspect({kind, reason})}")
        {:error, "Save failed: #{inspect(reason)}"}
    end
  end

  defp do_load_slot(slot) do
    path = slot_path(slot)

    if File.exists?(path) do
      case read_gzip(path) do
        {:ok, data} -> restore_full_state(data)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :slot_empty}
    end
  end

  defp do_autosave(tick) do
    try do
      state = collect_full_state()

      state =
        Map.put(state, :meta, %{
          name: "Auto-save",
          saved_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          auto: true,
          tick: tick
        })

      write_gzip(autosave_path(), state)
      Logger.debug("Auto-saved at tick #{tick}")
    catch
      kind, reason ->
        Logger.warning("Auto-save failed at tick #{tick}: #{inspect({kind, reason})}")
    end
  end

  @doc false
  def collect_full_state do
    world_state =
      try do
        Modus.Simulation.World.get_state()
      catch
        _, _ -> %{name: "Unknown", config: %{}, grid_size: {50, 50}}
      end

    tick =
      try do
        Modus.Simulation.Ticker.current_tick()
      catch
        _, _ -> 0
      end

    {gx, gy} =
      case world_state do
        %{grid_size: {x, y}} -> {x, y}
        _ -> {50, 50}
      end

    config =
      try do
        %{
          template: to_string(world_state.config.template),
          danger_level: to_string(world_state.config.danger_level),
          resource_abundance: to_string(world_state.config.resource_abundance),
          seed: world_state.config[:seed] || world_state.config.seed,
          grid_size: %{x: gx, y: gy}
        }
      catch
        _, _ ->
          %{
            template: "village",
            danger_level: "normal",
            resource_abundance: "medium",
            seed: 42,
            grid_size: %{x: gx, y: gy}
          }
      end

    agents = collect_agents()

    buildings =
      try do
        Modus.Simulation.Building.serialize_all()
      catch
        _, _ -> []
      end

    wildlife =
      try do
        collect_wildlife()
      catch
        _, _ -> []
      end

    economy =
      try do
        collect_economy()
      catch
        _, _ -> %{}
      end

    history =
      try do
        Modus.Simulation.WorldHistory.export_chronicle(world_state.name)
      catch
        _, _ -> ""
      end

    groups =
      try do
        collect_groups()
      catch
        _, _ -> []
      end

    %{
      modus_version: "3.7.0",
      world: %{
        name: world_state.name,
        config: config,
        tick: tick
      },
      agents: agents,
      buildings: buildings,
      wildlife: wildlife,
      economy: economy,
      history: history,
      groups: groups
    }
  end

  defp collect_agents do
    # v7.3: Parallel agent state collection with Task.async_stream
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Task.async_stream(
      fn {_id, pid} ->
        try do
          GenServer.call(pid, :get_state, 2_000)
        catch
          :exit, _ -> nil
        end
      end,
      max_concurrency: 10,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce([], fn
      {:ok, nil}, acc ->
        acc

      {:ok, state}, acc ->
        agent = %{
          id: state.id,
          name: state.name,
          position: %{x: elem(state.position, 0), y: elem(state.position, 1)},
          occupation: to_string(state.occupation),
          personality:
            if(is_struct(state.personality),
              do: Map.from_struct(state.personality),
              else: state.personality
            )
            |> Map.new(fn {k, v} -> {k, ensure_float(v)} end),
          needs: %{
            hunger: ensure_float(state.needs.hunger),
            social: ensure_float(state.needs.social),
            rest: ensure_float(state.needs.rest),
            shelter: ensure_float(state.needs.shelter)
          },
          relationships: serialize_relationships(state.relationships),
          current_action: to_string(state.current_action),
          conatus_score: ensure_float(state.conatus_score),
          alive: state.alive?,
          age: state.age,
          inventory: state.inventory || %{}
        }

        [agent | acc]

      {:exit, _reason}, acc ->
        acc

      _, acc ->
        acc
    end)
  end

  defp collect_wildlife do
    try do
      Modus.Simulation.Wildlife.get_animals()
      |> Enum.map(fn w ->
        %{
          id: w.id,
          species: to_string(w.species),
          position: %{x: elem(w.position, 0), y: elem(w.position, 1)},
          health: ensure_float(w.health),
          age: w.age
        }
      end)
    catch
      _, _ -> []
    end
  end

  defp collect_economy do
    try do
      %{
        trades: Modus.Simulation.TradeSystem.trade_history(100),
        market_prices: Modus.Simulation.Economy.stats()
      }
    catch
      _, _ -> %{}
    end
  end

  defp collect_groups do
    try do
      Modus.Mind.SocialEngine.get_groups()
      |> Enum.map(fn g ->
        %{
          id: g.id,
          name: g.name,
          leader: g.leader,
          members: g.members,
          type: to_string(g.type)
        }
      end)
    catch
      _, _ -> []
    end
  end

  defp restore_full_state(data) when is_map(data) do
    try do
      # Use WorldExport for the heavy lifting of world restoration
      case Modus.Persistence.WorldExport.import_world(data) do
        {:ok, info} ->
          Logger.info("State restored: #{info.name} (#{info.agents} agents)")
          {:ok, info}

        {:error, _} = err ->
          err
      end
    catch
      kind, reason ->
        Logger.error("State restore failed: #{inspect({kind, reason})}")
        {:error, "Restore failed"}
    end
  end

  # ── Gzip I/O ────────────────────────────────────────────────

  defp write_gzip(path, data) do
    json = Jason.encode!(data)
    compressed = :zlib.gzip(json)
    File.write!(path, compressed)
  end

  defp read_gzip(path) do
    case File.read(path) do
      {:ok, compressed} ->
        json = :zlib.gunzip(compressed)
        Jason.decode(json)

      {:error, reason} ->
        {:error, "Read failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Decompress failed: #{inspect(e)}"}
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp ensure_save_dir do
    File.mkdir_p!(save_dir())
  end

  defp save_dir do
    try do
      Application.app_dir(:modus, @save_dir)
    rescue
      _ -> Path.join("priv", "saves") |> tap(&File.mkdir_p!/1)
    end
  end

  defp slot_path(slot), do: Path.join(save_dir(), "slot_#{slot}.json.gz")
  defp autosave_path, do: Path.join(save_dir(), @autosave_file)

  # Catch-all for unexpected messages
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  defp serialize_relationships(rels) when is_map(rels) do
    Enum.map(rels, fn {id, {type, strength}} ->
      %{agent_id: id, type: to_string(type), strength: ensure_float(strength)}
    end)
  end

  defp serialize_relationships(_), do: []
end
