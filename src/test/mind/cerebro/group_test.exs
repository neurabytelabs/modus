defmodule Modus.Mind.Cerebro.GroupTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Cerebro.{Group, SocialNetwork}

  setup do
    Group.init()
    SocialNetwork.init()

    # Clear ETS tables
    :ets.delete_all_objects(:agent_groups)
    :ets.delete_all_objects(:agent_group_membership)
    :ets.delete_all_objects(:social_network)

    # Create strong friendships
    for _ <- 1..10 do
      SocialNetwork.update_relationship("agent_a", "agent_b", :shared_danger)
      SocialNetwork.update_relationship("agent_a", "agent_c", :shared_danger)
      SocialNetwork.update_relationship("agent_b", "agent_c", :shared_danger)
    end

    :ok
  end

  test "form_group creates a group with leader and members" do
    assert {:ok, group} = Group.form_group("agent_a", ["agent_b", "agent_c"], 100)
    assert group.leader_id == "agent_a"
    assert group.member_ids == ["agent_b", "agent_c"]
    assert group.color in [0xFF6B6B, 0x4ECDC4, 0xFFE66D, 0xA855F7, 0x06B6D4, 0xF97316, 0x22C55E, 0xEC4899]
    assert group.formed_at == 100
  end

  test "get_agent_group returns group for members" do
    {:ok, group} = Group.form_group("agent_a", ["agent_b"], 0)
    assert Group.get_agent_group("agent_a") == group
    assert Group.get_agent_group("agent_b") == group
    assert Group.get_agent_group("agent_unknown") == nil
  end

  test "same_group? detects agents in same group" do
    {:ok, _} = Group.form_group("agent_a", ["agent_b"], 0)
    assert Group.same_group?("agent_a", "agent_b")
    refute Group.same_group?("agent_a", "agent_c")
  end

  test "leave_group dissolves when leader leaves" do
    {:ok, group} = Group.form_group("agent_a", ["agent_b"], 0)
    Group.leave_group("agent_a")
    assert Group.get_group(group.id) == nil
    assert Group.get_agent_group("agent_b") == nil
  end

  test "leave_group removes member without dissolving" do
    {:ok, group} = Group.form_group("agent_a", ["agent_b", "agent_c"], 0)
    Group.leave_group("agent_c")
    updated = Group.get_group(group.id)
    assert updated != nil
    assert "agent_c" not in updated.member_ids
    assert Group.get_agent_group("agent_a") != nil
  end

  test "cannot join two groups" do
    {:ok, _} = Group.form_group("agent_a", ["agent_b"], 0)
    assert {:error, :already_in_group} = Group.form_group("agent_b", ["agent_c"], 0)
  end

  test "max members enforced" do
    assert {:error, :too_many_members} = Group.form_group("agent_a", ["agent_b", "agent_c", "d", "e"], 0)
  end

  test "insufficient friendship rejected" do
    # agent_d has no friendship with agent_a
    assert {:error, :insufficient_friendship} = Group.form_group("agent_a", ["agent_d"], 0)
  end

  test "list_groups returns all groups" do
    {:ok, _} = Group.form_group("agent_a", ["agent_b"], 0)
    assert length(Group.list_groups()) == 1
  end

  test "cleanup_dead removes dead agents from groups" do
    {:ok, _} = Group.form_group("agent_a", ["agent_b", "agent_c"], 0)
    Group.cleanup_dead(["agent_c"])
    group = Group.get_agent_group("agent_a")
    assert group != nil
    refute "agent_c" in group.member_ids
  end
end
