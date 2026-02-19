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
          # v7.8: Store full state for latest 3, delta for older ones
          updated =
            [{tick, {:full, state}} | snapshots]
            |> Enum.take(@max_snapshots)
            |> compress_snapshots()

          :ets.insert(@ets_table, {agent_id, updated})
        end)
    end
  rescue
    _ -> :ok
  end

  @doc "Get snapshot history for an agent (newest first). Reconstructs full state from deltas."
  @spec history(String.t()) :: [{non_neg_integer(), map()}]
  def history(agent_id) do
    case :ets.whereis(@ets_table) do
      :undefined -> []
      _ ->
        case :ets.lookup(@ets_table, agent_id) do
          [{^agent_id, snapshots}] -> reconstruct_snapshots(snapshots)
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

  @doc "Diff two snapshots for an agent, returning changed fields between tick_a and tick_b."
  @spec diff(String.t(), non_neg_integer(), non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def diff(agent_id, tick_a, tick_b) do
    snapshots = history(agent_id)

    with snap_a when snap_a != nil <- find_snapshot(snapshots, tick_a),
         snap_b when snap_b != nil <- find_snapshot(snapshots, tick_b) do
      changes =
        (Map.keys(snap_a) ++ Map.keys(snap_b))
        |> Enum.uniq()
        |> Enum.reduce(%{}, fn key, acc ->
          val_a = Map.get(snap_a, key)
          val_b = Map.get(snap_b, key)

          if val_a != val_b do
            Map.put(acc, key, %{from: val_a, to: val_b})
          else
            acc
          end
        end)

      {:ok, changes}
    else
      nil -> {:error, :not_found}
    end
  end

  defp find_snapshot(snapshots, tick) do
    case Enum.find(snapshots, fn {t, _} -> t == tick end) do
      {_, state} -> state
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

  # ── v7.8: Delta Compression ──────────────────────────────

  @full_count 3

  # Keep first @full_count as :full, convert older to :delta (diff from next newer)
  defp compress_snapshots(snapshots) do
    {recent, old} = Enum.split(snapshots, @full_count)

    recent_full =
      Enum.map(recent, fn
        {tick, {:full, state}} -> {tick, {:full, state}}
        {_tick, {:delta, _delta}} = entry ->
          # Already delta, leave as-is (shouldn't happen for recent)
          entry
        {tick, state} when is_map(state) -> {tick, {:full, state}}
      end)

    # For old entries, compute delta relative to the entry just before them (newer)
    base_states = reconstruct_snapshots(recent_full)
    base = case List.last(base_states) do
      {_tick, state} -> state
      nil -> %{}
    end

    old_compressed =
      old
      |> Enum.map(fn
        {tick, {:full, state}} ->
          delta = compute_delta(base, state)
          {tick, {:delta, delta}}
        {_tick, {:delta, _}} = entry -> entry
        {tick, state} when is_map(state) ->
          delta = compute_delta(base, state)
          {tick, {:delta, delta}}
      end)

    recent_full ++ old_compressed
  end

  # Compute changed fields: base -> target
  defp compute_delta(base, target) do
    all_keys = (Map.keys(base) ++ Map.keys(target)) |> Enum.uniq()

    Enum.reduce(all_keys, %{}, fn key, acc ->
      v_base = Map.get(base, key)
      v_target = Map.get(target, key)

      if v_base != v_target do
        Map.put(acc, key, v_target)
      else
        acc
      end
    end)
  end

  # Reconstruct full states from mixed full/delta snapshots (newest first).
  # Deltas are applied against the nearest full snapshot base (scanning forward = older).
  defp reconstruct_snapshots(snapshots) do
    # Pass 1: find the last full snapshot as base, then reconstruct deltas
    # Snapshots are newest-first, so we reverse to process oldest-first
    reversed = Enum.reverse(snapshots)

    {result, _last_full} =
      Enum.reduce(reversed, {[], nil}, fn entry, {acc, last_full} ->
        case entry do
          {tick, {:full, state}} ->
            {[{tick, state} | acc], state}

          {tick, {:delta, delta}} ->
            case last_full do
              nil ->
                # No base snapshot available — return delta as partial (best-effort)
                {[{tick, delta} | acc], nil}
              base ->
                reconstructed = Map.merge(base, delta)
                {[{tick, reconstructed} | acc], base}
            end

          {tick, state} when is_map(state) ->
            # Legacy format
            {[{tick, state} | acc], state}
        end
      end)

    result
  end
end
