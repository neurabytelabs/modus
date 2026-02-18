defmodule Modus.Simulation.TradeSystemTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.TradeSystem

  setup do
    # Clean up ETS tables
    for table <- [:modus_trade_system, :modus_trade_history] do
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end

    TradeSystem.init()

    agent_a = %{
      id: "agent-a",
      name: "Maya",
      position: {5, 5},
      personality: %{
        openness: 0.7,
        conscientiousness: 0.6,
        extraversion: 0.5,
        agreeableness: 0.8,
        neuroticism: 0.3
      },
      needs: %{hunger: 40.0, social: 50.0, rest: 80.0, shelter: 70.0},
      inventory: %{wood: 10.0, stone: 2.0, food: 1.0},
      occupation: :gatherer
    }

    agent_b = %{
      id: "agent-b",
      name: "Kai",
      position: {6, 5},
      personality: %{
        openness: 0.4,
        conscientiousness: 0.8,
        extraversion: 0.3,
        agreeableness: 0.3,
        neuroticism: 0.6
      },
      needs: %{hunger: 70.0, social: 30.0, rest: 60.0, shelter: 80.0},
      inventory: %{wood: 1.0, stone: 8.0, food: 12.0},
      occupation: :builder
    }

    {:ok, agent_a: agent_a, agent_b: agent_b}
  end

  describe "init/0" do
    test "creates ETS tables" do
      assert :ets.whereis(:modus_trade_system) != :undefined
      assert :ets.whereis(:modus_trade_history) != :undefined
    end

    test "initializes stats" do
      stats = TradeSystem.stats()
      assert stats.total_trades == 0
      assert stats.total_value == 0.0
    end
  end

  describe "propose_trade/7" do
    test "successful trade between nearby agents", %{agent_a: a, agent_b: b} do
      assert {:ok, trade} = TradeSystem.propose_trade(a, b, :wood, 3.0, :food, 2.0, 100)
      assert trade.agent_a_id == "agent-a"
      assert trade.agent_b_id == "agent-b"
      assert trade.offered.resource == :wood
      assert trade.received.resource == :food
    end

    test "rejected when too far apart", %{agent_a: a, agent_b: b} do
      far_b = %{b | position: {50, 50}}
      assert {:error, :too_far} = TradeSystem.propose_trade(a, far_b, :wood, 3.0, :food, 2.0, 100)
    end

    test "rejected when insufficient inventory", %{agent_a: a, agent_b: b} do
      assert {:error, :insufficient_resources} =
               TradeSystem.propose_trade(a, b, :wood, 100.0, :food, 2.0, 100)
    end

    test "rejected when agent B lacks requested resource", %{agent_a: a, agent_b: b} do
      poor_b = %{b | inventory: %{wood: 1.0, stone: 0.0, food: 0.0}}

      assert {:error, :insufficient_resources} =
               TradeSystem.propose_trade(a, poor_b, :wood, 3.0, :food, 2.0, 100)
    end

    test "updates stats after trade", %{agent_a: a, agent_b: b} do
      {:ok, _} = TradeSystem.propose_trade(a, b, :wood, 3.0, :food, 2.0, 100)
      stats = TradeSystem.stats()
      assert stats.total_trades == 1
      assert stats.total_value > 0.0
    end

    test "records trade history", %{agent_a: a, agent_b: b} do
      {:ok, _} = TradeSystem.propose_trade(a, b, :wood, 3.0, :food, 2.0, 100)
      history = TradeSystem.trade_history()
      assert length(history) == 1
      assert hd(history).agent_a_name == "Maya"
    end
  end

  describe "personality_value_modifier/1" do
    test "agreeable agents have lower modifier (accept worse deals)" do
      agreeable = %{agreeableness: 0.9, conscientiousness: 0.5}
      disagreeable = %{agreeableness: 0.1, conscientiousness: 0.5}

      assert TradeSystem.personality_value_modifier(agreeable) <
               TradeSystem.personality_value_modifier(disagreeable)
    end

    test "returns float" do
      mod = TradeSystem.personality_value_modifier(%{agreeableness: 0.5, conscientiousness: 0.5})
      assert is_float(mod)
    end
  end

  describe "resource_value/1" do
    test "returns base values for known resources" do
      assert TradeSystem.resource_value(:food) > TradeSystem.resource_value(:wood)
    end

    test "returns default for unknown resources" do
      assert TradeSystem.resource_value(:unknown) == 1.0
    end

    test "supply/demand affects value" do
      # Abundant supply lowers value
      TradeSystem.update_supply(%{wood: 100.0})
      low_val = TradeSystem.resource_value(:wood)

      # Scarce supply raises value
      TradeSystem.update_supply(%{wood: 10.0})
      high_val = TradeSystem.resource_value(:wood)

      assert high_val > low_val
    end
  end

  describe "trade_history/1" do
    test "filters by agent_id", %{agent_a: a, agent_b: b} do
      {:ok, _} = TradeSystem.propose_trade(a, b, :wood, 3.0, :food, 2.0, 100)

      assert length(TradeSystem.trade_history(agent_id: "agent-a")) == 1
      assert length(TradeSystem.trade_history(agent_id: "nonexistent")) == 0
    end

    test "respects limit", %{agent_a: a, agent_b: b} do
      for tick <- 1..5 do
        TradeSystem.propose_trade(a, b, :wood, 3.0, :food, 1.0, tick)
      end

      assert length(TradeSystem.trade_history(limit: 3)) == 3
    end
  end

  describe "find_trade_opportunity/2" do
    test "finds opportunity when agent has surplus and need", %{agent_a: a, agent_b: b} do
      # Agent A has lots of wood, needs food (hunger high)
      rich_a = %{
        a
        | inventory: %{wood: 20.0, food: 0.5},
          needs: %{hunger: 70.0, social: 50.0, rest: 50.0, shelter: 50.0}
      }

      rich_b = %{b | inventory: %{wood: 0.5, food: 20.0}}

      assert {:ok, opp} = TradeSystem.find_trade_opportunity(rich_a, [rich_b])
      assert opp.partner.id == "agent-b"
      assert opp.offer == :wood
    end

    test "returns :none when no suitable partner", %{agent_a: a} do
      assert :none = TradeSystem.find_trade_opportunity(a, [])
    end
  end

  describe "market_bonus?/1" do
    test "returns false when no buildings table" do
      if :ets.whereis(:buildings) != :undefined, do: :ets.delete(:buildings)
      refute TradeSystem.market_bonus?({5, 5})
    end

    test "returns true when market nearby" do
      if :ets.whereis(:buildings) != :undefined, do: :ets.delete(:buildings)
      :ets.new(:buildings, [:set, :public, :named_table])
      :ets.insert(:buildings, {"market-1", %{type: :market, position: {5, 6}}})

      assert TradeSystem.market_bonus?({5, 5})

      :ets.delete(:buildings)
    end
  end

  describe "update_supply/1" do
    test "stores supply data" do
      TradeSystem.update_supply(%{wood: 50.0, food: 30.0})
      # Verify via resource_value changes
      assert is_float(TradeSystem.resource_value(:wood))
    end
  end
end
