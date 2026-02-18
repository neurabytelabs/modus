defmodule Modus.Mind.MindEngine do
  @moduledoc "Orchestrates conatus + affect processing each tick"

  alias Modus.Mind.{Conatus, Affect, AffectMemory, ReasoningEngine, Goals, Culture}

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
        agent.id,
        tick,
        agent.position,
        agent.affect_state,
        new_affect,
        affect_reason,
        new_energy
      )
    end

    # 7. Decay memories every 50 ticks
    if rem(tick, 50) == 0 do
      AffectMemory.decay_all(tick)
    end

    # 7b. Decay social relationships every 100 ticks
    if rem(tick, 100) == 0 do
      Modus.Mind.Cerebro.SocialNetwork.decay_all()
    end

    # 7d. Culture: generate catchphrases from experience
    Culture.maybe_generate_catchphrase(agent.id, event, tick)

    # 7e. Cultural drift every 150 ticks
    if rem(tick, 150) == 0 do
      Culture.drift(agent.id)
    end

    # 7f. Decay culture every 200 ticks
    if rem(tick, 200) == 0 do
      Culture.decay_all()
    end

    # 7g. Check traditions every 100 ticks
    if rem(tick, 100) == 0 do
      season =
        try do
          Modus.Simulation.Seasons.get_state().season
        catch
          _, _ -> :spring
        end

      triggered = Culture.check_traditions(tick, season, if(not agent.alive?, do: :death))

      Enum.each(triggered, fn tradition ->
        # Find nearby agents as participants
        nearby_ids =
          Modus.AgentRegistry
          |> Registry.select([{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
          |> Enum.filter(fn {_id, {_x, _y, alive}} -> alive end)
          |> Enum.map(fn {id, _} -> id end)
          |> Enum.take(6)

        Culture.perform_tradition(tradition.id, [agent.id | nearby_ids], tick)

        Modus.Simulation.EventLog.log(:tradition_performed, tick, [agent.id | nearby_ids], %{
          tradition: tradition.name,
          description: tradition.description,
          type: to_string(tradition.type)
        })
      end)
    end

    # 7c. Try to form groups every 200 ticks
    if rem(tick, 200) == 0 do
      agent_ids =
        Modus.AgentRegistry
        |> Registry.select([{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
        |> Enum.filter(fn {_id, {_x, _y, alive}} -> alive end)
        |> Enum.map(fn {id, _} -> id end)

      Modus.Mind.Cerebro.Group.maybe_form_groups(agent_ids, tick)
    end

    # 8. Build base updated agent
    updated_agent = %{
      agent
      | conatus_energy: new_energy,
        affect_state: new_affect,
        affect_history: affect_history,
        conatus_history: conatus_history
    }

    # 9. Auto-assign goals on first tick
    updated_agent =
      if not updated_agent.goals_initialized do
        Goals.auto_assign(updated_agent.id, updated_agent.personality, tick)
        %{updated_agent | goals_initialized: true}
      else
        updated_agent
      end

    # 10. Check goal progress every 50 ticks
    updated_agent =
      if rem(tick, 50) == 0 do
        {_updated_goals, completed} = Goals.check_progress(updated_agent.id, updated_agent, tick)

        Enum.reduce(completed, updated_agent, fn goal, acc ->
          # Reward: joy + conatus boost + event log
          Modus.Simulation.EventLog.log(:goal_completed, tick, [acc.id], %{
            name: acc.name,
            goal: to_string(goal.type),
            description: Goals.describe(goal)
          })

          %{
            acc
            | conatus_energy: Conatus.clamp(acc.conatus_energy + 0.1),
              affect_state: :joy,
              affect_history:
                Enum.take(
                  [
                    %{
                      tick: tick,
                      from: acc.affect_state,
                      to: :joy,
                      reason: "completed goal: #{Goals.describe(goal)}"
                    }
                    | acc.affect_history
                  ],
                  @max_history
                )
          }
        end)
      else
        updated_agent
      end

    # 11. LLM reasoning every 100 ticks for persistently sad agents
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
      %{
        updated_agent
        | conatus_energy: Conatus.clamp(updated_agent.conatus_energy + 0.05),
          affect_state: :desire,
          affect_history:
            Enum.take(
              [
                %{tick: tick, from: new_affect, to: :desire, reason: "reasoning insight"}
                | affect_history
              ],
              @max_history
            ),
          last_reasoning: "Reasoning triggered at tick #{tick}"
      }
    else
      updated_agent
    end
  end

  @doc "Classify an action atom into a mind event type."
  def classify_event(action, agent) do
    hunger_critical? = agent.needs.hunger > 90

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
