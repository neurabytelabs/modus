defmodule Modus.Performance.MemoryAuditTest do
  use ExUnit.Case, async: true

  alias Modus.Performance.MemoryAudit

  describe "summary/0" do
    test "returns valid structure" do
      result = MemoryAudit.summary()
      assert is_map(result)
      assert Map.has_key?(result, :count)
      assert Map.has_key?(result, :total_bytes)
      assert Map.has_key?(result, :avg_bytes)
      assert Map.has_key?(result, :over_limit)
      assert result.count >= 0
    end
  end

  describe "ets_tables/0" do
    test "lists ETS tables with memory info" do
      tables = MemoryAudit.ets_tables()
      assert is_list(tables)
      if tables != [] do
        first = hd(tables)
        assert Map.has_key?(first, :name)
        assert Map.has_key?(first, :memory_bytes)
        assert first.memory_bytes >= 0
      end
    end
  end

  describe "system_report/0" do
    test "returns comprehensive report" do
      report = MemoryAudit.system_report()
      assert is_map(report)
      assert report.total_bytes > 0
      assert report.processes_bytes > 0
      assert is_map(report.agent_summary)
      assert is_list(report.ets_tables)
    end
  end
end
