defmodule Modus.Mind.TrustTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Trust

  setup do
    Trust.init()
    Trust.reset()
    :ok
  end

  describe "get_trust/1" do
    test "returns 0 for unknown agent" do
      assert Trust.get_trust("unknown-agent") == 0
    end

    test "returns stored trust value" do
      Trust.update_trust("agent-1", 30)
      assert Trust.get_trust("agent-1") == 30
    end
  end

  describe "update_trust/2" do
    test "increases trust" do
      assert Trust.update_trust("agent-1", 10) == 10
      assert Trust.update_trust("agent-1", 5) == 15
    end

    test "clamps at 100" do
      Trust.update_trust("agent-1", 90)
      assert Trust.update_trust("agent-1", 20) == 100
    end

    test "clamps at 0" do
      assert Trust.update_trust("agent-1", -10) == 0
    end

    test "handles negative delta" do
      Trust.update_trust("agent-1", 50)
      assert Trust.update_trust("agent-1", -5) == 45
    end
  end

  describe "trust_level/1" do
    test "stranger for 0-24" do
      assert Trust.trust_level("new") == :stranger
    end

    test "known for 25-49" do
      Trust.update_trust("a", 30)
      assert Trust.trust_level("a") == :known
    end

    test "trusted for 50-74" do
      Trust.update_trust("a", 60)
      assert Trust.trust_level("a") == :trusted
    end

    test "bonded for 75-100" do
      Trust.update_trust("a", 80)
      assert Trust.trust_level("a") == :bonded
    end
  end

  describe "context_for_prompt/1" do
    test "returns context string with level info" do
      Trust.update_trust("agent-1", 60)
      context = Trust.context_for_prompt("agent-1")
      assert context =~ "trusted"
      assert context =~ "60/100"
    end
  end
end
