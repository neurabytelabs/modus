defmodule Modus.Simulation.StateSnapshots do
  @moduledoc """
  StateSnapshots — Time-travel agent state inspection (v7.7).

  Stores agent state snapshots every N ticks in an ETS ring buffer.
  Keeps the last `@max_snapshots` snapshots per agent for rewind inspection.

  ## Usage

      # Called from Ticker every 100 ticks
      StateSnapshots.capture(tick_number)

      # Inspect an agent's history
      StateSnapshots.history("agent_123")
      # => [{tick, agent_state}, ...]

      # Get snapshot at specific tick
      StateSnapshots.at("agent_123", 500)
  """

  @ets_table :agent_state_snapshots
  @max_snapshots 10
  @snapshot_interval 100

  @doc "Initialize ETS table. Call from Application.start/2."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    end

    :ok
  end

  @doc "Snapshot interval in ticks."
  @spec interval() :: pos_integer()
  def interval, do: @snapshot_interval

  @doc "Capture snapshots of all agents at the given tick."
  @spec capture(non_neg_integer()) :: :ok
  def capture(tick) do
    case :ets.whereis(:agent_states_cache) do
      :undefined ->
        :ok

      _ ->
        :ets.tab2list(:agent_states_cache)
        |> Enum.each(fn {agent_id, state} ->
          snapshots =
            case :ets.lookup(@ets_table, agent_id) do
              [{^agent_id, existing}] -> existing
              [] -> []
            end

          # Ring buffer: keep last @max_snapshots
          updated = Enum.take([{tick, state} | snapshots], @max_snapshots)
          :ets.insert(@ets_table, {agent_id, updated})
        end)
    end
  rescue
    _ -> :ok
  end

  @doc "Get snapshot history for an agent (newest first)."
  @spec history(String.t()) :: [{non_neg_integer(), map()}]
  def history(agent_id) do
    case :ets.whereis(@ets_table) do
      :undefined -> []
      _ ->
        case :ets.lookup(@ets_table, agent_id) do
          [{^agent_id, snapshots}] -> snapshots
          [] -> []
        end
    end
  rescue
    _ -> []
  end

  @doc "Get agent state at a specific tick (nearest snapshot)."
  @spec at(String.t(), non_neg_integer()) :: map() | nil
  def at(agent_id, tick) do
    history(agent_id)
    |> Enum.min_by(fn {t, _} -> abs(t - tick) end, fn -> nil end)
    |> case do
      {_t, state} -> state
      nil -> nil
    end
  end

  @doc "Clean up snapshots for a terminated agent."
  @spec cleanup(String.t()) :: :ok
  def cleanup(agent_id) do
    try do
      if :ets.whereis(@ets_table) != :undefined do
        :ets.delete(@ets_table, agent_id)
      end
    catch
      _, _ -> :ok
    end

    :ok
  end
end
