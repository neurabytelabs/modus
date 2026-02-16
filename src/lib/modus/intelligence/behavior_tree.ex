defmodule Modus.Intelligence.BehaviorTree do
  @moduledoc """
  BehaviorTree — Need-driven and personality-based decision making.

  Implements a simple priority-based behavior tree:
  1. **Critical needs** — survival-level urgency (hunger, rest, social)
  2. **Personality-driven** — probabilistic actions based on Big Five traits
  3. **Default** — idle fallback

  In Spinoza's terms, this is the conatus expressing itself through
  the agent's affects and dispositions.
  """

  alias Modus.Simulation.Agent

  @type action :: :find_food | :go_home_sleep | :find_friend | :explore |
                  :help_nearby | :gather | :idle

  @doc """
  Evaluate the behavior tree for an agent, returning an action atom.

  Priority order:
  1. Need-driven (critical thresholds)
  2. Personality-driven (every 10 ticks, probabilistic)
  3. Fallback to :idle
  """
  @spec evaluate(Agent.t(), non_neg_integer()) :: action()
  def evaluate(%Agent{} = agent, tick) do
    case check_needs(agent) do
      nil -> check_personality(agent, tick)
      action -> action
    end
  end

  # ── Need-driven decisions ───────────────────────────────────

  @spec check_needs(Agent.t()) :: action() | nil
  defp check_needs(%Agent{needs: needs}) do
    cond do
      needs.hunger > 80.0  -> :find_food
      needs.rest < 20.0    -> :go_home_sleep
      needs.social < 30.0  -> :find_friend
      true                 -> nil
    end
  end

  # ── Personality-driven decisions (every 10 ticks) ───────────

  @spec check_personality(Agent.t(), non_neg_integer()) :: action()
  defp check_personality(%Agent{personality: p}, tick) when rem(tick, 10) == 0 do
    roll = :rand.uniform()

    cond do
      p.openness > 0.7 and roll < 0.3       -> :explore
      p.agreeableness > 0.8 and roll < 0.5   -> :help_nearby
      p.conscientiousness > 0.7 and roll < 0.4 -> :gather
      true                                    -> :idle
    end
  end

  defp check_personality(_agent, _tick), do: :idle
end
