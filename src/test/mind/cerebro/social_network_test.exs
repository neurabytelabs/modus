defmodule Modus.Mind.Cerebro.SocialNetworkTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Cerebro.SocialNetwork

  setup do
    SocialNetwork.init()
    # Clear table between tests
    :ets.delete_all_objects(:social_network)
    :ok
  end

  test "canonical key ordering" do
    SocialNetwork.update_relationship("b", "a", :conversation_neutral)
    assert SocialNetwork.get_relationship("a", "b") != nil
    assert SocialNetwork.get_relationship("b", "a") != nil
    # Same relationship
    assert SocialNetwork.get_relationship("a", "b").strength ==
             SocialNetwork.get_relationship("b", "a").strength
  end

  test "relationship strengthens on conversation" do
    SocialNetwork.update_relationship("a1", "a2", :conversation_joy)
    rel = SocialNetwork.get_relationship("a1", "a2")
    assert rel.strength == 0.08
    assert rel.convo_count == 1
  end

  test "relationship decays over time" do
    SocialNetwork.update_relationship("a1", "a2", :conversation_joy)
    SocialNetwork.decay_all(0.05)
    rel = SocialNetwork.get_relationship("a1", "a2")
    assert rel.strength == 0.08 - 0.05
  end

  test "type progresses with strength" do
    for _ <- 1..3 do
      SocialNetwork.update_relationship("a1", "a2", :conversation_joy)
    end

    rel = SocialNetwork.get_relationship("a1", "a2")
    assert rel.strength == 0.24
    assert rel.type == :acquaintance
  end

  test "get_friends filters by min_strength" do
    SocialNetwork.update_relationship("a1", "a2", :conversation_joy)
    # strength = 0.08, below default 0.3
    assert SocialNetwork.get_friends("a1") == []
    assert length(SocialNetwork.get_friends("a1", 0.05)) == 1
  end

  test "nil for unknown relationship" do
    assert SocialNetwork.get_relationship("x", "y") == nil
  end

  test "shared danger gives higher delta" do
    SocialNetwork.update_relationship("a1", "a2", :shared_danger)
    rel = SocialNetwork.get_relationship("a1", "a2")
    assert rel.strength == 0.10
  end
end
