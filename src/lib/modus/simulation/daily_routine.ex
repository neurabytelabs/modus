defmodule Modus.Simulation.DailyRoutine do
  @moduledoc """
  DailyRoutine — Agent daily schedule with sleep cycles.

  "Even the soul needs rest" — Spinoza

  Agents follow a natural rhythm tied to the Environment day/night cycle:
  - **Dawn (0.00-0.15):** Wake up, eat breakfast, plan the day
  - **Day (0.15-0.45):** Work and primary activities
  - **Dusk (0.45-0.55):** Evening social gathering
  - **Night (0.55-0.95):** Sleep (energy restoration)
  - **Pre-dawn (0.95-1.00):** Deep sleep / dream phase

  Nocturnal agents invert this schedule.

  Energy system:
  - Activity drains energy (0.001-0.005 per tick depending on action)
  - Sleep restores energy (+0.008 per tick indoors, +0.004 outdoors)
  - Exhaustion (<0.1 energy) causes mood/performance penalties
  """

  alias Modus.Simulation.{Environment, Building, EventLog}

  @energy_drain %{
    moving: 0.003,
    exploring: 0.004,
    gathering: 0.005,
    building: 0.005,
    crafting: 0.004,
    trading: 0.002,
    talking: 0.001,
    sleeping: 0.0,
    idle: 0.001,
    fleeing: 0.006
  }

  @indoor_sleep_restore 0.008
  @outdoor_sleep_restore 0.004
  @exhaustion_threshold 0.1
  @sleep_threshold 0.3
  @nocturnal_chance 0.15

  # ── Public API ──────────────────────────────────────────────

  @doc "Determine if an agent is nocturnal based on personality."
  @spec nocturnal?(map()) :: boolean()
  def nocturnal?(personality) do
    # High openness + low conscientiousness → more likely nocturnal
    openness = Map.get(personality, :openness, 0.5) |> ensure_float()
    conscientiousness = Map.get(personality, :conscientiousness, 0.5) |> ensure_float()
    score = openness * 0.6 + (1.0 - conscientiousness) * 0.4
    score > 1.0 - @nocturnal_chance
  end

  @doc "Get the current day phase from Environment."
  @spec current_phase() :: :dawn | :day | :dusk | :night | :predawn
  def current_phase do
    try do
      env = Environment.get_state()
      Map.get(env, :day_phase, :day)
    catch
      :exit, _ -> :day
    end
  end

  @doc "Get recommended action for an agent based on time and state."
  @spec recommend_action(map()) :: {:override, atom(), map()} | :no_override
  def recommend_action(agent) do
    phase = current_phase()
    is_nocturnal = nocturnal?(agent.personality || %{})
    energy = agent.conatus_energy |> ensure_float()
    rest = Map.get(agent.needs || %{}, :rest, 50.0) |> ensure_float()

    # Invert phases for nocturnal agents
    effective_phase = if is_nocturnal, do: invert_phase(phase), else: phase

    cond do
      # Exhaustion override — must sleep regardless
      energy < @exhaustion_threshold and agent.current_action != :sleeping ->
        {:override, :sleep, %{reason: :exhaustion}}

      # Night phase — should sleep
      effective_phase in [:night, :predawn] and rest < 70.0 ->
        {:override, :sleep, %{reason: :night_cycle}}

      # Dawn — morning routine (eat if hungry)
      effective_phase == :dawn and Map.get(agent.needs, :hunger, 0.0) > 40.0 ->
        {:override, :gather, %{reason: :morning_meal}}

      # Dusk — social gathering
      effective_phase == :dusk and Map.get(agent.needs, :social, 50.0) < 60.0 ->
        {:override, :socialize, %{reason: :evening_social}}

      # Low energy during day — take a nap
      energy < @sleep_threshold and effective_phase == :day ->
        {:override, :sleep, %{reason: :nap}}

      true ->
        :no_override
    end
  end

  @doc "Apply energy drain based on current action."
  @spec drain_energy(map(), atom()) :: map()
  def drain_energy(agent, action) do
    drain = Map.get(@energy_drain, action, 0.002) |> ensure_float()

    # Weather penalty: bad weather drains more energy
    weather_penalty = get_weather_penalty()
    total_drain = drain + weather_penalty

    new_energy = max(ensure_float(agent.conatus_energy) - total_drain, 0.0)
    %{agent | conatus_energy: new_energy}
  end

  @doc "Apply sleep restoration. Indoor sleep is more effective."
  @spec restore_from_sleep(map()) :: map()
  def restore_from_sleep(agent) do
    is_indoors = agent_has_home?(agent)
    restore = if is_indoors, do: @indoor_sleep_restore, else: @outdoor_sleep_restore

    new_energy = min(ensure_float(agent.conatus_energy) + restore, 1.0)
    rest_boost = if is_indoors, do: 15.0, else: 8.0
    new_rest = min(ensure_float(Map.get(agent.needs, :rest, 50.0)) + rest_boost, 100.0)

    new_needs = Map.put(agent.needs || %{}, :rest, new_rest)
    %{agent | conatus_energy: new_energy, needs: new_needs}
  end

  @doc "Apply exhaustion penalties to an exhausted agent."
  @spec apply_exhaustion_penalties(map()) :: map()
  def apply_exhaustion_penalties(agent) do
    energy = ensure_float(agent.conatus_energy)

    if energy < @exhaustion_threshold do
      # Mood penalty
      needs = agent.needs || %{}
      social_penalty = min(ensure_float(Map.get(needs, :social, 50.0)), 100.0) - 2.0
      new_needs = Map.put(needs, :social, max(social_penalty, 0.0))

      # Conatus drops when exhausted
      new_conatus = ensure_float(Map.get(agent, :conatus_score, 0.0)) - 0.1
      %{agent | needs: new_needs, conatus_score: max(new_conatus, -10.0)}
    else
      agent
    end
  end

  @doc "Check if agent should dream (sleeping + low energy restored enough)."
  @spec should_dream?(map()) :: boolean()
  def should_dream?(agent) do
    # 2% chance per tick while sleeping
    agent.current_action == :sleeping and
      ensure_float(agent.conatus_energy) > 0.5 and
      :rand.uniform() < 0.02
  end

  @doc "Generate a dream event description (fallback, no LLM)."
  @spec generate_dream(map()) :: String.t()
  def generate_dream(agent) do
    dreams = [
      "#{agent.name} rüyasında uçsuz bucaksız bir ovada yürüdüğünü gördü.",
      "#{agent.name} rüyasında eski bir dostla karşılaştı.",
      "#{agent.name} rüyasında parlak bir ışık gördü ve huzur hissetti.",
      "#{agent.name} rüyasında yeni topraklar keşfetti.",
      "#{agent.name} rüyasında büyük bir şölen vardı.",
      "#{agent.name} rüyasında gökyüzünde dans eden yıldızları izledi."
    ]

    Enum.random(dreams)
  end

  @doc "Process daily routine for a tick — called from agent tick."
  @spec process_tick(map(), atom(), integer()) :: map()
  def process_tick(agent, action, tick) do
    agent
    |> drain_energy(action)
    |> maybe_sleep_restore(action)
    |> apply_exhaustion_penalties()
    |> maybe_dream(tick)
  end

  # ── Private ─────────────────────────────────────────────────

  defp maybe_sleep_restore(agent, action) do
    if action == :sleep or agent.current_action == :sleeping do
      restore_from_sleep(agent)
    else
      agent
    end
  end

  defp maybe_dream(agent, tick) do
    if should_dream?(agent) do
      dream = generate_dream(agent)

      try do
        EventLog.log(:dream, tick, [agent.id], %{agent: agent.name, dream: dream})
      catch
        _, _ -> :ok
      end

      # Add dream to memory
      memory = agent.memory || []
      new_memory = [{tick, {:dream, dream}} | Enum.take(memory, 19)]
      %{agent | memory: new_memory}
    else
      agent
    end
  end

  defp agent_has_home?(agent) do
    try do
      home = Building.get_home(agent.id)
      home != nil
    catch
      _, _ -> false
    end
  end

  defp get_weather_penalty do
    try do
      weather = Modus.Simulation.Weather.current()

      case Map.get(weather, :type, :clear) do
        :storm -> 0.003
        :rain -> 0.001
        :snow -> 0.002
        :heatwave -> 0.002
        :blizzard -> 0.004
        _ -> 0.0
      end
    catch
      _, _ -> 0.0
    end
  end

  defp invert_phase(:dawn), do: :dusk
  defp invert_phase(:day), do: :night
  defp invert_phase(:dusk), do: :dawn
  defp invert_phase(:night), do: :day
  defp invert_phase(:predawn), do: :predawn

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
