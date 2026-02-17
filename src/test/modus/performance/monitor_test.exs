defmodule Modus.Performance.MonitorTest do
  use ExUnit.Case, async: true

  alias Modus.Performance.Monitor

  describe "metrics/0" do
    test "returns valid metrics map" do
      m = Monitor.metrics()
      assert is_map(m)
      assert Map.has_key?(m, :agent_count)
      assert Map.has_key?(m, :memory_total_mb)
      assert Map.has_key?(m, :cpu_percent)
      assert Map.has_key?(m, :health)
      assert m.health in [:healthy, :warning, :critical]
      assert m.memory_total_mb >= 0
    end
  end
end
