defmodule Modus.Mind.PerceptionTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Perception

  setup do
    # Ensure SocialNetwork ETS exists
    Modus.Mind.Cerebro.SocialNetwork.init()
    # Start Registry for agent lookups
    if Process.whereis(Modus.AgentRegistry) == nil do
      start_supervised!({Registry, keys: :unique, name: Modus.AgentRegistry})
    end
    :ok
  end

  defp make_agent do
    %Modus.Simulation.Agent{
      id: "test-agent-1",
      name: "TestAgent",
      position: {25, 25},
      personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5},
      needs: %{hunger: 40.0, social: 60.0, rest: 80.0, shelter: 70.0},
      occupation: :explorer,
      relationships: %{},
      memory: [],
      current_action: :exploring,
      conatus_score: 5.0,
      alive?: true,
      age: 0,
      conatus_energy: 0.7,
      affect_state: :neutral,
      affect_history: [],
      conatus_history: []
    }
  end

  describe "snapshot/1" do
    test "returns correct structure" do
      agent = make_agent()
      result = Perception.snapshot(agent)

      assert result.position == {25, 25}
      assert result.terrain == :grass
      assert is_list(result.nearby_agents)
      assert is_map(result.nearby_resources)
      assert is_float(result.conatus_energy)
      assert result.affect_state == :neutral
      assert is_map(result.needs)
      assert result.needs.hunger == 40.0
      assert result.current_action == :exploring
    end
  end

  describe "get_terrain_at/1" do
    test "returns :grass when World is not running" do
      assert Perception.get_terrain_at({10, 10}) == :grass
    end
  end
end
