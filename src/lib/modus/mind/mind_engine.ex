defmodule Modus.Mind.MindEngine do
  @moduledoc "Orchestrates conatus + affect processing each tick"

  alias Modus.Mind.{Conatus, Affect, AffectMemory, ReasoningEngine}

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

    affect_changed = new_affect != agent.affect_state

    affect_history =
      if affect_changed do
        Enum.take([affect_entry | agent.affect_history], @max_history)
      else
        agent.affect_history
      end

    conatus_history = Enum.take([conatus_entry | agent.conatus_history], @max_history)

    # 6. Form affect memory on state change
    if affect_changed do
      AffectMemory.form_memory(
        agent.id, tick, agent.position,
        agent.affect_state, new_affect, affect_reason, new_energy
      )
    end

    # 7. Decay memories every 50 ticks
    if rem(tick, 50) == 0 do
      AffectMemory.decay_all(tick)
    end

    # 8. Build base updated agent
    updated_agent = %{agent |
      conatus_energy: new_energy,
      affect_state: new_affect,
      affect_history: affect_history,
      conatus_history: conatus_history
    }

    # 9. LLM reasoning every 100 ticks for persistently sad agents
    if rem(tick, 100) == 0 and ReasoningEngine.should_reason?(updated_agent) do
      # Fire reasoning async, apply result
      agent_ref = updated_agent
      Task.start(fn ->
        case ReasoningEngine.reason(agent_ref) do
          {:ok, _reasoning} -> :ok
          _ -> :ok
        end
      end)

      # Boost conatus and shift affect to desire
      %{updated_agent |
        conatus_energy: Conatus.clamp(updated_agent.conatus_energy + 0.05),
        affect_state: :desire,
        affect_history: Enum.take([%{tick: tick, from: new_affect, to: :desire, reason: "reasoning insight"} | affect_history], @max_history),
        last_reasoning: "Reasoning triggered at tick #{tick}"
      }
    else
      updated_agent
    end
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
