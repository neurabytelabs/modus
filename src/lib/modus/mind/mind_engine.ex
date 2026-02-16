defmodule Modus.Mind.MindEngine do
  @moduledoc "Orchestrates conatus + affect processing each tick"

  alias Modus.Mind.{Conatus, Affect}

  @max_history 20

  @doc "Process one tick of the mind engine. Returns updated agent state."
  def process_tick(agent, action, _action_result, tick) do
    # 1. Classify action into event type
    event = classify_event(action, agent)

    # 2. Update affect state
    {new_affect, affect_reason} =
      Affect.transition(agent.affect_state, event, agent.personality, agent.conatus_energy)

    # 3. Apply affect's conatus modifier (passive per-tick effect)
    affect_mod = Affect.conatus_modifier(new_affect)
    energy_after_affect = Conatus.clamp(agent.conatus_energy + affect_mod)

    # 4. Update conatus based on event
    {new_energy, delta, conatus_reason} =
      Conatus.update_energy(energy_after_affect, event, new_affect)

    # 5. Build histories
    affect_entry = %{tick: tick, from: agent.affect_state, to: new_affect, reason: affect_reason}
    conatus_entry = %{tick: tick, energy: new_energy, delta: delta, reason: conatus_reason}

    affect_history =
      if new_affect != agent.affect_state do
        Enum.take([affect_entry | agent.affect_history], @max_history)
      else
        agent.affect_history
      end

    conatus_history = Enum.take([conatus_entry | agent.conatus_history], @max_history)

    # 6. Return updated agent
    %{agent |
      conatus_energy: new_energy,
      affect_state: new_affect,
      affect_history: affect_history,
      conatus_history: conatus_history
    }
  end

  @doc "Classify an action atom into a mind event type."
  def classify_event(action, agent) do
    hunger_critical? = agent.needs.hunger > 80

    cond do
      hunger_critical? -> :hunger_critical
      action in [:gather, :find_food] -> :action_success
      action in [:talk, :find_friend] -> :social_positive
      action == :explore -> :action_success_minor
      action == :sleep -> :rest
      action == :flee -> :action_failure
      action == :idle -> :natural_decay
      true -> :natural_decay
    end
  end
end
