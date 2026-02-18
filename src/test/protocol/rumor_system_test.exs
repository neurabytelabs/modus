defmodule Modus.Protocol.RumorSystemTest do
  use ExUnit.Case, async: false

  alias Modus.Protocol.RumorSystem

  setup do
    RumorSystem.init()
    try do :ets.delete_all_objects(:rumors) catch _, _ -> :ok end
    :ok
  end

  test "create_rumor stores a rumor with full accuracy" do
    rumor = RumorSystem.create_rumor("a1", "Alice", "There's a wolf near the forest", 100)
    assert rumor.accuracy == 1.0
    assert rumor.hops == 0
    assert rumor.originator_id == "a1"

    rumors = RumorSystem.get_rumors("a1")
    assert length(rumors) == 1
  end

  test "spread_rumor degrades accuracy" do
    rumor = RumorSystem.create_rumor("a1", "Alice", "Resources at the river", 100)
    {:ok, spread} = RumorSystem.spread_rumor("a1", "a2", rumor.id, 110)

    assert spread.hops == 1
    assert spread.accuracy < 1.0
    assert spread.accuracy > 0.5
    assert "a2" in spread.spread_chain
  end

  test "spread_rumor to agent who already knows is skipped" do
    rumor = RumorSystem.create_rumor("a1", "Alice", "Some info", 100)
    {:ok, _} = RumorSystem.spread_rumor("a1", "a2", rumor.id, 110)
    assert {:skipped, :already_known} = RumorSystem.spread_rumor("a1", "a2", rumor.id, 120)
  end

  test "rumor degrades through multiple hops" do
    rumor = RumorSystem.create_rumor("a1", "Alice", "Original fact", 100)

    {:ok, _} = RumorSystem.spread_rumor("a1", "a2", rumor.id, 110)
    {:ok, _} = RumorSystem.spread_rumor("a2", "a3", rumor.id, 120)
    {:ok, _} = RumorSystem.spread_rumor("a3", "a4", rumor.id, 130)
    {:ok, spread4} = RumorSystem.spread_rumor("a4", "a5", rumor.id, 140)

    assert spread4.hops == 4
    assert spread4.accuracy < 0.5
  end

  test "get_spreadable filters by accuracy threshold" do
    RumorSystem.create_rumor("a1", "Alice", "Good rumor", 100)
    spreadable = RumorSystem.get_spreadable("a1")
    assert length(spreadable) == 1
  end

  test "format_for_context returns formatted string" do
    RumorSystem.create_rumor("a1", "Alice", "There's gold in the hills", 100)
    context = RumorSystem.format_for_context("a1")
    assert context =~ "gold"
    assert context =~ "100%"
  end
end
