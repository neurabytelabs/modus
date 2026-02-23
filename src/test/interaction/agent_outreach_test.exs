defmodule Modus.Interaction.AgentOutreachTest do
  use ExUnit.Case, async: false

  alias Modus.Interaction.AgentOutreach
  alias Modus.Mind.Trust

  setup do
    Trust.init()
    Trust.reset()
    AgentOutreach.init()
    AgentOutreach.reset()
    :ok
  end

  describe "check_outreach/2" do
    test "returns nil on non-interval tick" do
      agent = %{id: "a1", name: "Test", conatus_energy: 0.1, affect_state: :neutral}
      assert AgentOutreach.check_outreach(agent, 3) == nil
    end

    test "triggers help request when energy low" do
      agent = %{id: "a1", name: "Ada", conatus_energy: 0.2, affect_state: :neutral}
      result = AgentOutreach.check_outreach(agent, 50)
      assert result.type == :help_request
      assert result.message =~ "Ada"
    end

    test "triggers fear message" do
      agent = %{id: "a2", name: "Bob", conatus_energy: 0.8, affect_state: :fear}
      result = AgentOutreach.check_outreach(agent, 100)
      assert result.type == :fear
      assert result.message =~ "Korkuyorum"
    end

    test "respects cooldown" do
      agent = %{id: "a1", name: "Ada", conatus_energy: 0.1, affect_state: :neutral}
      AgentOutreach.check_outreach(agent, 50)
      assert AgentOutreach.check_outreach(agent, 100) == nil
    end
  end

  describe "pending_messages/0" do
    test "returns pending messages" do
      agent = %{id: "a1", name: "Ada", conatus_energy: 0.1, affect_state: :neutral}
      AgentOutreach.check_outreach(agent, 50)
      assert length(AgentOutreach.pending_messages()) == 1
    end
  end
end
