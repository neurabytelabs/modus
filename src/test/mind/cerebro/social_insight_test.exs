defmodule Modus.Mind.Cerebro.SocialInsightTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.Cerebro.{SocialInsight, SocialNetwork}

  setup do
    SocialNetwork.init()
    :ok
  end

  describe "describe_relationships/1" do
    test "returns empty message when no friends" do
      result = SocialInsight.describe_relationships("lonely_agent")
      assert result == "You don't know anyone yet."
    end

    test "returns relationship descriptions when friends exist" do
      # Add a relationship
      SocialNetwork.update_relationship("agent_a", "agent_b", :conversation_joy)
      SocialNetwork.update_relationship("agent_a", "agent_b", :conversation_joy)
      SocialNetwork.update_relationship("agent_a", "agent_b", :conversation_joy)

      result = SocialInsight.describe_relationships("agent_a")
      # Should mention the relationship (though agent name will be "Bilinmeyen" without real agent)
      assert is_binary(result)
      assert result != "You don't know anyone yet."
    end
  end

  describe "describe_relationship/3" do
    test "unknown relationship" do
      result = SocialInsight.describe_relationship("x", "y", "Ali")
      assert result == "You haven't met Ali before."
    end

    test "known relationship" do
      SocialNetwork.update_relationship("p", "q", :conversation_joy)
      result = SocialInsight.describe_relationship("p", "q", "Ali")
      assert is_binary(result)
      assert String.contains?(result, "Ali")
    end
  end
end
