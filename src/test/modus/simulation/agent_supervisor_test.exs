defmodule Modus.Simulation.AgentSupervisorTest do
  use ExUnit.Case, async: false
  alias Modus.Simulation.{Agent, AgentSupervisor}

  describe "spawn_agent/1" do
    test "spawns an agent process" do
      agent = Agent.new("Spawn1", {0, 0})
      assert {:ok, pid} = AgentSupervisor.spawn_agent(agent)
      assert Process.alive?(pid)
    end

    test "agent is queryable via registry" do
      agent = Agent.new("Spawn2", {5, 5}, :farmer)
      {:ok, _pid} = AgentSupervisor.spawn_agent(agent)

      state = Agent.get_state(agent.id)
      assert state.name == "Spawn2"
      assert state.occupation == :farmer
    end
  end

  describe "kill_agent/1" do
    test "kills an existing agent" do
      agent = Agent.new("Doomed", {0, 0})
      {:ok, pid} = AgentSupervisor.spawn_agent(agent)
      assert :ok = AgentSupervisor.kill_agent(agent.id)
      Process.sleep(20)
      refute Process.alive?(pid)
    end

    test "returns error for unknown agent" do
      assert {:error, :not_found} = AgentSupervisor.kill_agent("nonexistent")
    end
  end

  describe "list_agents/0" do
    test "lists spawned agent ids" do
      a1 = Agent.new("List1", {0, 0})
      a2 = Agent.new("List2", {1, 1})
      AgentSupervisor.spawn_agent(a1)
      AgentSupervisor.spawn_agent(a2)

      ids = AgentSupervisor.list_agents()
      assert a1.id in ids
      assert a2.id in ids
    end
  end
end
