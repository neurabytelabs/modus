defmodule Modus.Simulation.AgentTest do
  use ExUnit.Case, async: true
  alias Modus.Simulation.Agent

  describe "new/3" do
    test "creates agent with valid defaults" do
      agent = Agent.new("Elif", {5, 10}, :farmer)

      assert agent.name == "Elif"
      assert agent.position == {5, 10}
      assert agent.occupation == :farmer
      assert agent.alive? == true
      assert agent.age == 0
      assert agent.conatus_score == 5.0
      assert agent.current_action == :idle
    end

    test "generates unique ids" do
      a1 = Agent.new("A", {0, 0})
      a2 = Agent.new("B", {1, 1})

      assert a1.id != a2.id
    end

    test "creates random personality with Big Five traits" do
      agent = Agent.new("Test", {0, 0})

      assert Map.has_key?(agent.personality, :openness)
      assert Map.has_key?(agent.personality, :conscientiousness)
      assert Map.has_key?(agent.personality, :extraversion)
      assert Map.has_key?(agent.personality, :agreeableness)
      assert Map.has_key?(agent.personality, :neuroticism)

      for {_trait, value} <- agent.personality do
        assert value >= 0.0 and value <= 1.0
      end
    end

    test "initializes needs at balanced levels" do
      agent = Agent.new("Test", {0, 0})

      assert agent.needs.hunger == 50.0
      assert agent.needs.social == 50.0
      assert agent.needs.rest == 80.0
      assert agent.needs.shelter == 70.0
    end

    test "defaults to explorer occupation" do
      agent = Agent.new("Test", {0, 0})
      assert agent.occupation == :explorer
    end
  end

  describe "GenServer tick" do
    setup do
      agent = Agent.new("Ticker", {10, 10})
      pid = start_supervised!({Agent, agent})
      %{pid: pid, agent: agent}
    end

    test "tick decays needs", %{agent: agent} do
      Agent.tick(agent.id, 1)
      # Give cast time to process
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.age == 1
      assert state.needs.hunger > 50.0
      assert state.needs.social < 50.0
      assert state.needs.rest < 80.0
    end

    test "multiple ticks accumulate decay", %{agent: agent} do
      for i <- 1..10, do: Agent.tick(agent.id, i)
      Process.sleep(50)
      state = Agent.get_state(agent.id)

      assert state.age == 10
      assert_in_delta state.needs.hunger, 51.0, 0.01
      assert_in_delta state.needs.social, 49.5, 0.01
      assert_in_delta state.needs.rest, 79.2, 0.01
    end

    test "agent dies when hunger exceeds 100", %{agent: agent} do
      # Set hunger close to death
      :sys.replace_state(via(agent.id), fn s ->
        %{s | needs: %{s.needs | hunger: 99.95}}
      end)

      Agent.tick(agent.id, 1)
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.alive? == false
      assert state.current_action == :dead
    end

    test "agent dies when rest drops below 0", %{agent: agent} do
      # Set rest very low and hunger high so decision engine picks :find_food
      # instead of :sleep, allowing rest to decay past 0
      :sys.replace_state(via(agent.id), fn s ->
        %{s | needs: %{s.needs | rest: 0.05, hunger: 90.0}}
      end)

      Agent.tick(agent.id, 1)
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.alive? == false
    end

    test "dead agents don't tick further", %{agent: agent} do
      :sys.replace_state(via(agent.id), fn s ->
        %{s | alive?: false, age: 42}
      end)

      Agent.tick(agent.id, 1)
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.age == 42
    end
  end

  describe "movement" do
    setup do
      agent = Agent.new("Mover", {10, 10})
      pid = start_supervised!({Agent, agent})
      %{pid: pid, agent: agent}
    end

    test "moves one cell toward target", %{agent: agent} do
      Agent.move_toward(agent.id, {15, 10})
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.position == {11, 10}
    end

    test "moves diagonally toward target", %{agent: agent} do
      Agent.move_toward(agent.id, {15, 15})
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.position == {11, 11}
    end

    test "stays put when already at target", %{agent: agent} do
      Agent.move_toward(agent.id, {10, 10})
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.position == {10, 10}
    end

    test "dead agents don't move", %{agent: agent} do
      :sys.replace_state(via(agent.id), fn s -> %{s | alive?: false} end)

      Agent.move_toward(agent.id, {15, 15})
      Process.sleep(20)
      state = Agent.get_state(agent.id)

      assert state.position == {10, 10}
    end
  end

  describe "perception" do
    setup do
      a1 = Agent.new("Near", {10, 10})
      a2 = Agent.new("Far", {10, 13})
      a3 = Agent.new("TooFar", {10, 20})

      start_supervised!({Agent, a1}, id: :perc_a1)
      start_supervised!({Agent, a2}, id: :perc_a2)
      start_supervised!({Agent, a3}, id: :perc_a3)

      %{a1: a1, a2: a2, a3: a3}
    end

    test "finds nearby agents within radius", %{a1: a1, a2: a2, a3: a3} do
      nearby = Agent.nearby_agents(a1.position, 5)

      assert a1.id in nearby
      assert a2.id in nearby
      refute a3.id in nearby
    end
  end

  defp via(id), do: {:via, Registry, {Modus.AgentRegistry, id}}
end
