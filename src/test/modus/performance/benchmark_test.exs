defmodule Modus.Performance.BenchmarkTest do
  use ExUnit.Case, async: true

  alias Modus.Performance.Benchmark

  describe "quick/0" do
    test "returns performance snapshot" do
      result = Benchmark.quick()
      assert is_map(result)
      assert Map.has_key?(result, :agent_count)
      assert Map.has_key?(result, :spatial_rebuild_us)
      assert Map.has_key?(result, :memory)
      assert result.agent_count >= 0
    end
  end
end
