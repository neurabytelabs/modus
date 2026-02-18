defmodule Modus.Mind.Goals do
  @moduledoc """
  Agent Goals System — User-defined objectives that drive agent behavior.

  Goals are stored in ETS for fast access. Each goal tracks progress
  toward completion and rewards agents with joy + conatus on success.

  Available goal types:
  - :build_home — Build a house or hut
  - :make_friends — Reach a target friend count
  - :explore_map — Visit % of the map
  - :gather_resources — Gather a target amount of resources
  - :survive_winter — Survive through a winter season
  """

  @table :agent_goals
  @goal_types [:build_home, :make_friends, :explore_map, :gather_resources, :survive_winter]

  defstruct [
    :id,
    :agent_id,
    :type,
    :target,
    :progress,
    # :active | :completed | :failed
    :status,
    # tick
    :assigned_at,
    # tick | nil
    :completed_at
  ]

  @type t :: %__MODULE__{}

  # --- Init ---

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :bag, :public, read_concurrency: true])
    end

    :ok
  end

  # --- Public API ---

  @doc "Add a goal to an agent."
  def add_goal(agent_id, type, target \\ nil, tick \\ 0) when type in @goal_types do
    init()
    target = target || default_target(type)

    goal = %__MODULE__{
      id: :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower),
      agent_id: agent_id,
      type: type,
      target: target,
      progress: 0.0,
      status: :active,
      assigned_at: tick,
      completed_at: nil
    }

    :ets.insert(@table, {agent_id, goal})
    goal
  end

  @doc "Remove a goal by id."
  def remove_goal(agent_id, goal_id) do
    init()
    goals = get_goals(agent_id)
    remaining = Enum.reject(goals, &(&1.id == goal_id))
    :ets.delete(@table, agent_id)
    Enum.each(remaining, fn g -> :ets.insert(@table, {agent_id, g}) end)
    :ok
  end

  @doc "Get all goals for an agent."
  def get_goals(agent_id) do
    init()

    :ets.lookup(@table, agent_id)
    |> Enum.map(fn {_id, goal} -> goal end)
  end

  @doc "Get active goals for an agent."
  def active_goals(agent_id) do
    get_goals(agent_id) |> Enum.filter(&(&1.status == :active))
  end

  @doc "Check and update goal progress. Returns {updated_goals, newly_completed}."
  def check_progress(agent_id, agent_state, tick) do
    init()
    goals = active_goals(agent_id)

    {updated, completed} =
      Enum.reduce(goals, {[], []}, fn goal, {upd, comp} ->
        new_progress = calculate_progress(goal, agent_state)

        if new_progress >= 1.0 do
          done = %{goal | progress: 1.0, status: :completed, completed_at: tick}
          {[done | upd], [done | comp]}
        else
          {[%{goal | progress: new_progress} | upd], comp}
        end
      end)

    # Persist updated goals
    unchanged = get_goals(agent_id) |> Enum.filter(&(&1.status != :active))
    :ets.delete(@table, agent_id)
    Enum.each(updated ++ unchanged, fn g -> :ets.insert(@table, {agent_id, g}) end)

    {updated, completed}
  end

  @doc "Auto-assign goals based on personality."
  def auto_assign(agent_id, personality, tick) do
    init()
    existing = get_goals(agent_id) |> Enum.map(& &1.type)

    goals = []

    goals =
      if personality.openness > 0.65 and :explore_map not in existing,
        do: [add_goal(agent_id, :explore_map, 50, tick) | goals],
        else: goals

    goals =
      if personality.extraversion > 0.65 and :make_friends not in existing,
        do: [add_goal(agent_id, :make_friends, 3, tick) | goals],
        else: goals

    goals =
      if personality.conscientiousness > 0.65 and :build_home not in existing,
        do: [add_goal(agent_id, :build_home, nil, tick) | goals],
        else: goals

    goals =
      if personality.neuroticism > 0.65 and :gather_resources not in existing,
        do: [add_goal(agent_id, :gather_resources, 20, tick) | goals],
        else: goals

    goals
  end

  @doc "Serialize goals for JSON transport."
  def serialize(agent_id) do
    get_goals(agent_id)
    |> Enum.map(fn g ->
      %{
        id: g.id,
        type: to_string(g.type),
        target: g.target,
        progress: Float.round(ensure_float(g.progress), 2),
        status: to_string(g.status),
        assigned_at: g.assigned_at,
        completed_at: g.completed_at
      }
    end)
  end

  @doc "Clear all goals (for world reset)."
  def clear_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc "Available goal types."
  def goal_types, do: @goal_types

  @doc "Human-readable goal description."
  def describe(%{type: :build_home}), do: "Build a home"
  def describe(%{type: :make_friends, target: t}), do: "Make #{t} friends"
  def describe(%{type: :explore_map, target: t}), do: "Explore #{t}% of the map"
  def describe(%{type: :gather_resources, target: t}), do: "Gather #{t} resources"
  def describe(%{type: :survive_winter}), do: "Survive through winter"
  def describe(_), do: "Unknown goal"

  # --- Private ---

  defp calculate_progress(%{type: :build_home} = _goal, agent) do
    if Modus.Simulation.Building.has_home?(agent.id), do: 1.0, else: 0.0
  end

  defp calculate_progress(%{type: :make_friends, target: target}, agent) do
    friend_count =
      agent.relationships
      |> Enum.filter(fn {_id, {type, _str}} -> type in [:friend, :close_friend] end)
      |> length()

    min(friend_count / max(target, 1), 1.0)
  end

  defp calculate_progress(%{type: :explore_map, target: target_pct}, agent) do
    # Use unique positions from affect memory as proxy for exploration
    visited =
      try do
        memories = Modus.Mind.AffectMemory.recall(agent.id, limit: 100)

        memories
        |> Enum.map(& &1.position)
        |> Enum.uniq()
        |> length()
      catch
        _, _ -> 0
      end

    # Estimate world size from World state
    total =
      try do
        state = Modus.Simulation.World.get_state()
        {w, h} = state.grid_size
        w * h
      catch
        _, _ -> 2500
      end

    pct = visited / max(total, 1) * 100
    min(pct / max(target_pct, 1), 1.0)
  end

  defp calculate_progress(%{type: :gather_resources, target: target}, agent) do
    total =
      agent.inventory
      |> Map.values()
      |> Enum.sum()

    min(total / max(target, 1), 1.0)
  end

  defp calculate_progress(%{type: :survive_winter}, _agent) do
    try do
      state = Modus.Simulation.Seasons.get_state()

      cond do
        # Survived winter if we completed at least 1 year (been through all seasons)
        state.year > 1 -> 1.0
        # Currently in winter — show progress through it
        state.season == :winter -> state.season_tick / 1000
        # Past winter in year 1 (spring/summer/autumn after winter)
        state.season in [:spring] and state.total_ticks > 3000 -> 1.0
        true -> 0.0
      end
    catch
      _, _ -> 0.0
    end
  end

  defp calculate_progress(_goal, _agent), do: 0.0

  defp default_target(:build_home), do: 1
  defp default_target(:make_friends), do: 3
  defp default_target(:explore_map), do: 30
  defp default_target(:gather_resources), do: 20
  defp default_target(:survive_winter), do: 1

  def ensure_float_pub(val), do: ensure_float(val)

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0
end
