defmodule Modus.Performance.AgentBenchmarkTest do
  @moduledoc "Performance baseline: measures memory per agent."
  use ExUnit.Case, async: false

  alias Modus.Simulation.Agent

  setup_all do
    Modus.Simulation.Lifecycle.init()
    :ok
  end

  @tag :benchmark
  test "memory per agent baseline" do
    # Measure memory before
    :erlang.garbage_collect()
    mem_before = :erlang.memory(:total)

    # Spawn 50 agents
    agents =
      for i <- 1..50 do
        agent = Agent.new("Bench#{i}", {rem(i, 50), div(i, 50)})
        {:ok, pid} = Agent.start_link(agent)
        {agent.id, pid}
      end

    :erlang.garbage_collect()
    mem_after = :erlang.memory(:total)

    mem_per_agent = (mem_after - mem_before) / 50
    IO.puts("\n📊 Performance Baseline:")
    IO.puts("  Memory per agent: #{Float.round(mem_per_agent / 1024, 1)} KB")
    IO.puts("  Total for 50 agents: #{Float.round((mem_after - mem_before) / 1024, 1)} KB")

    # Baseline assertion: each agent should use less than 100KB
    assert mem_per_agent < 100_000, "Agent uses too much memory: #{mem_per_agent} bytes"

    # Cleanup
    for {_id, pid} <- agents do
      GenServer.stop(pid, :normal, 1000)
    end
  end
end
