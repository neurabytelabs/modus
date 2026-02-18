defmodule Modus.Intelligence.BudgetTracker do
  @moduledoc """
  BudgetTracker — Limits LLM calls per tick with priority queue.

  Max N calls per tick. High-priority requests (e.g., user chat) bypass limit.
  Low-priority batch decisions get queued/dropped when over budget.
  """

  @table :llm_budget
  @max_calls_per_tick 5

  # ── Setup ──────────────────────────────────────────────

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    reset()
    :ok
  end

  @doc "Reset budget for new tick."
  def reset do
    :ets.insert(@table, {:calls_remaining, @max_calls_per_tick})
    :ets.insert(@table, {:current_tick_calls, 0})
    :ok
  rescue
    _ -> :ok
  end

  @doc "Request a call slot. Returns :ok or :over_budget."
  def request_slot(priority \\ :normal) do
    case priority do
      :high ->
        # High priority always allowed (user chat, etc.)
        :ets.update_counter(@table, :current_tick_calls, {2, 1}, {:current_tick_calls, 0})
        :ok

      _ ->
        remaining = get_remaining()

        if remaining > 0 do
          :ets.update_counter(@table, :calls_remaining, {2, -1}, {:calls_remaining, 0})
          :ets.update_counter(@table, :current_tick_calls, {2, 1}, {:current_tick_calls, 0})
          :ok
        else
          :over_budget
        end
    end
  rescue
    _ -> :ok
  end

  @doc "Get remaining call slots."
  def get_remaining do
    case :ets.lookup(@table, :calls_remaining) do
      [{:calls_remaining, n}] -> max(n, 0)
      [] -> @max_calls_per_tick
    end
  rescue
    _ -> @max_calls_per_tick
  end

  @doc "Get calls made this tick."
  def calls_this_tick do
    case :ets.lookup(@table, :current_tick_calls) do
      [{:current_tick_calls, n}] -> n
      [] -> 0
    end
  rescue
    _ -> 0
  end

  @doc "Get max calls per tick."
  def max_per_tick, do: @max_calls_per_tick
end
