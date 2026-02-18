defmodule Modus.Mind.Cerebro.AgentConversationTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Cerebro.{AgentConversation, SocialNetwork}

  setup do
    SocialNetwork.init()
    AgentConversation.init()
    Modus.Mind.AffectMemory.init()
    :ets.delete_all_objects(:social_network)
    :ets.delete_all_objects(:conversation_cooldowns)
    :ok
  end

  defp make_agent(overrides \\ %{}) do
    Map.merge(
      %{
        id: "agent_#{:rand.uniform(10000)}",
        name: "TestAgent",
        occupation: :explorer,
        position: {10, 10},
        personality: %{
          openness: 0.5,
          conscientiousness: 0.5,
          extraversion: 0.7,
          agreeableness: 0.6,
          neuroticism: 0.3
        },
        needs: %{hunger: 30.0, social: 60.0, rest: 70.0, shelter: 70.0},
        conatus_energy: 0.7,
        affect_state: :neutral,
        current_action: :talking,
        alive?: true
      },
      overrides
    )
  end

  test "skipped when conatus too low" do
    agent = make_agent(%{conatus_energy: 0.2})
    assert :skipped == AgentConversation.maybe_converse(agent, ["other"], 100)
  end

  test "skipped when no nearby agents" do
    agent = make_agent()
    assert :skipped == AgentConversation.maybe_converse(agent, [], 100)
  end

  test "build_conversation_prompt includes names and affect" do
    a1 = make_agent(%{name: "Emre", affect_state: :joy})
    a2 = make_agent(%{name: "Selin", affect_state: :sadness})
    prompt = AgentConversation.build_conversation_prompt(a1, a2, nil)
    assert prompt =~ "Emre"
    assert prompt =~ "Selin"
    assert prompt =~ "joy"
  end

  test "build_conversation_prompt includes relationship context" do
    a1 = make_agent(%{name: "A"})
    a2 = make_agent(%{name: "B"})
    rel = %{type: :friend, strength: 0.6, last_interaction: 0, convo_count: 5}
    prompt = AgentConversation.build_conversation_prompt(a1, a2, rel)
    assert prompt =~ "friends"
  end

  test "cooldown prevents spam" do
    agent = make_agent(%{id: "a1"})
    # Simulate cooldown entry
    :ets.insert(:conversation_cooldowns, {{"a1", "a2"}, 100})
    # At tick 120, still in cooldown (< 50 ticks)
    assert :skipped == AgentConversation.maybe_converse(agent, ["a2"], 120)
  end
end
