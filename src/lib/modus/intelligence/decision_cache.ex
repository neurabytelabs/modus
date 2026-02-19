defmodule Modus.Intelligence.DecisionCache do
  @moduledoc """
  DecisionCache — ETS-backed cache for LLM decisions with TTL.

  Avoids redundant LLM calls by caching recent decisions per agent.
  TTL: 5 minutes (300 seconds).
  """

  use GenServer

  @table :llm_decision_cache
  @ttl_ms 300_000
  @cleanup_interval_ms 60_000

  # ── Public API ──────────────────────────────────────────────

  @doc "Get a cached decision for an agent_id. Returns nil if expired or missing."
  @spec get(String.t()) :: {atom(), map()} | nil
  def get(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, decision, inserted_at}] ->
        if System.monotonic_time(:millisecond) - inserted_at < @ttl_ms do
          decision
        else
          :ets.delete(@table, agent_id)
          nil
        end

      [] ->
        nil
    end
  end

  @doc "Cache a decision for an agent_id."
  @spec put(String.t(), {atom(), map()}) :: :ok
  def put(agent_id, decision) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table, {agent_id, decision, now})
    :ok
  end

  @doc "Clear all cached decisions."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  # ── GenServer ───────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now - @ttl_ms}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
