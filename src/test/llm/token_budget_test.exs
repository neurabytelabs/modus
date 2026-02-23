defmodule Modus.Llm.TokenBudgetTest do
  use ExUnit.Case, async: false

  alias Modus.Llm.TokenBudget

  setup do
    TokenBudget.init()
    TokenBudget.reset()
    :ok
  end

  test "track_call returns :ok within budget" do
    assert :ok = TokenBudget.track_call("agent_1", 100, 1)
  end

  test "track_call returns :over_budget when agent exceeds limit" do
    assert :ok = TokenBudget.track_call("agent_1", 400, 1)
    assert {:over_budget, :agent_limit} = TokenBudget.track_call("agent_1", 200, 2)
  end

  test "remaining/0 tracks session-level calls" do
    assert TokenBudget.remaining() == 1000
    TokenBudget.track_call("agent_1", 50, 1)
    assert TokenBudget.remaining() == 999
  end

  test "remaining/1 tracks per-agent tokens" do
    assert TokenBudget.remaining("agent_1") == 500
    TokenBudget.track_call("agent_1", 200, 1)
    assert TokenBudget.remaining("agent_1") == 300
  end

  test "stats returns full budget info" do
    TokenBudget.track_call("agent_1", 100, 1)
    stats = TokenBudget.stats()
    assert stats.total_calls == 1
    assert stats.total_tokens == 100
    assert stats.calls_remaining == 999
    assert length(stats.agents) == 1
  end

  test "reset clears all budgets" do
    TokenBudget.track_call("agent_1", 100, 1)
    TokenBudget.reset()
    assert TokenBudget.remaining() == 1000
    assert TokenBudget.remaining("agent_1") == 500
  end

  test "session limit triggers over_budget" do
    # Track 1000 calls
    for i <- 1..1000 do
      TokenBudget.track_call("agent_#{rem(i, 100)}", 1, i)
    end

    assert {:over_budget, :session_limit} = TokenBudget.track_call("agent_x", 1, 1001)
  end
end
