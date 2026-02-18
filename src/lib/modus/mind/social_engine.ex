defmodule Modus.Mind.SocialEngine do
  @moduledoc """
  SocialEngine — Social structures: clans, leadership, alliances, group identity.
  Spinoza: *Societas* — humans are social animals; together they thrive.

  Manages clan/tribe formation from proximity + positive relationships,
  leadership selection by social influence, group decisions, alliances/rivalries
  between groups, shared resources, and LLM-generated group names.

  All persistent state stored in ETS for lock-free concurrent reads.
  GenServer handles mutations (formation, dissolution, tick updates).
  """

  use GenServer
  require Logger

  @groups_table :social_groups
  @members_table :social_members
  @alliances_table :social_alliances

  @proximity_radius 5
  @min_relationship_strength 0.2
  @min_group_size 2
  @max_group_size 12
  @leadership_recalc_interval 10
  @alliance_threshold 0.3
  @rivalry_threshold -0.3
  @resource_share_rate 0.1

  # ── Types ──────────────────────────────────────────────

  @type group :: %{
          id: String.t(),
          name: String.t(),
          identity: String.t(),
          leader_id: String.t() | nil,
          member_ids: [String.t()],
          formed_tick: integer(),
          shared_resources: map(),
          motto: String.t() | nil
        }

  @type alliance :: %{
          group_a: String.t(),
          group_b: String.t(),
          type: :alliance | :rivalry | :neutral,
          strength: float(),
          since_tick: integer()
        }

  # ── Client API ─────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Initialize ETS tables (call without GenServer)."
  @spec init_tables() :: :ok
  def init_tables do
    tables = [
      {@groups_table, [:set, :public, :named_table, read_concurrency: true]},
      {@members_table, [:set, :public, :named_table, read_concurrency: true]},
      {@alliances_table, [:set, :public, :named_table, read_concurrency: true]}
    ]

    Enum.each(tables, fn {name, opts} ->
      if :ets.whereis(name) == :undefined, do: :ets.new(name, opts)
    end)

    :ok
  end

  @doc "Process a simulation tick — form groups, update leadership, handle alliances."
  @spec tick(integer(), [map()]) :: :ok
  def tick(tick, agents) do
    init_tables()
    form_groups(tick, agents)

    if rem(tick, @leadership_recalc_interval) == 0 do
      recalculate_leadership(agents)
    end

    update_alliances(tick, agents)
    share_group_resources(agents)
    :ok
  end

  @doc "Get all groups."
  @spec get_groups() :: [group()]
  def get_groups do
    init_tables()

    :ets.tab2list(@groups_table)
    |> Enum.map(fn {_id, group} -> group end)
  end

  @doc "Get group for a specific agent."
  @spec get_agent_group(String.t()) :: group() | nil
  def get_agent_group(agent_id) do
    init_tables()

    case :ets.lookup(@members_table, agent_id) do
      [{^agent_id, group_id}] ->
        case :ets.lookup(@groups_table, group_id) do
          [{^group_id, group}] -> group
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc "Get all alliances/rivalries."
  @spec get_alliances() :: [alliance()]
  def get_alliances do
    init_tables()

    :ets.tab2list(@alliances_table)
    |> Enum.map(fn {_key, alliance} -> alliance end)
  end

  @doc "Get social data for LiveView assigns."
  @spec live_data() :: map()
  def live_data do
    groups = get_groups()
    alliances = get_alliances()

    %{
      social_groups: groups,
      social_alliances: alliances,
      social_group_count: length(groups),
      social_total_members: groups |> Enum.map(&length(&1.member_ids)) |> Enum.sum()
    }
  end

  @doc "Get the leader agent for a group decision."
  @spec group_leader_decision(String.t(), atom(), [map()]) :: map() | nil
  def group_leader_decision(group_id, decision_type, agents) do
    case :ets.lookup(@groups_table, group_id) do
      [{^group_id, group}] ->
        leader = Enum.find(agents, &(&1.id == group.leader_id))

        if leader do
          case decision_type do
            :resource_allocation ->
              %{
                decision: :resource_allocation,
                leader: leader.id,
                group: group_id,
                strategy: choose_resource_strategy(leader)
              }

            :movement ->
              %{
                decision: :movement,
                leader: leader.id,
                group: group_id,
                target: choose_movement_target(leader, group, agents)
              }

            _ ->
              %{decision: decision_type, leader: leader.id, group: group_id, strategy: :default}
          end
        end

      _ ->
        nil
    end
  end

  @doc "Remove an agent from their group."
  @spec remove_agent(String.t()) :: :ok
  def remove_agent(agent_id) do
    init_tables()

    case :ets.lookup(@members_table, agent_id) do
      [{^agent_id, group_id}] ->
        :ets.delete(@members_table, agent_id)

        case :ets.lookup(@groups_table, group_id) do
          [{^group_id, group}] ->
            new_members = List.delete(group.member_ids, agent_id)

            if length(new_members) < @min_group_size do
              dissolve_group(group_id)
            else
              new_leader =
                if group.leader_id == agent_id,
                  do: List.first(new_members),
                  else: group.leader_id

              :ets.insert(
                @groups_table,
                {group_id, %{group | member_ids: new_members, leader_id: new_leader}}
              )
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end

    :ok
  end

  # ── GenServer Callbacks ────────────────────────────────

  @impl true
  def init(_opts) do
    init_tables()
    {:ok, %{last_tick: 0}}
  end

  @impl true
  def handle_call({:tick, tick, agents}, _from, state) do
    tick(tick, agents)
    {:reply, :ok, %{state | last_tick: tick}}
  end

  @impl true
  def handle_call(:get_groups, _from, state) do
    {:reply, get_groups(), state}
  end

  @impl true
  def handle_call(:live_data, _from, state) do
    {:reply, live_data(), state}
  end

  @impl true
  def handle_cast({:tick, tick, agents}, state) do
    tick(tick, agents)
    {:noreply, %{state | last_tick: tick}}
  end

  # ── Group Formation ────────────────────────────────────

  defp form_groups(tick, agents) do
    ungrouped =
      agents
      |> Enum.filter(fn a ->
        a.alive? != false and :ets.lookup(@members_table, a.id) == []
      end)

    clusters = find_clusters(ungrouped)

    Enum.each(clusters, fn cluster ->
      if length(cluster) >= @min_group_size do
        create_group(tick, cluster)
      end
    end)
  end

  defp find_clusters(agents) do
    # Simple proximity + relationship clustering
    agents
    |> Enum.reduce([], fn agent, clusters ->
      matching_cluster =
        Enum.find_index(clusters, fn cluster ->
          Enum.any?(cluster, fn member ->
            nearby?(agent, member) and positive_relationship?(agent, member)
          end)
        end)

      case matching_cluster do
        nil -> clusters ++ [[agent]]
        idx -> List.update_at(clusters, idx, &(&1 ++ [agent]))
      end
    end)
    |> Enum.filter(&(length(&1) >= @min_group_size))
    |> Enum.map(&Enum.take(&1, @max_group_size))
  end

  defp nearby?(a1, a2) do
    {x1, y1} = a1.position || {0, 0}
    {x2, y2} = a2.position || {0, 0}
    abs(x1 - x2) + abs(y1 - y2) <= @proximity_radius
  end

  defp positive_relationship?(a1, a2) do
    rels = a1.relationships || %{}

    case Map.get(rels, a2.id) do
      nil -> false
      {_type, strength} when is_number(strength) -> strength >= @min_relationship_strength
      strength when is_number(strength) -> strength >= @min_relationship_strength
      _ -> false
    end
  end

  defp create_group(tick, members) do
    group_id = "grp_#{:erlang.unique_integer([:positive])}"
    member_ids = Enum.map(members, & &1.id)
    leader = select_leader(members)

    group = %{
      id: group_id,
      name: generate_group_name(members),
      identity: generate_group_identity(members),
      leader_id: leader && leader.id,
      member_ids: member_ids,
      formed_tick: tick,
      shared_resources: %{},
      motto: nil
    }

    :ets.insert(@groups_table, {group_id, group})
    Enum.each(member_ids, &:ets.insert(@members_table, {&1, group_id}))

    # Try async LLM name generation
    spawn(fn -> generate_llm_group_name(group_id, members) end)

    Logger.info(
      "[SocialEngine] Group '#{group.name}' formed with #{length(member_ids)} members, leader: #{leader && leader.name}"
    )

    group
  end

  # ── Leadership ─────────────────────────────────────────

  defp select_leader(members) do
    Enum.max_by(members, &social_influence/1, fn -> nil end)
  end

  @doc "Calculate social influence score for an agent."
  @spec social_influence(map()) :: float()
  def social_influence(agent) do
    personality = agent.personality || %{}
    relationships = agent.relationships || %{}

    extraversion = ensure_float(Map.get(personality, :extraversion, 0.5))
    agreeableness = ensure_float(Map.get(personality, :agreeableness, 0.5))
    conscientiousness = ensure_float(Map.get(personality, :conscientiousness, 0.5))

    relationship_score =
      relationships
      |> Map.values()
      |> Enum.map(fn
        {_type, strength} when is_number(strength) -> max(0, ensure_float(strength))
        strength when is_number(strength) -> max(0, ensure_float(strength))
        _ -> 0.0
      end)
      |> Enum.sum()

    rel_count = max(1, map_size(relationships))
    avg_rel = relationship_score / rel_count

    extraversion * 0.35 + agreeableness * 0.25 + conscientiousness * 0.2 + avg_rel * 0.2
  end

  defp recalculate_leadership(agents) do
    :ets.tab2list(@groups_table)
    |> Enum.each(fn {group_id, group} ->
      group_agents = Enum.filter(agents, &(&1.id in group.member_ids))

      if length(group_agents) > 0 do
        new_leader = select_leader(group_agents)

        if new_leader && new_leader.id != group.leader_id do
          :ets.insert(@groups_table, {group_id, %{group | leader_id: new_leader.id}})

          Logger.debug("[SocialEngine] Leadership change in '#{group.name}': #{new_leader.name}")
        end
      end
    end)
  end

  # ── Group Decisions ────────────────────────────────────

  defp choose_resource_strategy(leader) do
    personality = leader.personality || %{}
    agreeableness = ensure_float(Map.get(personality, :agreeableness, 0.5))

    if agreeableness > 0.6, do: :share_equally, else: :prioritize_needs
  end

  defp choose_movement_target(leader, group, agents) do
    group_agents = Enum.filter(agents, &(&1.id in group.member_ids))

    # Average position of group
    positions = Enum.map(group_agents, &(&1.position || {0, 0}))
    count = max(1, length(positions))
    avg_x = Enum.map(positions, &elem(&1, 0)) |> Enum.sum() |> div(count)
    avg_y = Enum.map(positions, &elem(&1, 1)) |> Enum.sum() |> div(count)

    # Leader's explore target or center of group
    leader.explore_target || {avg_x, avg_y}
  end

  # ── Alliances & Rivalries ──────────────────────────────

  defp update_alliances(tick, agents) do
    groups = :ets.tab2list(@groups_table) |> Enum.map(fn {_id, g} -> g end)

    for g1 <- groups, g2 <- groups, g1.id < g2.id do
      score = inter_group_relationship(g1, g2, agents)
      key = {g1.id, g2.id}

      type =
        cond do
          score >= @alliance_threshold -> :alliance
          score <= @rivalry_threshold -> :rivalry
          true -> :neutral
        end

      existing =
        case :ets.lookup(@alliances_table, key) do
          [{^key, a}] -> a
          _ -> nil
        end

      since = if existing && existing.type == type, do: existing.since_tick, else: tick

      alliance = %{
        group_a: g1.id,
        group_b: g2.id,
        type: type,
        strength: ensure_float(score),
        since_tick: since
      }

      :ets.insert(@alliances_table, {key, alliance})
    end
  end

  defp inter_group_relationship(g1, g2, agents) do
    agents_map = Map.new(agents, &{&1.id, &1})

    scores =
      for m1 <- g1.member_ids, m2 <- g2.member_ids do
        a1 = Map.get(agents_map, m1)

        if a1 do
          rels = a1.relationships || %{}

          case Map.get(rels, m2) do
            {_type, s} when is_number(s) -> ensure_float(s)
            s when is_number(s) -> ensure_float(s)
            _ -> 0.0
          end
        else
          0.0
        end
      end

    count = max(1, length(scores))
    Enum.sum(scores) / count
  end

  # ── Shared Resources ──────────────────────────────────

  defp share_group_resources(agents) do
    agents_map = Map.new(agents, &{&1.id, &1})

    :ets.tab2list(@groups_table)
    |> Enum.each(fn {group_id, group} ->
      group_agents =
        Enum.map(group.member_ids, &Map.get(agents_map, &1)) |> Enum.reject(&is_nil/1)

      if length(group_agents) >= 2 do
        # Calculate pooled resources
        all_inventories = Enum.map(group_agents, &(Map.get(&1, :inventory) || %{}))

        pooled =
          Enum.reduce(all_inventories, %{}, fn inv, acc ->
            Enum.reduce(inv, acc, fn {k, v}, a ->
              Map.update(
                a,
                k,
                ensure_float(v) * @resource_share_rate,
                &(&1 + ensure_float(v) * @resource_share_rate)
              )
            end)
          end)

        :ets.insert(@groups_table, {group_id, %{group | shared_resources: pooled}})
      end
    end)
  end

  # ── Group Name Generation ──────────────────────────────

  defp generate_group_name(members) do
    names = Enum.map(members, & &1.name) |> Enum.take(3)
    prefixes = ~w(The United Brave Noble Free Wild Sacred Iron Storm)
    suffixes = ~w(Clan Pack Tribe Band Circle Lodge Fellowship)
    prefix = Enum.random(prefixes)
    suffix = Enum.random(suffixes)
    "#{prefix} #{suffix} of #{List.first(names) || "Unknown"}"
  end

  defp generate_group_identity(members) do
    occupations = Enum.map(members, &to_string(&1.occupation || :unknown)) |> Enum.uniq()
    "A group of #{length(members)} (#{Enum.join(occupations, ", ")})"
  end

  defp generate_llm_group_name(group_id, members) do
    names = Enum.map(members, & &1.name)
    occupations = Enum.map(members, &to_string(&1.occupation || :unknown)) |> Enum.uniq()

    prompt = """
    Generate a creative clan/tribe name and a short motto (max 10 words) for a group of #{length(members)} people.
    Members: #{Enum.join(names, ", ")}
    Occupations: #{Enum.join(occupations, ", ")}

    Respond in exactly this format:
    NAME: <clan name>
    MOTTO: <short motto>
    """

    case safe_llm_call(prompt) do
      {:ok, response} ->
        name = extract_field(response, "NAME") || generate_group_name(members)
        motto = extract_field(response, "MOTTO")

        case :ets.lookup(@groups_table, group_id) do
          [{^group_id, group}] ->
            :ets.insert(@groups_table, {group_id, %{group | name: name, motto: motto}})

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp safe_llm_call(prompt) do
    if Code.ensure_loaded?(Modus.Intelligence.LlmProvider) do
      try do
        Modus.Intelligence.LlmProvider.chat(prompt, "social_engine")
      rescue
        _ -> {:error, :llm_unavailable}
      catch
        :exit, _ -> {:error, :llm_unavailable}
      end
    else
      {:error, :llm_not_loaded}
    end
  end

  defp extract_field(text, field) do
    case Regex.run(~r/#{field}:\s*(.+)/i, text) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  # ── Group Dissolution ──────────────────────────────────

  defp dissolve_group(group_id) do
    case :ets.lookup(@groups_table, group_id) do
      [{^group_id, group}] ->
        Enum.each(group.member_ids, &:ets.delete(@members_table, &1))
        :ets.delete(@groups_table, group_id)

        # Clean up alliances involving this group
        :ets.tab2list(@alliances_table)
        |> Enum.each(fn {key, alliance} ->
          if alliance.group_a == group_id or alliance.group_b == group_id do
            :ets.delete(@alliances_table, key)
          end
        end)

        Logger.info("[SocialEngine] Group '#{group.name}' dissolved")

      _ ->
        :ok
    end
  end

  # ── Helpers ────────────────────────────────────────────

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
