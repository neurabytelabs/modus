defmodule Modus.Protocol.InformationSharingTest do
  use ExUnit.Case, async: false

  alias Modus.Protocol.InformationSharing

  setup do
    InformationSharing.init()
    try do :ets.delete_all_objects(:shared_knowledge) catch _, _ -> :ok end
    :ok
  end

  test "record_knowledge stores spatial knowledge" do
    :ok = InformationSharing.record_knowledge("a1", :resource_location, {10, 20}, %{resource: :wood})
    knowledge = InformationSharing.get_knowledge("a1")
    assert length(knowledge) == 1
    assert hd(knowledge).type == :resource_location
    assert hd(knowledge).accuracy == 1.0
  end

  test "share_knowledge transfers knowledge with degradation" do
    InformationSharing.record_knowledge("a1", :danger_zone, {5, 5})
    {:ok, count} = InformationSharing.share_knowledge("a1", "a2", 0.8)
    assert count == 1

    a2_knowledge = InformationSharing.get_knowledge("a2")
    assert length(a2_knowledge) == 1
    assert hd(a2_knowledge).accuracy < 1.0
    assert hd(a2_knowledge).source == :shared
  end

  test "share_knowledge skips already known info" do
    InformationSharing.record_knowledge("a1", :resource_location, {10, 20})
    InformationSharing.record_knowledge("a2", :resource_location, {10, 20})

    {:ok, count} = InformationSharing.share_knowledge("a1", "a2", 0.5)
    assert count == 0
  end

  test "higher trust means less degradation" do
    InformationSharing.record_knowledge("a1", :safe_area, {30, 30})
    {:ok, _} = InformationSharing.share_knowledge("a1", "high_trust", 1.0)
    {:ok, _} = InformationSharing.share_knowledge("a1", "low_trust", 0.1)

    high = hd(InformationSharing.get_knowledge("high_trust"))
    low = hd(InformationSharing.get_knowledge("low_trust"))
    assert high.accuracy > low.accuracy
  end

  test "get_knowledge_by_type filters correctly" do
    InformationSharing.record_knowledge("a1", :resource_location, {10, 20})
    InformationSharing.record_knowledge("a1", :danger_zone, {5, 5})

    resources = InformationSharing.get_knowledge_by_type("a1", :resource_location)
    assert length(resources) == 1
    assert hd(resources).type == :resource_location
  end

  test "format_for_context returns formatted string" do
    InformationSharing.record_knowledge("a1", :danger_zone, {5, 5})
    context = InformationSharing.format_for_context("a1")
    assert context =~ "Danger"
    assert context =~ "(5,5)"
  end

  test "format_for_context returns empty for unknown agent" do
    assert InformationSharing.format_for_context("unknown") == ""
  end
end
