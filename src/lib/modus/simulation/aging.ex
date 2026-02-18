defmodule Modus.Simulation.Aging do
  @moduledoc """
  Aging — Agent lifecycle stages, appearance, and generational knowledge.

  Spinoza's Sensus: "Time writes its story on every face."

  ## Age Stages
  - Child (0-499 ticks): learns fast, low strength
  - Young (500-1499): energetic, social
  - Adult (1500-2999): peak abilities, balanced
  - Elder (3000+): wise, teaches others, slower

  ## Lifespan
  Base: 3000-5000 ticks, modified by lifestyle factors:
  - High conatus energy history → longer life
  - Balanced needs → longer life
  - Starvation/exhaustion → shorter life
  """

  @table :modus_aging

  @type age_stage :: :child | :young | :adult | :elder

  # Stage thresholds (in age units, where age increments every 100 ticks)
  # 0-499 ticks
  @child_max 4
  # 500-1499 ticks
  @young_max 14
  # 1500-2999 ticks
  @adult_max 29
  # 30+ = elder       # 3000+ ticks

  # Base lifespan range (in age units)
  # ~3000 ticks
  @min_lifespan 30
  # ~5000 ticks
  @max_lifespan 50

  # ── Init ────────────────────────────────────────────────────

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Initialize aging data for a new agent."
  @spec init_agent(String.t(), age_stage()) :: :ok
  def init_agent(agent_id, initial_stage \\ :child) do
    lifespan = @min_lifespan + :rand.uniform(@max_lifespan - @min_lifespan)

    data = %{
      stage: initial_stage,
      lifespan: lifespan,
      milestones: [],
      lifestyle_score: 0.0,
      lifestyle_ticks: 0
    }

    :ets.insert(@table, {agent_id, data})
    :ok
  end

  # ── Queries ─────────────────────────────────────────────────

  @doc "Get the age stage for an agent based on their age."
  @spec stage(non_neg_integer()) :: age_stage()
  def stage(age) when age <= @child_max, do: :child
  def stage(age) when age <= @young_max, do: :young
  def stage(age) when age <= @adult_max, do: :adult
  def stage(_age), do: :elder

  @doc "Get emoji for an agent's current age stage."
  @spec emoji(age_stage()) :: String.t()
  def emoji(:child), do: "👶"
  def emoji(:young), do: "🧑"
  def emoji(:adult), do: "🧔"
  def emoji(:elder), do: "👴"

  @doc "Get the stage label."
  @spec stage_label(age_stage()) :: String.t()
  def stage_label(:child), do: "Child"
  def stage_label(:young), do: "Young"
  def stage_label(:adult), do: "Adult"
  def stage_label(:elder), do: "Elder"

  @doc "Get ability modifiers for a stage."
  @spec modifiers(age_stage()) :: map()
  def modifiers(:child) do
    %{learning_rate: 2.0, strength: 0.5, wisdom: 0.3, speed: 0.7, social: 0.8}
  end

  def modifiers(:young) do
    %{learning_rate: 1.5, strength: 0.9, wisdom: 0.5, speed: 1.2, social: 1.3}
  end

  def modifiers(:adult) do
    %{learning_rate: 1.0, strength: 1.0, wisdom: 1.0, speed: 1.0, social: 1.0}
  end

  def modifiers(:elder) do
    %{learning_rate: 0.5, strength: 0.5, wisdom: 2.0, speed: 0.6, social: 1.2}
  end

  @doc "Get aging data for an agent."
  @spec get_data(String.t()) :: map() | nil
  def get_data(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, data}] -> data
      _ -> nil
    end
  end

  @doc "Check if agent has reached their lifespan (natural death)."
  @spec should_die_of_age?(String.t(), non_neg_integer()) :: boolean()
  def should_die_of_age?(agent_id, age) do
    case get_data(agent_id) do
      nil ->
        false

      data ->
        # Lifestyle bonus: good living extends lifespan up to 20%
        bonus = min(data.lifestyle_score / max(data.lifestyle_ticks, 1) * 0.2, 0.2)
        effective_lifespan = round(data.lifespan * (1.0 + bonus))
        age >= effective_lifespan
    end
  end

  # ── Processing ──────────────────────────────────────────────

  @doc "Process aging tick — update stage, check milestones, track lifestyle."
  @spec process_tick(map(), non_neg_integer()) :: map()
  def process_tick(agent, tick) do
    age = agent.age
    current_stage = stage(age)
    data = get_data(agent.id)

    if data == nil do
      init_agent(agent.id, current_stage)
      agent
    else
      old_stage = data.stage

      # Update lifestyle score based on current wellbeing
      wellbeing = calculate_wellbeing(agent)
      new_lifestyle = data.lifestyle_score + wellbeing
      new_ticks = data.lifestyle_ticks + 1

      # Check for stage transition milestone
      milestones =
        if current_stage != old_stage do
          milestone = %{from: old_stage, to: current_stage, tick: tick, age: age}
          [milestone | data.milestones]
        else
          data.milestones
        end

      # Log milestone events
      if current_stage != old_stage do
        Modus.Simulation.EventLog.log(:milestone, tick, [agent.id], %{
          name: agent.name,
          event: "age_transition",
          from: to_string(old_stage),
          to: to_string(current_stage)
        })
      end

      :ets.insert(
        @table,
        {agent.id,
         %{
           data
           | stage: current_stage,
             milestones: milestones,
             lifestyle_score: new_lifestyle,
             lifestyle_ticks: new_ticks
         }}
      )

      agent
    end
  end

  @doc "Elder knowledge transfer — elder teaches a skill to a nearby young agent."
  @spec maybe_teach(String.t(), non_neg_integer(), [String.t()]) :: :ok
  def maybe_teach(elder_id, tick, nearby_agent_ids) do
    elder_age =
      try do
        Modus.Simulation.Agent.get_state(elder_id).age
      catch
        _, _ -> 0
      end

    if stage(elder_age) == :elder and rem(tick, 200) == 0 do
      # Find a young/child agent nearby to teach
      student =
        Enum.find(nearby_agent_ids, fn id ->
          try do
            s = Modus.Simulation.Agent.get_state(id)
            s.alive? and stage(s.age) in [:child, :young]
          catch
            _, _ -> false
          end
        end)

      if student do
        # Transfer knowledge: pick elder's best skill
        elder_skills = Modus.Mind.Learning.get_skills(elder_id)
        {best_skill, best_data} = Enum.max_by(elder_skills, fn {_, d} -> d.xp end)

        if best_data.xp > 0 do
          # Student gets 10% of elder's XP (wisdom modifier)
          xp_gift = best_data.xp * 0.1
          Modus.Mind.Learning.add_xp(student, best_skill, xp_gift)

          Modus.Simulation.EventLog.log(:teaching, tick, [elder_id, student], %{
            skill: to_string(best_skill),
            xp: Float.round(xp_gift, 1)
          })
        end
      end
    end

    :ok
  end

  @doc "Handle elder death — create memorial event and legacy."
  @spec on_death(String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def on_death(agent_id, age, tick) do
    if stage(age) == :elder do
      Modus.Simulation.EventLog.log(:memorial, tick, [agent_id], %{
        event: "elder_memorial",
        age: age,
        stage: "elder"
      })
    end

    # Cleanup
    :ets.delete(@table, agent_id)
    :ok
  end

  @doc "Get population age distribution."
  @spec population_pyramid() :: map()
  def population_pyramid do
    agents =
      try do
        Modus.Simulation.AgentSupervisor.list_agents()
        |> Enum.map(fn id ->
          try do
            s = Modus.Simulation.Agent.get_state(id)
            if s.alive?, do: stage(s.age), else: nil
          catch
            _, _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      catch
        _, _ -> []
      end

    %{
      child: Enum.count(agents, &(&1 == :child)),
      young: Enum.count(agents, &(&1 == :young)),
      adult: Enum.count(agents, &(&1 == :adult)),
      elder: Enum.count(agents, &(&1 == :elder)),
      total: length(agents)
    }
  end

  @doc "Serialize aging data for frontend."
  @spec serialize(String.t(), non_neg_integer()) :: map()
  def serialize(agent_id, age) do
    current_stage = stage(age)
    data = get_data(agent_id)
    mods = modifiers(current_stage)

    %{
      "stage" => to_string(current_stage),
      "stage_label" => stage_label(current_stage),
      "emoji" => emoji(current_stage),
      "age" => age,
      "lifespan" => if(data, do: data.lifespan, else: 0),
      "milestones" => if(data, do: length(data.milestones), else: 0),
      "modifiers" => %{
        "learning_rate" => mods.learning_rate,
        "strength" => mods.strength,
        "wisdom" => mods.wisdom,
        "speed" => mods.speed,
        "social" => mods.social
      }
    }
  end

  # ── Internal ────────────────────────────────────────────────

  defp calculate_wellbeing(agent) do
    needs = agent.needs
    hunger_ok = if needs.hunger < 50.0, do: 1.0, else: 0.0
    rest_ok = if needs.rest > 30.0, do: 1.0, else: 0.0
    energy_ok = if agent.conatus_energy > 0.5, do: 1.0, else: 0.0
    (hunger_ok + rest_ok + energy_ok) / 3.0
  end
end
