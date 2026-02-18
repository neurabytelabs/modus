defmodule Modus.Simulation.EventChainTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.EventChain

  describe "get_chain/1" do
    test "returns chain links for drought" do
      chain = EventChain.get_chain(:drought)
      assert length(chain) == 3
      types = Enum.map(chain, & &1.event)
      assert :famine in types
      assert :migration_wave in types
      assert :conflict in types
    end

    test "returns empty list for unknown event" do
      assert EventChain.get_chain(:unknown_event) == []
    end

    test "all chain links have required fields" do
      for type <- EventChain.chain_types() do
        for link <- EventChain.get_chain(type) do
          assert is_atom(link.event)
          assert is_number(link.probability)
          assert link.probability >= 0 and link.probability <= 1
          assert is_integer(link.delay)
          assert link.delay > 0
          assert is_integer(link.severity_mod)
        end
      end
    end
  end

  describe "evaluate/3" do
    test "returns list of triggered chain events" do
      # Run many times to get at least some results (probabilistic)
      results =
        for _ <- 1..100, reduce: [] do
          acc -> acc ++ EventChain.evaluate(:drought, 100, 2)
        end

      # Should get at least some results over 100 trials
      assert length(results) > 0

      for {type, tick, severity} <- results do
        assert is_atom(type)
        assert tick > 100
        assert severity >= 1 and severity <= 3
      end
    end

    test "returns empty list for events with no chains" do
      # storm has no chain, so always empty
      results = EventChain.evaluate(:storm, 100, 1)
      assert is_list(results)
    end

    test "severity is clamped between 1 and 3" do
      for _ <- 1..50 do
        results = EventChain.evaluate(:golden_age, 0, 3)

        for {_type, _tick, severity} <- results do
          assert severity >= 1 and severity <= 3
        end
      end
    end
  end
end
