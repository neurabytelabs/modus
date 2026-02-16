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
  @birth_check_interval 50

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
    if rem(tick_number, @birth_check_interval) == 0 do
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
      "Yeni", "Umut", "Bahar", "Güneş", "Toprak", "Bulut",
      "Nehir", "Rüzgar", "Yıldız", "Çınar", "Atlas", "Nil",
      "Masal", "Ekin", "Derin", "Asya", "Ege", "Ada"
    ]

    name = Enum.random(names)
    occupation = Enum.random([:farmer, :builder, :explorer, :healer, :trader])
    child = Modus.Simulation.Agent.new(name, child_pos, occupation)

    case Modus.Simulation.AgentSupervisor.spawn_agent(child) do
      {:ok, _pid} ->
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
