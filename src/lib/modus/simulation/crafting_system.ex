defmodule Modus.Simulation.CraftingSystem do
  @moduledoc """
  Fabrica — Recipe-based crafting with skill progression and teaching.

  ## Skill Levels
  - novice:      0-24 XP
  - apprentice: 25-49 XP
  - expert:     50-74 XP
  - master:     75-100 XP

  ## Quality
  Tool/item quality scales with skill level (0.25 to 1.0).

  ## Teaching
  Master agents can transfer XP to apprentices via teach/3.
  """

  alias Modus.Simulation.EventLog

  @recipes %{
    sword: [:iron, :wood],
    bread: [:wheat, :water],
    medicine: [:herb, :water],
    rope: [:fiber],
    torch: [:wood, :fiber]
  }

  @skill_thresholds [
    {:master, 75},
    {:expert, 50},
    {:apprentice, 25},
    {:novice, 0}
  ]

  @type skill_data :: %{xp: number(), crafted_count: integer()}
  @type agent_skills :: %{optional(atom()) => skill_data()}
  @type craft_result :: {:ok, map()} | {:error, atom()}

  # ── Public API ──────────────────────────────────────────

  @doc "Returns all available recipes."
  @spec recipes() :: map()
  def recipes, do: @recipes

  @doc "Get the skill level atom for a given XP value."
  @spec skill_level(number()) :: atom()
  def skill_level(xp) when is_number(xp) do
    xp = ensure_float(xp)
    Enum.find_value(@skill_thresholds, :novice, fn {level, threshold} ->
      if xp >= threshold, do: level
    end)
  end

  @doc "Quality multiplier based on skill level (0.25 - 1.0)."
  @spec quality(atom()) :: float()
  def quality(:master), do: 1.0
  def quality(:expert), do: 0.75
  def quality(:apprentice), do: 0.5
  def quality(:novice), do: 0.25

  @doc """
  Attempt to craft an item.

  Returns `{:ok, result}` with crafted item info and updated skills,
  or `{:error, reason}`.
  """
  @spec craft(String.t(), atom(), map(), agent_skills(), integer()) :: craft_result()
  def craft(agent_id, item, inventory, skills, tick \\ 0) do
    with {:ok, ingredients} <- get_recipe(item),
         :ok <- check_ingredients(ingredients, inventory) do
      skill = Map.get(skills, item, %{xp: 0.0, crafted_count: 0})
      level = skill_level(skill.xp)
      item_quality = quality(level)

      new_xp = min(ensure_float(skill.xp) + xp_gain(level), 100.0)
      new_count = skill.crafted_count + 1
      updated_skill = %{xp: new_xp, crafted_count: new_count}
      updated_skills = Map.put(skills, item, updated_skill)

      new_inventory = consume_ingredients(ingredients, inventory)

      result = %{
        item: item,
        quality: item_quality,
        level: level,
        skill: updated_skill,
        skills: updated_skills,
        inventory: new_inventory
      }

      log_craft(agent_id, item, item_quality, level, tick)

      {:ok, result}
    end
  end

  @doc """
  Master teaches apprentice. Transfers XP for a specific item skill.
  Teacher must be master level. Apprentice gains 10 XP.
  """
  @spec teach(String.t(), String.t(), atom(), agent_skills(), agent_skills(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def teach(teacher_id, student_id, item, teacher_skills, student_skills, tick \\ 0) do
    teacher_skill = Map.get(teacher_skills, item, %{xp: 0.0, crafted_count: 0})

    if skill_level(teacher_skill.xp) == :master do
      student_skill = Map.get(student_skills, item, %{xp: 0.0, crafted_count: 0})
      new_xp = min(ensure_float(student_skill.xp) + 10.0, 100.0)
      updated = %{student_skill | xp: new_xp}
      updated_student_skills = Map.put(student_skills, item, updated)

      log_teach(teacher_id, student_id, item, tick)

      {:ok, %{student_skills: updated_student_skills, xp_gained: 10.0}}
    else
      {:error, :teacher_not_master}
    end
  end

  # ── Private ─────────────────────────────────────────────

  defp get_recipe(item) do
    case Map.get(@recipes, item) do
      nil -> {:error, :unknown_recipe}
      ingredients -> {:ok, ingredients}
    end
  end

  defp check_ingredients(ingredients, inventory) do
    counts = Enum.frequencies(ingredients)

    missing =
      Enum.any?(counts, fn {res, needed} ->
        Map.get(inventory, res, 0) < needed
      end)

    if missing, do: {:error, :missing_ingredients}, else: :ok
  end

  defp consume_ingredients(ingredients, inventory) do
    Enum.reduce(ingredients, inventory, fn res, inv ->
      Map.update(inv, res, 0, &max(&1 - 1, 0))
    end)
  end

  defp xp_gain(:master), do: 0.5
  defp xp_gain(:expert), do: 2.0
  defp xp_gain(:apprentice), do: 3.0
  defp xp_gain(:novice), do: 5.0

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  defp log_craft(agent_id, item, quality, level, tick) do
    try do
      EventLog.log(:crafting, tick, [agent_id], %{
        item: item,
        quality: quality,
        skill_level: level
      })
    rescue
      _ -> :ok
    end
  end

  defp log_teach(teacher_id, student_id, item, tick) do
    try do
      EventLog.log(:teaching, tick, [teacher_id, student_id], %{
        item: item,
        teacher: teacher_id,
        student: student_id
      })
    rescue
      _ -> :ok
    end
  end
end
