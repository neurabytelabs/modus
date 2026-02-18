defmodule Modus.Simulation.EventProbability do
  @moduledoc """
  EventProbability — Context-aware event probability system.

  Calculates event probabilities based on:
  - Current season (drought more likely in summer, flood in spring)
  - Population happiness (festivals when happy, conflicts when miserable)
  - Resource scarcity (famine when food low)
  - Time since last event (cooldown to avoid spam)
  - Population size (more people = more events)

  ## Spinoza: *Sub specie aeternitatis* — All events follow from necessity.
  """

  @season_modifiers %{
    spring: %{flood: 1.5, discovery: 1.3, festival: 1.2, drought: 0.3},
    summer: %{drought: 2.0, fire: 1.8, festival: 1.0, flood: 0.2},
    autumn: %{storm: 1.5, migration_wave: 1.5, festival: 1.3, drought: 0.5},
    winter: %{famine: 1.8, plague: 1.5, storm: 1.3, fire: 0.3, drought: 0.2}
  }

  @base_probabilities %{
    storm: 0.015,
    earthquake: 0.005,
    meteor_shower: 0.003,
    plague: 0.008,
    golden_age: 0.01,
    flood: 0.01,
    fire: 0.012,
    drought: 0.01,
    famine: 0.008,
    festival: 0.015,
    discovery: 0.012,
    migration_wave: 0.01,
    conflict: 0.008
  }

  @doc "Calculate probability of each event type given world context."
  @spec calculate(map()) :: [{atom(), float()}]
  def calculate(context) do
    season = Map.get(context, :season, :spring)
    happiness = Map.get(context, :avg_happiness, 0.5)
    population = Map.get(context, :population, 10)
    food_ratio = Map.get(context, :food_ratio, 1.0)
    ticks_since_last = Map.get(context, :ticks_since_last_event, 100)

    season_mods = Map.get(@season_modifiers, season, %{})

    # Cooldown: reduce probability if recent event
    cooldown_mod = min(1.0, ticks_since_last / 50.0)

    # Population modifier: more people = slightly more events
    pop_mod = min(2.0, 0.5 + population / 20.0)

    @base_probabilities
    |> Enum.map(fn {event, base_prob} ->
      season_mod = Map.get(season_mods, event, 1.0)

      # Context-specific modifiers
      context_mod = case event do
        :festival -> if happiness > 0.7, do: 2.0, else: if(happiness < 0.3, do: 0.1, else: 1.0)
        :conflict -> if happiness < 0.3, do: 2.0, else: if(happiness > 0.7, do: 0.2, else: 1.0)
        :famine -> if food_ratio < 0.3, do: 2.5, else: if(food_ratio > 0.8, do: 0.2, else: 1.0)
        :golden_age -> if happiness > 0.8, do: 2.5, else: if(happiness < 0.5, do: 0.1, else: 1.0)
        :migration_wave -> if population < 5, do: 2.0, else: if(population > 30, do: 0.5, else: 1.0)
        :discovery -> if population > 5, do: 1.5, else: 0.5
        _ -> 1.0
      end

      final_prob = base_prob * season_mod * context_mod * cooldown_mod * pop_mod
      {event, min(0.5, final_prob)}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  @doc "Roll for a random event based on context. Returns nil or {event_type, severity}."
  @spec roll(map()) :: nil | {atom(), non_neg_integer()}
  def roll(context) do
    probabilities = calculate(context)

    result = Enum.find(probabilities, fn {_event, prob} ->
      :rand.uniform() < prob
    end)

    case result do
      {event, _prob} ->
        severity = weighted_severity()
        {event, severity}
      nil -> nil
    end
  end

  defp weighted_severity do
    r = :rand.uniform(100)
    cond do
      r <= 60 -> 1  # 60% minor
      r <= 90 -> 2  # 30% moderate
      true -> 3     # 10% severe
    end
  end

  @doc "Get base probabilities map."
  def base_probabilities, do: @base_probabilities
end
