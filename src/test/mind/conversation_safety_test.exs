defmodule Modus.Mind.Cerebro.AgentConversationSafetyTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.Cerebro.AgentConversation

  describe "maybe_converse/3 nil safety" do
    test "returns :skipped for nil agent" do
      assert :skipped == AgentConversation.maybe_converse(nil, ["agent1"], 100)
    end

    test "returns :skipped for nil nearby_agent_ids" do
      assert :skipped == AgentConversation.maybe_converse(%{id: "test"}, nil, 100)
    end

    test "returns :skipped for agent with nil id" do
      assert :skipped == AgentConversation.maybe_converse(%{id: nil}, ["agent1"], 100)
    end
  end
end
