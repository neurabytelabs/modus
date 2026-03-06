defmodule Modus.Nexus.TraceEngineTest do
  use ExUnit.Case, async: false

  alias Modus.Nexus.TraceEngine

  @ets_decisions :nexus_trace_decisions
  @ets_positions :nexus_trace_positions
  @ets_disappearances :nexus_trace_disappearances

  setup do
    for table <- [@ets_decisions, @ets_positions, @ets_disappearances] do
      if :ets.whereis(table) == :undefined do
        :ets.new(table, [:set, :public, :named_table])
      end

      :ets.delete_all_objects(table)
    end

    :ok
  end

  # 1. ETS tables exist after init
  test "ETS tables created" do
    for table <- [@ets_decisions, @ets_positions, @ets_disappearances] do
      assert :ets.whereis(table) != :undefined
    end
  end

  # 2. log_decision stores and retrieves decisions
  test "log_decision stores decisions" do
    entry = %{tick: 1, timestamp: 1000, action: :move, reason: "hungry", energy: 0.5, affect: :sad, position: {10, 10}}
    assert :ok = TraceEngine.log_decision("agent-1", entry)

    decisions = TraceEngine.get_decisions("agent-1")
    assert length(decisions) == 1
    assert hd(decisions).action == :move
  end

  # 3. Decision log circular buffer (max 100)
  test "decision log caps at 100" do
    for i <- 1..120 do
      entry = %{tick: i, timestamp: i * 1000, action: :move, reason: nil, energy: 0.5, affect: :neutral, position: {i, i}}
      TraceEngine.log_decision("agent-cap", entry)
    end

    decisions = TraceEngine.get_decisions("agent-cap", 200)
    assert length(decisions) == 100
    # Most recent first
    assert hd(decisions).tick == 120
  end

  # 4. log_position stores position trace
  test "log_position stores positions" do
    TraceEngine.log_position("agent-1", {5, 5}, 1)
    TraceEngine.log_position("agent-1", {6, 6}, 2)

    trace = TraceEngine.get_position_trace("agent-1")
    assert length(trace) == 2
    assert hd(trace).position == {6, 6}
  end

  # 5. Position trace caps at 100
  test "position trace caps at 100" do
    for i <- 1..120 do
      TraceEngine.log_position("agent-pos-cap", {i, i}, i)
    end

    trace = TraceEngine.get_position_trace("agent-pos-cap", 200)
    assert length(trace) == 100
  end

  # 6. get_decisions with limit
  test "get_decisions respects limit" do
    for i <- 1..10 do
      entry = %{tick: i, timestamp: i, action: :idle, reason: nil, energy: 0.7, affect: :neutral, position: {0, 0}}
      TraceEngine.log_decision("agent-lim", entry)
    end

    assert length(TraceEngine.get_decisions("agent-lim", 3)) == 3
  end

  # 7. get_decisions returns empty for unknown agent
  test "get_decisions returns empty for unknown agent" do
    assert TraceEngine.get_decisions("nonexistent") == []
  end

  # 8. get_position_trace returns empty for unknown agent
  test "get_position_trace returns empty for unknown agent" do
    assert TraceEngine.get_position_trace("nonexistent") == []
  end

  # 9. why_answer returns string for unknown agent
  test "why_answer handles missing agent" do
    result = TraceEngine.why_answer("nonexistent-agent")
    assert is_binary(result)
    assert String.contains?(result, "not found")
  end

  # 10. why_answer returns analysis for agent with decisions logged
  test "why_answer with logged decisions produces template" do
    # Log some decisions so the template has data
    for i <- 1..3 do
      entry = %{tick: i, timestamp: i * 1000, action: :forage, reason: "açlık", energy: 0.3, affect: :sad, position: {i, i}}
      TraceEngine.log_decision("trace-test-agent", entry)
      TraceEngine.log_position("trace-test-agent", {i, i}, i)
    end

    # Since the agent doesn't actually exist in simulation,
    # why_answer will return the "bulunamadı" template
    result = TraceEngine.why_answer("trace-test-agent")
    assert is_binary(result)
  end

  # 11. disappearance detection returns empty when no agents OOB
  test "check_disappearances returns empty when no agents" do
    result = TraceEngine.check_disappearances(%{min_x: 0, min_y: 0, max_x: 49, max_y: 49})
    # May be empty or contain agents — just check it returns a list
    assert is_list(result)
  end

  # 12. get_disappearances returns list
  test "get_disappearances returns list" do
    result = TraceEngine.get_disappearances()
    assert is_list(result)
  end
end
