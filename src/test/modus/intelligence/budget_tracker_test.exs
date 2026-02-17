defmodule Modus.Intelligence.BudgetTrackerTest do
  use ExUnit.Case, async: false

  alias Modus.Intelligence.BudgetTracker

  setup do
    BudgetTracker.init()
    BudgetTracker.reset()
    :ok
  end

  test "init creates ETS table" do
    assert :ets.whereis(:llm_budget) != :undefined
  end

  test "request_slot decrements budget" do
    initial = BudgetTracker.get_remaining()
    assert :ok = BudgetTracker.request_slot(:normal)
    assert BudgetTracker.get_remaining() == initial - 1
  end

  test "over_budget when slots exhausted" do
    max = BudgetTracker.max_per_tick()
    for _ <- 1..max, do: BudgetTracker.request_slot(:normal)
    assert :over_budget = BudgetTracker.request_slot(:normal)
  end

  test "high priority bypasses budget" do
    max = BudgetTracker.max_per_tick()
    for _ <- 1..max, do: BudgetTracker.request_slot(:normal)
    assert :ok = BudgetTracker.request_slot(:high)
  end

  test "reset restores budget" do
    BudgetTracker.request_slot(:normal)
    BudgetTracker.reset()
    assert BudgetTracker.get_remaining() == BudgetTracker.max_per_tick()
  end

  test "calls_this_tick tracks usage" do
    BudgetTracker.request_slot(:normal)
    BudgetTracker.request_slot(:normal)
    assert BudgetTracker.calls_this_tick() == 2
  end
end
