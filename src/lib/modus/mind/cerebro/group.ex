defmodule Modus.Mind.Cerebro.Group do
  @moduledoc """
  Group — Agent groups/teams with collective behavior.
  Spinoza: *Societas* — social bonds and collective action.

  Groups are stored in ETS. A group has a leader and up to 3 members (max 4 total).
  Leaders decide, members follow. Groups move together and share a color halo.
  """

  @table :agent_groups
  @member_index :agent_group_membership
  @max_members 4
  @min_friendship_to_group 0.5

  alias Modus.Mind.Cerebro.SocialNetwork

  @type group :: %{
          id: String.t(),
          leader_id: String.t(),
          member_ids: [String.t()],
          color: integer(),
          formed_at: integer(),
          name: String.t()
        }

  @group_colors [
    # red
    0xFF6B6B,
    # teal
    0x4ECDC4,
    # yellow
    0xFFE66D,
    # purple
    0xA855F7,
    # cyan
    0x06B6D4,
    # orange
    0xF97316,
    # green
    0x22C55E,
    # pink
    0xEC4899
  ]

  @group_names [
    "Wanderers",
    "Seekers",
    "Builders",
    "Guardians",
    "Dreamers",
    "Foragers",
    "Scouts",
    "Sages"
  ]

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@member_index) == :undefined do
      :ets.new(@member_index, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Form a new group with leader and initial members. Returns {:ok, group} or {:error, reason}."
  def form_group(leader_id, member_ids, tick \\ 0) do
    # Validate: no one already in a group
    all_ids = [leader_id | member_ids]

    if length(all_ids) > @max_members do
      {:error, :too_many_members}
    else
      already_grouped = Enum.any?(all_ids, &get_agent_group/1)

      if already_grouped do
        {:error, :already_in_group}
      else
        # Validate friendship strength
        weak =
          Enum.any?(member_ids, fn mid ->
            rel = SocialNetwork.get_relationship(leader_id, mid)
            rel == nil or Map.get(rel, :strength, 0) < @min_friendship_to_group
          end)

        if weak do
          {:error, :insufficient_friendship}
        else
          group_id = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
          color = Enum.random(@group_colors)
          name = Enum.random(@group_names)

          group = %{
            id: group_id,
            leader_id: leader_id,
            member_ids: member_ids,
            color: color,
            formed_at: tick,
            name: name
          }

          :ets.insert(@table, {group_id, group})
          # Index each member
          Enum.each(all_ids, fn aid ->
            :ets.insert(@member_index, {aid, group_id})
          end)

          # Update social network with group relationship
          Enum.each(member_ids, fn mid ->
            SocialNetwork.update_relationship(leader_id, mid, :shared_danger)
          end)

          {:ok, group}
        end
      end
    end
  end

  @doc "Get the group an agent belongs to, or nil."
  def get_agent_group(agent_id) do
    case :ets.lookup(@member_index, agent_id) do
      [{^agent_id, group_id}] ->
        case :ets.lookup(@table, group_id) do
          [{^group_id, group}] ->
            group

          [] ->
            :ets.delete(@member_index, agent_id)
            nil
        end

      [] ->
        nil
    end
  end

  @doc "Get group by id."
  def get_group(group_id) do
    case :ets.lookup(@table, group_id) do
      [{^group_id, group}] -> group
      [] -> nil
    end
  end

  @doc "List all groups."
  def list_groups do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, group} -> group end)
  end

  @doc "Remove an agent from their group. If leader leaves, group dissolves."
  def leave_group(agent_id) do
    case get_agent_group(agent_id) do
      nil ->
        :ok

      group ->
        if group.leader_id == agent_id do
          dissolve_group(group.id)
        else
          new_members = List.delete(group.member_ids, agent_id)
          updated = %{group | member_ids: new_members}
          :ets.insert(@table, {group.id, updated})
          :ets.delete(@member_index, agent_id)

          # Dissolve if only leader remains
          if new_members == [] do
            dissolve_group(group.id)
          end
        end

        :ok
    end
  end

  @doc "Dissolve a group entirely."
  def dissolve_group(group_id) do
    case get_group(group_id) do
      nil ->
        :ok

      group ->
        all_ids = [group.leader_id | group.member_ids]

        Enum.each(all_ids, fn aid ->
          :ets.delete(@member_index, aid)
        end)

        :ets.delete(@table, group_id)
        :ok
    end
  end

  @doc "Check if two agents are in the same group."
  def same_group?(id1, id2) do
    case :ets.lookup(@member_index, id1) do
      [{^id1, gid1}] ->
        case :ets.lookup(@member_index, id2) do
          [{^id2, gid2}] -> gid1 == gid2
          [] -> false
        end

      [] ->
        false
    end
  end

  @doc "Get leader's target position for group movement. Members should follow."
  def get_group_target(agent_id) do
    case get_agent_group(agent_id) do
      nil ->
        nil

      group ->
        if group.leader_id == agent_id do
          # Leader decides on their own
          nil
        else
          # Follow leader — get leader position from registry
          case Registry.lookup(Modus.AgentRegistry, group.leader_id) do
            [{_pid, {lx, ly, true}}] -> {lx, ly}
            _ -> nil
          end
        end
    end
  end

  @doc """
  Try to auto-form groups from strong friendships.
  Called periodically (e.g., every 200 ticks).
  """
  def maybe_form_groups(agent_ids, tick) do
    # Find agents not in groups with strong friendships
    ungrouped = Enum.reject(agent_ids, &get_agent_group/1)

    Enum.reduce(ungrouped, [], fn agent_id, formed ->
      if get_agent_group(agent_id) do
        formed
      else
        friends =
          SocialNetwork.get_friends(agent_id, @min_friendship_to_group)
          |> Enum.reject(fn f -> get_agent_group(f.id) != nil end)
          |> Enum.take(@max_members - 1)

        if length(friends) >= 1 do
          member_ids = Enum.map(friends, & &1.id)

          case form_group(agent_id, member_ids, tick) do
            {:ok, group} -> [group | formed]
            _ -> formed
          end
        else
          formed
        end
      end
    end)
  end

  @doc "Clean up dead agents from groups."
  def cleanup_dead(dead_agent_ids) do
    Enum.each(dead_agent_ids, &leave_group/1)
  end
end
