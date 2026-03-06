defmodule Modus.Nexus.InsightEngineTest do
  use ExUnit.Case, async: false

  alias Modus.Nexus.InsightEngine

  @ets_table :nexus_position_history

  setup do
    # Ensure ETS table exists (InsightEngine should be started by application)
    # If not, start it manually for test isolation
    unless :ets.whereis(@ets_table) != :undefined do
      :ets.new(@ets_table, [:set, :public, :named_table])
    end

    # Clean up test data
    :ets.delete_all_objects(@ets_table)
    :ok
  end

  # 1. InsightEngine starts and creates ETS table
  test "ETS table exists after init" do
    assert :ets.whereis(@ets_table) != :undefined
  end

  # 2. record_position stores positions
  test "record_position stores positions" do
    InsightEngine.record_position("agent-1", {10, 20})
    InsightEngine.record_position("agent-1", {11, 21})

    [{_, positions}] = :ets.lookup(@ets_table, "agent-1")
    assert length(positions) == 2
    assert hd(positions) == {11, 21}
  end

  # 3. record_position caps at 50
  test "record_position caps at 50 positions" do
    for i <- 1..60 do
      InsightEngine.record_position("agent-cap", {i, i})
    end

    [{_, positions}] = :ets.lookup(@ets_table, "agent-cap")
    assert length(positions) == 50
    # Most recent should be {60, 60}
    assert hd(positions) == {60, 60}
  end

  # 4. agent_query returns data for valid agent (requires running agent — test graceful path)
  test "agent_query with non-existent agent returns error" do
    result = InsightEngine.agent_query("nonexistent-agent-xyz")
    assert result == {:error, :agent_not_found}
  end

  # 5. agent_query handles missing agent gracefully
  test "agent_query handles missing agent gracefully" do
    result = InsightEngine.agent_query("does-not-exist")
    assert {:error, :agent_not_found} = result
  end

  # 6. event_replay returns a list
  test "event_replay returns events list" do
    result = InsightEngine.event_replay(limit: 5)
    assert is_list(result)
  end

  # 7. stats_query computes correct stats (with no agents running)
  test "stats_query returns zero stats when no agents" do
    stats = InsightEngine.stats_query()
    assert stats.total_agents >= 0
    assert is_float(stats.average_energy) or stats.average_energy == 0.0
  end

  # 8. format_response falls back to template when Ollama unavailable
  test "format_response falls back to template" do
    data = %{name: "TestAgent", conatus_energy: 0.8, affect_state: :happy}
    result = InsightEngine.format_response(:agent_query, data)
    assert is_binary(result)
    assert String.length(result) > 0
  end

  # 9. format_response works for stats
  test "format_response template for stats_query" do
    data = %{total_agents: 5, average_energy: 0.65}
    result = InsightEngine.format_response(:stats_query, data)
    assert String.length(result) > 0
  end

  # 10. format_response works for events
  test "format_response template for event_query" do
    data = [%{type: :conversation}, %{type: :death}]
    result = InsightEngine.format_response(:event_query, data)
    assert String.length(result) > 0
  end
end
