defmodule Modus.Intelligence.BehaviorTree do
  @moduledoc """
  BehaviorTree — Need-driven and personality-based decision making.

  Implements a priority-based behavior tree with low idle rates:
  1. **Critical needs** — survival-level urgency (lowered thresholds)
  2. **Moderate needs** — proactive behavior before crisis
  3. **Personality-driven** — every tick, probabilistic actions based on Big Five
  4. **Default** — mostly explore, rarely idle
  """

  alias Modus.Simulation.Agent

  @type action :: :find_food | :go_home_sleep | :find_friend | :explore |
                  :help_nearby | :gather | :idle

  @spec evaluate(Agent.t(), non_neg_integer()) :: action()
  def evaluate(%Agent{} = agent, tick) do
    case check_critical_needs(agent) do
      nil ->
        case check_moderate_needs(agent) do
          nil -> check_personality(agent, tick)
          action -> action
        end
      action -> action
    end
  end

  # ── Critical needs (immediate action) ──────────────────────

  defp check_critical_needs(%Agent{needs: needs}) do
    cond do
      needs.hunger > 70.0 -> :find_food
      needs.rest < 25.0   -> :go_home_sleep
      needs.social < 20.0 -> :find_friend
      true                -> nil
    end
  end

  # ── Moderate needs (proactive) ─────────────────────────────

  defp check_moderate_needs(%Agent{needs: needs, personality: p}) do
    cond do
      needs.hunger > 40.0 and :rand.uniform() < 0.4 -> :find_food
      needs.hunger > 40.0 and :rand.uniform() < 0.3 -> :gather
      needs.rest < 40.0 and :rand.uniform() < 0.3   -> :go_home_sleep
      needs.social < 60.0 and p.extraversion > 0.5 and :rand.uniform() < 0.5 -> :find_friend
      needs.social < 60.0 and :rand.uniform() < 0.25 -> :find_friend
      true -> nil
    end
  end

  # ── Personality-driven decisions (every tick now) ───────────

  defp check_personality(%Agent{personality: p}, _tick) do
    roll = :rand.uniform()

    # Personality weights
    explore_chance = 0.30 + p.openness * 0.2
    gather_chance = p.conscientiousness * 0.25
    social_chance = p.extraversion * 0.2
    help_chance = p.agreeableness * 0.15

    cond do
      roll < explore_chance                              -> :explore
      roll < explore_chance + gather_chance               -> :gather
      roll < explore_chance + gather_chance + social_chance -> :find_friend
      roll < explore_chance + gather_chance + social_chance + help_chance -> :help_nearby
      :rand.uniform() < 0.7                              -> :explore
      true                                                -> :idle
    end
  end
end
