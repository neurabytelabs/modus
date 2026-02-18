defmodule Modus.IntegrationTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.{World, Agent}

  @moduletag :integration

  describe "full simulation loop" do
    test "world → agents → tick → needs decay → decisions" do
      # 1. Start a world
      world = World.new("integration-test", grid_size: {50, 50})
      {:ok, _world_pid} = World.start_link(world)

      # 2. Spawn agents
      agent_ids =
        for i <- 1..5 do
          agent = Agent.new("TestAgent#{i}", {Enum.random(0..49), Enum.random(0..49)})
          {:ok, _pid} = Agent.start_link(agent)
          agent.id
        end

      assert length(agent_ids) == 5

      # 3. Get initial state
      initial_state = Agent.get_state(List.first(agent_ids))
      assert initial_state.alive? == true
      assert is_map(initial_state.needs)

      # 4. Run ticks sequentially (avoid GenServer deadlock in nearby_agents)
      context = %{world_id: world.id, resources: [], time_of_day: :morning}

      for tick <- 1..10 do
        Enum.each(agent_ids, fn id ->
          Agent.tick(id, tick, context)
          # Wait for each agent to finish its tick before next
          Agent.get_state(id)
        end)
      end

      # 5. After ticks, needs should have decayed
      post_state = Agent.get_state(List.first(agent_ids))
      has_decay = Enum.any?(post_state.needs, fn {_k, v} -> v < 80.0 end)
      assert has_decay, "Needs should decay after ticks"

      # 6. Agents should still be alive
      Enum.each(agent_ids, fn id ->
        state = Agent.get_state(id)
        assert state.alive?
      end)

      # Clean up
      Enum.each(agent_ids, fn id ->
        GenServer.stop({:via, Registry, {Modus.AgentRegistry, id}})
      end)
    end

    test "50 agents tick performance — sequential tick < 200ms" do
      agent_ids =
        for i <- 1..50 do
          agent = Agent.new("PerfAgent#{i}", {Enum.random(0..99), Enum.random(0..99)})
          {:ok, _pid} = Agent.start_link(agent)
          agent.id
        end

      context = %{resources: [], time_of_day: :afternoon}

      # Measure sequential tick (mirrors actual Ticker behavior)
      {elapsed_us, _} =
        :timer.tc(fn ->
          Enum.each(agent_ids, fn id ->
            Agent.tick(id, 1, context)
            Agent.get_state(id)
          end)
        end)

      elapsed_ms = elapsed_us / 1000
      assert elapsed_ms < 200, "50 agents sequential tick took #{elapsed_ms}ms, should be <200ms"

      # Clean up
      Enum.each(agent_ids, fn id ->
        GenServer.stop({:via, Registry, {Modus.AgentRegistry, id}})
      end)
    end
  end
end
