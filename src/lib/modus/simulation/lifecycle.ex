defmodule Modus.Simulation.Lifecycle do
  @moduledoc """
  Lifecycle — Birth and death dynamics for population balance.

  - Birth: Two joyful agents (affect_state == :joy, conatus_energy > 0.7) nearby → spawn new agent
  - Death: Handled by Agent.check_death (conatus_energy <= 0)
  - Population target: 8-15 agents (birth only when pop < 15)
  """

  @birth_radius 4
  @min_pop 8
  @max_pop 15
  @base_birth_check_interval 50

  # ── State (ETS-based) ───────────────────────────────────────

  @table :modus_lifecycle

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ets.insert(@table, {:stats, %{births: 0, deaths: 0}})
    :ok
  end

  @doc "Get lifecycle stats."
  @spec stats() :: map()
  def stats do
    case :ets.lookup(@table, :stats) do
      [{:stats, s}] -> s
      _ -> %{births: 0, deaths: 0}
    end
  end

  @doc "Record a death (called from Agent.check_death)."
  @spec record_death() :: :ok
  def record_death do
    case :ets.lookup(@table, :stats) do
      [{:stats, s}] -> :ets.insert(@table, {:stats, %{s | deaths: s.deaths + 1}})
      _ -> :ok
    end
    :ok
  end

  @doc "Process lifecycle tick — check for births."
  @spec tick(non_neg_integer()) :: :ok
  def tick(tick_number) do
    # Higher birth_rate → more frequent checks
    birth_rate = try do Modus.Simulation.RulesEngine.birth_rate() catch _, _ -> 1.0 end
    check_interval = max(10, round(@base_birth_check_interval / birth_rate))
    if rem(tick_number, check_interval) == 0 do
      maybe_spawn_birth(tick_number)
    end
    :ok
  end

  # ── Internal ────────────────────────────────────────────────

  defp maybe_spawn_birth(tick) do
    agents = get_living_agents()
    pop = length(agents)

    cond do
      pop >= @max_pop ->
        :ok

      pop < @min_pop ->
        # Force birth if under minimum
        spawn_new_agent(agents, tick)

      true ->
        # Normal birth: find two joyful agents nearby
        joyful = Enum.filter(agents, fn a ->
          a.affect_state == :joy and a.conatus_energy > 0.7
        end)

        case find_birth_pair(joyful) do
          {parent_a, parent_b} -> spawn_child(parent_a, parent_b, tick)
          nil -> :ok
        end
    end
  end

  defp find_birth_pair(joyful) when length(joyful) < 2, do: nil
  defp find_birth_pair(joyful) do
    Enum.reduce_while(joyful, nil, fn a, _acc ->
      case Enum.find(joyful, fn b ->
        b.id != a.id and in_radius?(a.position, b.position)
      end) do
        nil -> {:cont, nil}
        b -> {:halt, {a, b}}
      end
    end)
  end

  defp spawn_new_agent(agents, tick) do
    # Pick a random living agent as "parent"
    case agents do
      [] -> :ok
      _ ->
        parent = Enum.random(agents)
        spawn_child(parent, parent, tick)
    end
  end

  defp spawn_child(parent_a, parent_b, tick) do
    # Child spawns near parents
    {px, py} = parent_a.position
    offset_x = Enum.random(-2..2)
    offset_y = Enum.random(-2..2)
    child_pos = {max(0, min(px + offset_x, 49)), max(0, min(py + offset_y, 49))}

    names = [
      "Dawn", "Hope", "Sky", "Sol", "Clay", "Cloud",
      "Brook", "Breeze", "Star", "Oak", "Atlas", "Rae",
      "Fable", "Reed", "Lake", "Sage", "Bay", "Haven"
    ]

    name = Enum.random(names)
    occupation = Enum.random([:farmer, :builder, :explorer, :healer, :trader])

    # Apply mutation_rate from RulesEngine for personality variance
    mutation_rate = try do Modus.Simulation.RulesEngine.mutation_rate() catch _, _ -> 0.3 end
    child = if mutation_rate > 0 and function_exported?(Modus.Simulation.Agent, :new_custom, 5) do
      parent_p = try do
        state = Modus.Simulation.Agent.get_state(parent_a.id)
        state.personality
      catch
        _, _ -> nil
      end

      if parent_p do
        mutate = fn val ->
          drift = (:rand.uniform() - 0.5) * mutation_rate
          max(0.0, min(1.0, val + drift))
        end

        personality = %{
          openness: mutate.(parent_p.openness),
          conscientiousness: mutate.(parent_p.conscientiousness),
          extraversion: mutate.(parent_p.extraversion),
          agreeableness: mutate.(parent_p.agreeableness),
          neuroticism: mutate.(parent_p.neuroticism)
        }

        Modus.Simulation.Agent.new_custom(name, child_pos, occupation, personality, :calm)
      else
        Modus.Simulation.Agent.new(name, child_pos, occupation)
      end
    else
      Modus.Simulation.Agent.new(name, child_pos, occupation)
    end

    case Modus.Simulation.AgentSupervisor.spawn_agent(child) do
      {:ok, _pid} ->
        # Cultural transmission: child inherits skills from parents
        Modus.Mind.Learning.init_skills_with_inheritance(child.id, parent_a.id, parent_b.id)

        Modus.Simulation.EventLog.log(:birth, tick, [child.id, parent_a.id, parent_b.id], %{
          name: name,
          parents: [parent_a.name, parent_b.name]
        })
        increment_births()
        :ok

      _ ->
        :ok
    end
  end

  defp get_living_agents do
    Modus.Simulation.AgentSupervisor.list_agents()
    |> Enum.map(fn id ->
      try do
        Modus.Simulation.Agent.get_state(id)
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.filter(fn a -> a != nil and a.alive? end)
  end

  defp in_radius?({x1, y1}, {x2, y2}) do
    abs(x1 - x2) <= @birth_radius and abs(y1 - y2) <= @birth_radius
  end

  defp increment_births do
    case :ets.lookup(@table, :stats) do
      [{:stats, s}] -> :ets.insert(@table, {:stats, %{s | births: s.births + 1}})
      _ -> :ok
    end
  end
end
