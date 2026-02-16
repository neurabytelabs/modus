defmodule Modus.Mind.Learning do
  @moduledoc """
  Learning — Agent skill system with experience-based leveling and cultural transmission.

  Spinoza's *Sapientia*: wisdom gained through experience and inherited through culture.

  ## Skills
  Each agent has skills (farming, building, social, exploration, healing, trading)
  that improve with practice. Higher skills yield more efficient actions.

  ## Cultural Transmission
  Newborn agents inherit a fraction of their parents' skills, simulating
  cultural knowledge transfer across generations.

  ## Storage
  ETS-based for lock-free concurrent reads.
  """

  @table :modus_learning
  @skills [:farming, :building, :social, :exploration, :healing, :trading]

  # XP needed per level: level 1=100, level 2=250, level 3=500, etc.
  @xp_thresholds %{1 => 100, 2 => 250, 3 => 500, 4 => 1000, 5 => 2000}
  @max_level 5

  # Cultural transmission: child inherits this fraction of parent avg
  @inheritance_factor 0.3

  @type skill_data :: %{xp: float(), level: non_neg_integer()}
  @type skills_map :: %{atom() => skill_data()}

  # ── Init ────────────────────────────────────────────────────

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  @doc "Initialize skills for a new agent (all at level 0, 0 xp)."
  @spec init_skills(String.t()) :: :ok
  def init_skills(agent_id) do
    skills = Map.new(@skills, fn s -> {s, %{xp: 0.0, level: 0}} end)
    :ets.insert(@table, {agent_id, skills})
    :ok
  end

  @doc "Initialize skills for a newborn with cultural inheritance from parents."
  @spec init_skills_with_inheritance(String.t(), String.t(), String.t()) :: :ok
  def init_skills_with_inheritance(child_id, parent_a_id, parent_b_id) do
    parent_a_skills = get_skills(parent_a_id)
    parent_b_skills = get_skills(parent_b_id)

    child_skills =
      Map.new(@skills, fn skill ->
        a_xp = get_in_map(parent_a_skills, skill, :xp)
        b_xp = get_in_map(parent_b_skills, skill, :xp)
        avg_xp = (a_xp + b_xp) / 2.0
        inherited_xp = avg_xp * @inheritance_factor
        level = calculate_level(inherited_xp)
        {skill, %{xp: inherited_xp, level: level}}
      end)

    :ets.insert(@table, {child_id, child_skills})
    :ok
  end

  # ── Queries ─────────────────────────────────────────────────

  @doc "Get all skills for an agent."
  @spec get_skills(String.t()) :: skills_map()
  def get_skills(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, skills}] -> skills
      _ -> Map.new(@skills, fn s -> {s, %{xp: 0.0, level: 0}} end)
    end
  end

  @doc "Get a specific skill's data."
  @spec get_skill(String.t(), atom()) :: skill_data()
  def get_skill(agent_id, skill) do
    skills = get_skills(agent_id)
    Map.get(skills, skill, %{xp: 0.0, level: 0})
  end

  @doc "Get skill level (0-5)."
  @spec skill_level(String.t(), atom()) :: non_neg_integer()
  def skill_level(agent_id, skill) do
    get_skill(agent_id, skill).level
  end

  @doc "Calculate efficiency bonus from skill level (1.0 = no bonus, up to 2.0 at max)."
  @spec efficiency(String.t(), atom()) :: float()
  def efficiency(agent_id, skill) do
    level = skill_level(agent_id, skill)
    1.0 + level * 0.2
  end

  @doc "List all known skills."
  @spec skill_types() :: [atom()]
  def skill_types, do: @skills

  # ── XP & Leveling ──────────────────────────────────────────

  @doc "Add experience points to a skill. Returns {:ok, new_level} or {:level_up, old, new}."
  @spec add_xp(String.t(), atom(), float()) :: {:ok, non_neg_integer()} | {:level_up, non_neg_integer(), non_neg_integer()}
  def add_xp(agent_id, skill, xp_amount) when xp_amount > 0 do
    skills = get_skills(agent_id)
    current = Map.get(skills, skill, %{xp: 0.0, level: 0})
    new_xp = current.xp + xp_amount
    new_level = calculate_level(new_xp)
    updated = %{current | xp: new_xp, level: new_level}
    :ets.insert(@table, {agent_id, Map.put(skills, skill, updated)})

    if new_level > current.level do
      {:level_up, current.level, new_level}
    else
      {:ok, new_level}
    end
  end

  def add_xp(_agent_id, _skill, _xp), do: {:ok, 0}

  @doc "Award XP based on an action. Maps actions to relevant skills."
  @spec award_for_action(String.t(), atom()) :: :ok
  def award_for_action(agent_id, action) do
    case action_skill_map(action) do
      nil -> :ok
      {skill, xp} ->
        add_xp(agent_id, skill, xp)
        :ok
    end
  end

  # ── Serialization ───────────────────────────────────────────

  @doc "Serialize skills for JSON/frontend."
  @spec to_map(String.t()) :: map()
  def to_map(agent_id) do
    skills = get_skills(agent_id)

    skills
    |> Enum.map(fn {skill, data} ->
      {to_string(skill), %{
        "xp" => Float.round(ensure_float(data.xp), 1),
        "level" => data.level,
        "progress" => level_progress(data.xp, data.level)
      }}
    end)
    |> Map.new()
  end

  @doc "Clean up agent skills on death."
  @spec cleanup(String.t()) :: :ok
  def cleanup(agent_id) do
    :ets.delete(@table, agent_id)
    :ok
  end

  # ── Internal ────────────────────────────────────────────────

  defp calculate_level(xp) do
    @xp_thresholds
    |> Enum.sort_by(fn {lvl, _} -> lvl end, :desc)
    |> Enum.find_value(0, fn {lvl, threshold} ->
      if xp >= threshold, do: lvl
    end)
  end

  defp level_progress(_xp, level) when level >= @max_level, do: 100.0
  defp level_progress(xp, level) do
    current_threshold = Map.get(@xp_thresholds, level, 0)
    next_threshold = Map.get(@xp_thresholds, level + 1, 100)
    range = next_threshold - current_threshold
    progress = if range > 0, do: (xp - current_threshold) / range * 100, else: 0.0
    Float.round(ensure_float(max(0.0, min(progress, 100.0))), 1)
  end

  defp action_skill_map(:gather), do: {:farming, 5.0}
  defp action_skill_map(:farm), do: {:farming, 8.0}
  defp action_skill_map(:build), do: {:building, 8.0}
  defp action_skill_map(:repair), do: {:building, 4.0}
  defp action_skill_map(:converse), do: {:social, 5.0}
  defp action_skill_map(:trade), do: {:trading, 6.0}
  defp action_skill_map(:explore), do: {:exploration, 3.0}
  defp action_skill_map(:move), do: {:exploration, 1.0}
  defp action_skill_map(:heal), do: {:healing, 7.0}
  defp action_skill_map(:rest), do: {:healing, 1.0}
  defp action_skill_map(_), do: nil

  defp get_in_map(skills, skill, field) do
    case Map.get(skills, skill) do
      nil -> 0.0
      data -> Map.get(data, field, 0.0)
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0
end
