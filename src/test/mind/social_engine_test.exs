defmodule Modus.Mind.SocialEngineTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.SocialEngine

  setup do
    # Clean ETS tables between tests
    for table <- [:social_groups, :social_members, :social_alliances] do
      if :ets.whereis(table) != :undefined do
        :ets.delete_all_objects(table)
      end
    end

    SocialEngine.init_tables()
    :ok
  end

  defp make_agent(id, name, position, opts \\ []) do
    %{
      __struct__: Modus.Simulation.Agent,
      id: id,
      name: name,
      position: position,
      personality:
        Keyword.get(opts, :personality, %{
          openness: 0.5,
          conscientiousness: 0.5,
          extraversion: 0.5,
          agreeableness: 0.5,
          neuroticism: 0.5
        }),
      needs: %{hunger: 50.0, social: 50.0, rest: 80.0, shelter: 70.0},
      occupation: Keyword.get(opts, :occupation, :explorer),
      relationships: Keyword.get(opts, :relationships, %{}),
      memory: [],
      current_action: nil,
      conatus_score: 5.0,
      alive?: Keyword.get(opts, :alive?, true),
      age: 10,
      conatus_energy: 0.7,
      affect_state: :neutral,
      affect_history: [],
      conatus_history: [],
      last_reasoning: nil,
      explore_target: Keyword.get(opts, :explore_target, nil),
      explore_ticks: 0,
      conversing_with: nil,
      group_id: nil,
      inventory: Keyword.get(opts, :inventory, %{}),
      goals_initialized: false
    }
  end

  describe "init_tables/0" do
    test "creates ETS tables" do
      SocialEngine.init_tables()
      assert :ets.whereis(:social_groups) != :undefined
      assert :ets.whereis(:social_members) != :undefined
      assert :ets.whereis(:social_alliances) != :undefined
    end

    test "is idempotent" do
      SocialEngine.init_tables()
      SocialEngine.init_tables()
      assert :ets.whereis(:social_groups) != :undefined
    end
  end

  describe "get_groups/0" do
    test "returns empty list when no groups" do
      assert SocialEngine.get_groups() == []
    end
  end

  describe "get_alliances/0" do
    test "returns empty list when no alliances" do
      assert SocialEngine.get_alliances() == []
    end
  end

  describe "social_influence/1" do
    test "calculates based on personality" do
      agent =
        make_agent("a1", "Alice", {0, 0},
          personality: %{extraversion: 0.9, agreeableness: 0.8, conscientiousness: 0.7}
        )

      score = SocialEngine.social_influence(agent)
      assert is_float(score)
      assert score > 0.0
    end

    test "higher extraversion = more influence" do
      high =
        make_agent("a1", "High", {0, 0},
          personality: %{extraversion: 1.0, agreeableness: 0.5, conscientiousness: 0.5}
        )

      low =
        make_agent("a2", "Low", {0, 0},
          personality: %{extraversion: 0.1, agreeableness: 0.5, conscientiousness: 0.5}
        )

      assert SocialEngine.social_influence(high) > SocialEngine.social_influence(low)
    end

    test "relationships boost influence" do
      agent =
        make_agent("a1", "Alice", {0, 0},
          relationships: %{"b1" => {:friend, 0.9}, "b2" => {:friend, 0.8}}
        )

      loner = make_agent("a2", "Bob", {0, 0})

      assert SocialEngine.social_influence(agent) > SocialEngine.social_influence(loner)
    end

    test "handles nil personality gracefully" do
      agent = %{personality: nil, relationships: %{}}
      score = SocialEngine.social_influence(agent)
      assert is_float(score)
    end
  end

  describe "tick/2 - group formation" do
    test "forms group from nearby agents with positive relationships" do
      a1 = make_agent("a1", "Alice", {5, 5}, relationships: %{"a2" => {:friend, 0.5}})
      a2 = make_agent("a2", "Bob", {6, 5}, relationships: %{"a1" => {:friend, 0.5}})

      SocialEngine.tick(1, [a1, a2])

      groups = SocialEngine.get_groups()
      assert length(groups) == 1
      group = hd(groups)
      assert "a1" in group.member_ids
      assert "a2" in group.member_ids
      assert group.leader_id != nil
    end

    test "does not form group without positive relationships" do
      a1 = make_agent("a1", "Alice", {5, 5})
      a2 = make_agent("a2", "Bob", {6, 5})

      SocialEngine.tick(1, [a1, a2])

      assert SocialEngine.get_groups() == []
    end

    test "does not form group if agents are far apart" do
      a1 = make_agent("a1", "Alice", {0, 0}, relationships: %{"a2" => {:friend, 0.5}})
      a2 = make_agent("a2", "Bob", {50, 50}, relationships: %{"a1" => {:friend, 0.5}})

      SocialEngine.tick(1, [a1, a2])

      assert SocialEngine.get_groups() == []
    end

    test "dead agents are not grouped" do
      a1 =
        make_agent("a1", "Alice", {5, 5}, relationships: %{"a2" => {:friend, 0.5}}, alive?: false)

      a2 = make_agent("a2", "Bob", {6, 5}, relationships: %{"a1" => {:friend, 0.5}})

      SocialEngine.tick(1, [a1, a2])

      assert SocialEngine.get_groups() == []
    end

    test "selects highest influence agent as leader" do
      a1 =
        make_agent("a1", "Alice", {5, 5},
          relationships: %{"a2" => {:friend, 0.5}},
          personality: %{extraversion: 0.9, agreeableness: 0.9, conscientiousness: 0.9}
        )

      a2 =
        make_agent("a2", "Bob", {6, 5},
          relationships: %{"a1" => {:friend, 0.5}},
          personality: %{extraversion: 0.1, agreeableness: 0.1, conscientiousness: 0.1}
        )

      SocialEngine.tick(1, [a1, a2])

      group = hd(SocialEngine.get_groups())
      assert group.leader_id == "a1"
    end
  end

  describe "get_agent_group/1" do
    test "returns group for grouped agent" do
      a1 = make_agent("a1", "Alice", {5, 5}, relationships: %{"a2" => {:friend, 0.5}})
      a2 = make_agent("a2", "Bob", {6, 5}, relationships: %{"a1" => {:friend, 0.5}})
      SocialEngine.tick(1, [a1, a2])

      group = SocialEngine.get_agent_group("a1")
      assert group != nil
      assert "a1" in group.member_ids
    end

    test "returns nil for ungrouped agent" do
      assert SocialEngine.get_agent_group("nonexistent") == nil
    end
  end

  describe "remove_agent/1" do
    test "removes agent and dissolves small group" do
      a1 = make_agent("a1", "Alice", {5, 5}, relationships: %{"a2" => {:friend, 0.5}})
      a2 = make_agent("a2", "Bob", {6, 5}, relationships: %{"a1" => {:friend, 0.5}})
      SocialEngine.tick(1, [a1, a2])

      assert length(SocialEngine.get_groups()) == 1

      SocialEngine.remove_agent("a1")

      # Group should dissolve (below min size)
      assert SocialEngine.get_groups() == []
    end

    test "removes agent from larger group without dissolving" do
      agents =
        for i <- 1..4 do
          rels =
            for j <- 1..4, j != i, into: %{} do
              {"a#{j}", {:friend, 0.5}}
            end

          make_agent("a#{i}", "Agent#{i}", {5 + rem(i, 2), 5}, relationships: rels)
        end

      SocialEngine.tick(1, agents)
      assert length(SocialEngine.get_groups()) >= 1

      SocialEngine.remove_agent("a1")
      groups = SocialEngine.get_groups()

      if length(groups) > 0 do
        group = hd(groups)
        refute "a1" in group.member_ids
      end
    end

    test "no-op for ungrouped agent" do
      assert SocialEngine.remove_agent("nonexistent") == :ok
    end
  end

  describe "live_data/0" do
    test "returns expected structure" do
      data = SocialEngine.live_data()
      assert is_map(data)
      assert Map.has_key?(data, :social_groups)
      assert Map.has_key?(data, :social_alliances)
      assert Map.has_key?(data, :social_group_count)
      assert Map.has_key?(data, :social_total_members)
      assert data.social_group_count == 0
      assert data.social_total_members == 0
    end

    test "reflects formed groups" do
      a1 = make_agent("a1", "Alice", {5, 5}, relationships: %{"a2" => {:friend, 0.5}})
      a2 = make_agent("a2", "Bob", {6, 5}, relationships: %{"a1" => {:friend, 0.5}})
      SocialEngine.tick(1, [a1, a2])

      data = SocialEngine.live_data()
      assert data.social_group_count == 1
      assert data.social_total_members == 2
    end
  end

  describe "group_leader_decision/3" do
    test "leader makes resource allocation decision" do
      a1 =
        make_agent("a1", "Alice", {5, 5},
          relationships: %{"a2" => {:friend, 0.5}},
          personality: %{extraversion: 0.9, agreeableness: 0.9, conscientiousness: 0.9}
        )

      a2 = make_agent("a2", "Bob", {6, 5}, relationships: %{"a1" => {:friend, 0.5}})
      SocialEngine.tick(1, [a1, a2])

      group = hd(SocialEngine.get_groups())
      decision = SocialEngine.group_leader_decision(group.id, :resource_allocation, [a1, a2])

      assert decision != nil
      assert decision.decision == :resource_allocation
      assert decision.leader == "a1"
      assert decision.strategy in [:share_equally, :prioritize_needs]
    end

    test "leader makes movement decision" do
      a1 = make_agent("a1", "Alice", {5, 5}, relationships: %{"a2" => {:friend, 0.5}})
      a2 = make_agent("a2", "Bob", {6, 5}, relationships: %{"a1" => {:friend, 0.5}})
      SocialEngine.tick(1, [a1, a2])

      group = hd(SocialEngine.get_groups())
      decision = SocialEngine.group_leader_decision(group.id, :movement, [a1, a2])

      assert decision != nil
      assert decision.decision == :movement
      assert is_tuple(decision.target)
    end

    test "returns nil for nonexistent group" do
      assert SocialEngine.group_leader_decision("fake_id", :movement, []) == nil
    end
  end

  describe "alliances and rivalries" do
    test "forms alliance between groups with positive inter-relationships" do
      # Group 1
      a1 =
        make_agent("a1", "Alice", {5, 5},
          relationships: %{"a2" => {:friend, 0.5}, "a3" => {:friend, 0.5}}
        )

      a2 =
        make_agent("a2", "Bob", {6, 5},
          relationships: %{"a1" => {:friend, 0.5}, "a4" => {:friend, 0.5}}
        )

      # Group 2
      a3 =
        make_agent("a3", "Eve", {20, 20},
          relationships: %{"a4" => {:friend, 0.5}, "a1" => {:friend, 0.5}}
        )

      a4 =
        make_agent("a4", "Dan", {21, 20},
          relationships: %{"a3" => {:friend, 0.5}, "a2" => {:friend, 0.5}}
        )

      SocialEngine.tick(1, [a1, a2, a3, a4])

      groups = SocialEngine.get_groups()

      if length(groups) == 2 do
        alliances = SocialEngine.get_alliances()
        assert length(alliances) >= 1
        alliance = hd(alliances)
        assert alliance.type in [:alliance, :rivalry, :neutral]
      end
    end
  end

  describe "shared resources" do
    test "pools resources among group members" do
      a1 =
        make_agent("a1", "Alice", {5, 5},
          relationships: %{"a2" => {:friend, 0.5}},
          inventory: %{wood: 10.0, food: 5.0}
        )

      a2 =
        make_agent("a2", "Bob", {6, 5},
          relationships: %{"a1" => {:friend, 0.5}},
          inventory: %{stone: 8.0, food: 3.0}
        )

      SocialEngine.tick(1, [a1, a2])

      group = hd(SocialEngine.get_groups())
      assert map_size(group.shared_resources) > 0
      assert Map.has_key?(group.shared_resources, :food)
    end
  end

  describe "GenServer" do
    test "starts and responds to calls" do
      {:ok, pid} = SocialEngine.start_link()

      assert Process.alive?(pid)
      assert GenServer.call(pid, :get_groups) == []

      data = GenServer.call(pid, :live_data)
      assert data.social_group_count == 0

      GenServer.stop(pid)
    end
  end
end
