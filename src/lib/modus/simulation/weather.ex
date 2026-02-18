defmodule Modus.Simulation.Weather do
  @moduledoc """
  Weather — Dynamic weather engine for the MODUS world.

  v4.4.0 Caelum: "Even the gods cannot control the weather."

  Weather types: clear, cloudy, rain, storm, snow, fog, wind, heatwave.
  Season-linked probabilities, micro-climates per biome, multi-tick weather events,
  shelter bonus, forecast lookahead, and agent mood/speed effects.

  ## ETS Storage
  State stored in `:modus_weather` for fast reads.
  """
  use GenServer

  alias Modus.Simulation.{Seasons, EventLog}

  @table :modus_weather
  @pubsub Modus.PubSub
  @topic "modus:weather"

  @weather_config %{
    clear:    %{emoji: "☀️",  name: "Clear",    move_mod: 1.0,  gather_mod: 1.1, mood_mod: 0.05,  crop_mod: 1.0,  duration: {20, 80}},
    cloudy:   %{emoji: "☁️",  name: "Cloudy",   move_mod: 1.0,  gather_mod: 1.0, mood_mod: 0.0,   crop_mod: 0.9,  duration: {15, 60}},
    rain:     %{emoji: "🌧️", name: "Rain",     move_mod: 0.8,  gather_mod: 0.7, mood_mod: -0.05, crop_mod: 1.3,  duration: {10, 50}},
    storm:    %{emoji: "⛈️", name: "Storm",    move_mod: 0.5,  gather_mod: 0.3, mood_mod: -0.15, crop_mod: 0.5,  duration: {5, 20}},
    snow:     %{emoji: "🌨️", name: "Snow",     move_mod: 0.6,  gather_mod: 0.5, mood_mod: -0.08, crop_mod: 0.2,  duration: {15, 60}},
    fog:      %{emoji: "🌫️", name: "Fog",      move_mod: 0.7,  gather_mod: 0.8, mood_mod: -0.03, crop_mod: 0.8,  duration: {10, 40}},
    wind:     %{emoji: "💨",  name: "Wind",     move_mod: 0.85, gather_mod: 0.9, mood_mod: -0.02, crop_mod: 0.9,  duration: {10, 30}},
    heatwave: %{emoji: "🔥",  name: "Heatwave", move_mod: 0.75, gather_mod: 0.6, mood_mod: -0.10, crop_mod: 0.4,  duration: {10, 40}}
  }

  # Season → weather probability weights
  @season_weights %{
    spring:  %{clear: 20, cloudy: 25, rain: 30, storm: 5, snow: 2, fog: 10, wind: 5, heatwave: 3},
    summer:  %{clear: 35, cloudy: 15, rain: 10, storm: 8, snow: 0, fog: 5, wind: 7, heatwave: 20},
    autumn:  %{clear: 15, cloudy: 30, rain: 20, storm: 5, snow: 5, fog: 15, wind: 8, heatwave: 2},
    winter:  %{clear: 10, cloudy: 20, rain: 10, storm: 3, snow: 35, fog: 12, wind: 8, heatwave: 2}
  }

  # Biome micro-climate adjustments (additive weights)
  # Biome micro-climate adjustments — used by biome_weather/1
  @biome_adjustments %{
    desert:   %{heatwave: 15, clear: 10, rain: -10, snow: -20},
    tundra:   %{snow: 20, heatwave: -15, clear: -5},
    forest:   %{fog: 10, rain: 5, heatwave: -5},
    swamp:    %{fog: 15, rain: 10, clear: -10},
    mountain: %{wind: 15, storm: 10, snow: 10, heatwave: -10},
    ocean:    %{storm: 10, wind: 10, rain: 5},
    plains:   %{}
  }

  # Severe multi-tick events
  @severe_events %{
    hurricane: %{emoji: "🌀", name: "Hurricane", base: :storm, duration: {30, 80}, move_mod: 0.3, gather_mod: 0.1, mood_mod: -0.25, crop_mod: 0.1},
    blizzard:  %{emoji: "❄️", name: "Blizzard",  base: :snow,  duration: {25, 70}, move_mod: 0.3, gather_mod: 0.1, mood_mod: -0.20, crop_mod: 0.0},
    drought:   %{emoji: "☀️", name: "Drought",   base: :heatwave, duration: {50, 150}, move_mod: 0.9, gather_mod: 0.4, mood_mod: -0.12, crop_mod: 0.1}
  }

  defstruct current: :clear,
            ticks_remaining: 50,
            severe_event: nil,
            severe_ticks: 0,
            total_ticks: 0,
            history: []

  # ── Public API ──────────────────────────────────────────────

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc "Get current weather state."
  @spec get_state() :: map()
  def get_state do
    case :ets.lookup(@table, :state) do
      [{:state, state}] -> state
      _ -> %{current: :clear, severe_event: nil, total_ticks: 0}
    end
  end

  @doc "Get current weather type."
  @spec current() :: atom()
  def current do
    get_state() |> Map.get(:current, :clear)
  end

  @doc "Get weather config for a specific type."
  @spec config_for(atom()) :: map()
  def config_for(weather_type) do
    Map.get(@weather_config, weather_type, Map.get(@weather_config, :clear))
  end

  @doc "Get current weather effects (movement, gathering, mood, crop modifiers)."
  @spec effects() :: map()
  def effects do
    state = get_state()
    case state[:severe_event] do
      nil -> config_for(state[:current] || :clear)
      event -> Map.get(@severe_events, event, config_for(:clear))
    end
  end

  @doc "Movement speed modifier (0.0-1.0+). Factor in shelter."
  @spec movement_modifier(boolean()) :: float()
  def movement_modifier(in_shelter \\ false) do
    if in_shelter, do: 1.0, else: ensure_float(effects().move_mod)
  end

  @doc "Resource gathering modifier."
  @spec gather_modifier(boolean()) :: float()
  def gather_modifier(in_shelter \\ false) do
    if in_shelter, do: 1.0, else: ensure_float(effects().gather_mod)
  end

  @doc "Mood modifier."
  @spec mood_modifier(boolean()) :: float()
  def mood_modifier(in_shelter \\ false) do
    if in_shelter, do: 0.0, else: ensure_float(effects().mood_mod)
  end

  @doc "Crop growth modifier."
  @spec crop_modifier() :: float()
  def crop_modifier do
    ensure_float(effects().crop_mod)
  end

  @doc "Get most likely weather for a biome (micro-climate weighted pick)."
  @spec biome_weather(atom()) :: atom()
  def biome_weather(biome) do
    season = safe_current_season()
    base_weights = Map.get(@season_weights, season, Map.get(@season_weights, :spring))
    adjustments = Map.get(@biome_adjustments, biome, %{})

    merged = Enum.reduce(adjustments, base_weights, fn {k, v}, acc ->
      Map.update(acc, k, max(v, 0), &max(&1 + v, 0))
    end)

    weighted_pick(merged)
  end

  @doc "Forecast next N weather transitions (probabilistic lookahead)."
  @spec forecast(non_neg_integer()) :: [map()]
  def forecast(ticks_ahead \\ 100) do
    state = get_state()
    season = safe_current_season()
    remaining = state[:ticks_remaining] || 0
    current = state[:current] || :clear

    generate_forecast(current, season, remaining, ticks_ahead, [])
  end

  @doc "Serialize for client."
  @spec serialize() :: map()
  def serialize do
    state = get_state()
    current = state[:current] || :clear
    cfg = config_for(current)
    severe = state[:severe_event]
    severe_cfg = if severe, do: Map.get(@severe_events, severe), else: nil

    %{
      current: Atom.to_string(current),
      name: if(severe_cfg, do: severe_cfg.name, else: cfg.name),
      emoji: if(severe_cfg, do: severe_cfg.emoji, else: cfg.emoji),
      move_mod: ensure_float(if(severe_cfg, do: severe_cfg.move_mod, else: cfg.move_mod)),
      gather_mod: ensure_float(if(severe_cfg, do: severe_cfg.gather_mod, else: cfg.gather_mod)),
      mood_mod: ensure_float(if(severe_cfg, do: severe_cfg.mood_mod, else: cfg.mood_mod)),
      crop_mod: ensure_float(if(severe_cfg, do: severe_cfg.crop_mod, else: cfg.crop_mod)),
      severe_event: if(severe, do: Atom.to_string(severe), else: nil),
      ticks_remaining: state[:ticks_remaining] || 0,
      forecast: forecast(100) |> Enum.map(fn f ->
        %{weather: Atom.to_string(f.weather), emoji: f.emoji, at_tick: f.at_tick}
      end)
    }
  end

  # ── GenServer ───────────────────────────────────────────────

  @impl true
  def init(state) do
    # Create ETS table
    try do
      :ets.new(@table, [:set, :public, :named_table])
    catch
      :error, :badarg -> :ok  # already exists
    end

    initial = %{state | current: :clear, ticks_remaining: 30 + :rand.uniform(50)}
    store_state(initial)

    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    {:ok, initial}
  end

  @impl true
  def handle_info({:tick, _tick_number}, state) do
    new_total = state.total_ticks + 1
    new_remaining = state.ticks_remaining - 1

    new_state = cond do
      # Severe event ongoing
      state.severe_event != nil and state.severe_ticks > 0 ->
        %{state | severe_ticks: state.severe_ticks - 1, ticks_remaining: new_remaining, total_ticks: new_total}

      # Severe event ended
      state.severe_event != nil and state.severe_ticks <= 0 ->
        next = pick_next_weather()
        {min_d, max_d} = Map.get(@weather_config, next, %{duration: {20, 50}}).duration
        dur = min_d + :rand.uniform(max(max_d - min_d, 1))

        broadcast_change(next, nil)
        %{state | current: next, ticks_remaining: dur, severe_event: nil, severe_ticks: 0,
          total_ticks: new_total, history: add_history(state.history, next)}

      # Normal weather expired
      new_remaining <= 0 ->
        {next, severe} = pick_next_weather_or_event()
        case severe do
          nil ->
            {min_d, max_d} = Map.get(@weather_config, next, %{duration: {20, 50}}).duration
            dur = min_d + :rand.uniform(max(max_d - min_d, 1))
            broadcast_change(next, nil)
            %{state | current: next, ticks_remaining: dur, severe_event: nil,
              total_ticks: new_total, history: add_history(state.history, next)}

          event ->
            ecfg = Map.get(@severe_events, event)
            {min_d, max_d} = ecfg.duration
            dur = min_d + :rand.uniform(max(max_d - min_d, 1))
            broadcast_change(ecfg.base, event)
            log_severe_event(event, new_total)
            %{state | current: ecfg.base, ticks_remaining: dur, severe_event: event,
              severe_ticks: dur, total_ticks: new_total, history: add_history(state.history, event)}
        end

      # Weather continues
      true ->
        %{state | ticks_remaining: new_remaining, total_ticks: new_total}
    end

    store_state(new_state)
    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ─────────────────────────────────────────────────

  defp store_state(state) do
    :ets.insert(@table, {:state, %{
      current: state.current,
      severe_event: state.severe_event,
      ticks_remaining: state.ticks_remaining,
      total_ticks: state.total_ticks
    }})
  end

  defp pick_next_weather do
    season = safe_current_season()
    weights = Map.get(@season_weights, season, Map.get(@season_weights, :spring))
    weighted_pick(weights)
  end

  defp pick_next_weather_or_event do
    next = pick_next_weather()
    # 3% chance of severe event
    if :rand.uniform(100) <= 3 do
      season = safe_current_season()
      event = case season do
        :winter -> :blizzard
        :summer -> Enum.random([:hurricane, :drought])
        _ -> if(:rand.uniform(2) == 1, do: :hurricane, else: :drought)
      end
      {Map.get(@severe_events, event).base, event}
    else
      {next, nil}
    end
  end

  defp weighted_pick(weights) do
    # Ensure no negative weights
    clean = Enum.map(weights, fn {k, v} -> {k, max(v, 0)} end)
    total = Enum.reduce(clean, 0, fn {_k, v}, acc -> acc + v end)

    if total <= 0 do
      :clear
    else
      roll = :rand.uniform(total)
      pick_from_weights(clean, roll, 0)
    end
  end

  defp pick_from_weights([], _roll, _acc), do: :clear
  defp pick_from_weights([{weather, weight} | rest], roll, acc) do
    new_acc = acc + weight
    if roll <= new_acc, do: weather, else: pick_from_weights(rest, roll, new_acc)
  end

  defp safe_current_season do
    try do
      Seasons.current_season()
    catch
      _, _ -> :spring
    end
  end

  defp broadcast_change(weather, severe_event) do
    cfg = config_for(weather)
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:weather_change, weather, severe_event, cfg})
  end

  defp log_severe_event(event, tick) do
    ecfg = Map.get(@severe_events, event)
    EventLog.log(:severe_weather, tick, [], %{
      event: event,
      name: ecfg.name,
      emoji: ecfg.emoji
    })
  end

  defp add_history(history, weather) do
    Enum.take([weather | history], 20)
  end

  defp generate_forecast(_current, _season, _remaining, ticks_ahead, acc) when ticks_ahead <= 0 do
    Enum.reverse(acc)
  end

  defp generate_forecast(current, season, remaining, ticks_ahead, acc) do
    if remaining >= ticks_ahead do
      cfg = config_for(current)
      entry = %{weather: current, emoji: cfg.emoji, at_tick: ticks_ahead}
      Enum.reverse([entry | acc])
    else
      cfg = config_for(current)
      entry = %{weather: current, emoji: cfg.emoji, at_tick: remaining}

      weights = Map.get(@season_weights, season, Map.get(@season_weights, :spring))
      next = weighted_pick(weights)
      next_cfg = config_for(next)
      {min_d, max_d} = next_cfg.duration
      next_dur = min_d + div(max_d - min_d, 2)  # use average for forecast

      generate_forecast(next, season, next_dur, ticks_ahead - remaining, [entry | acc])
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
