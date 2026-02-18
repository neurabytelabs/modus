defmodule Modus.Performance.StateLimiterTest do
  use ExUnit.Case, async: true

  alias Modus.Performance.StateLimiter

  describe "trim/1" do
    test "trims long memory lists" do
      agent = %{
        memory: Enum.map(1..50, fn i -> {i, {:idle, %{}}} end),
        affect_history: Enum.map(1..30, fn i -> {:joy, i} end),
        conatus_history: Enum.map(1..30, fn i -> {0.5, i} end),
        inventory: %{}
      }

      trimmed = StateLimiter.trim(agent)
      assert length(trimmed.memory) == 15
      assert length(trimmed.affect_history) == 10
      assert length(trimmed.conatus_history) == 10
    end

    test "trims large inventories" do
      inv = for i <- 1..20, into: %{}, do: {:"item_#{i}", i * 10.0}
      agent = %{memory: [], affect_history: [], conatus_history: [], inventory: inv}
      trimmed = StateLimiter.trim(agent)
      assert map_size(trimmed.inventory) == 8
    end

    test "leaves small state untouched" do
      agent = %{
        memory: [{1, :idle}],
        affect_history: [],
        conatus_history: [],
        inventory: %{wood: 5}
      }

      assert StateLimiter.trim(agent) == agent
    end
  end

  describe "estimate_size/1" do
    test "returns positive integer for any term" do
      assert StateLimiter.estimate_size(%{a: 1, b: [1, 2, 3]}) > 0
    end
  end
end
