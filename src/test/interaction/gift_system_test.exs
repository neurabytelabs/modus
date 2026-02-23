defmodule Modus.Interaction.GiftSystemTest do
  use ExUnit.Case, async: false

  alias Modus.Interaction.GiftSystem
  alias Modus.Mind.Trust

  setup do
    Trust.init()
    Trust.reset()
    GiftSystem.init()
    GiftSystem.reset()
    :ok
  end

  describe "give_gift/3" do
    test "valid gift increases trust by 3" do
      assert {:ok, 3} = GiftSystem.give_gift("player", "agent-1", "food")
      assert Trust.get_trust("agent-1") == 3
    end

    test "invalid resource returns error" do
      assert {:error, "invalid resource"} = GiftSystem.give_gift("player", "agent-1", "diamond")
    end

    test "gift is recorded in history" do
      GiftSystem.give_gift("player", "agent-1", "wood")
      history = GiftSystem.gift_history("agent-1")
      assert length(history) == 1
      assert hd(history).resource == "wood"
      assert hd(history).type == :gift
    end
  end

  describe "aid_agent/2" do
    test "aid increases trust by 2" do
      assert {:ok, :lowest_need, 2} = GiftSystem.aid_agent("player", "agent-1")
      assert Trust.get_trust("agent-1") == 2
    end

    test "aid is recorded in history" do
      GiftSystem.aid_agent("player", "agent-1")
      history = GiftSystem.gift_history("agent-1")
      assert length(history) == 1
      assert hd(history).type == :aid
    end
  end
end
