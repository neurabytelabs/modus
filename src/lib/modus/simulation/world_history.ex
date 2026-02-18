defmodule Modus.Simulation.WorldHistory do
  @moduledoc """
  WorldHistory — Automatic era detection and world history tracking.

  Analyzes simulation events to detect historical eras and maintain a structured
  world history with key figures, era transitions, and exportable chronicles.

  ## Spinoza: *Sub specie aeternitatis* — Under the aspect of eternity.
  """
  use GenServer

  @era_check_interval 200  # Check for era transitions every N ticks

  defstruct eras: [],
            current_era: nil,
            era_start_tick: 0,
            key_figures: %{},
            era_events: %{},
            last_check_tick: 0,
            metrics_window: []  # recent {tick, births, deaths, pop, trades, conflicts} snapshots

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc "Get all eras (completed + current)."
  @spec get_eras() :: [map()]
  def get_eras do
    GenServer.call(__MODULE__, :get_eras)
  end

  @doc "Get the current era."
  @spec current_era() :: map() | nil
  def current_era do
    GenServer.call(__MODULE__, :current_era)
  end

  @doc "Get events for a specific era."
  @spec era_events(String.t()) :: [map()]
  def era_events(era_id) do
    GenServer.call(__MODULE__, {:era_events, era_id})
  end

  @doc "Get key figures across all eras."
  @spec key_figures() :: [map()]
  def key_figures do
    GenServer.call(__MODULE__, :key_figures)
  end

  @doc "Export full world history as 'Chronicle of [World]' markdown."
  @spec export_chronicle(String.t()) :: String.t()
  def export_chronicle(world_name \\ "This World") do
    GenServer.call(__MODULE__, {:export_chronicle, world_name})
  end

  @doc "Get a summary string for LLM context injection."
  @spec history_context() :: String.t()
  def history_context do
    GenServer.call(__MODULE__, :history_context)
  end

  @doc "Record a metrics snapshot for era detection."
  @spec record_metrics(map()) :: :ok
  def record_metrics(metrics) do
    GenServer.cast(__MODULE__, {:record_metrics, metrics})
  end

  @doc "Record a notable figure's achievement."
  @spec record_figure(String.t(), String.t(), atom()) :: :ok
  def record_figure(agent_name, achievement, category \\ :general) do
    GenServer.cast(__MODULE__, {:record_figure, agent_name, achievement, category})
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    Phoenix.PubSub.subscribe(Modus.PubSub, "modus:events")

    # Start with "The Founding" era
    lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
    founding = %{
      id: "founding",
      name: Modus.I18n.era_name(lang, :founding),
      emoji: "🏛️",
      start_tick: 0,
      end_tick: nil,
      description: "The world begins. First souls appear on virgin ground.",
      color: "purple"
    }

    {:ok, %{state | current_era: founding, era_start_tick: 0, era_events: %{"founding" => []}}}
  end

  @impl true
  def handle_call(:get_eras, _from, state) do
    all = case state.current_era do
      nil -> Enum.reverse(state.eras)
      current -> Enum.reverse([current | state.eras])
    end
    {:reply, all, state}
  end

  @impl true
  def handle_call(:current_era, _from, state) do
    {:reply, state.current_era, state}
  end

  @impl true
  def handle_call({:era_events, era_id}, _from, state) do
    events = Map.get(state.era_events, era_id, []) |> Enum.reverse()
    {:reply, events, state}
  end

  @impl true
  def handle_call(:key_figures, _from, state) do
    figures = state.key_figures
    |> Enum.map(fn {name, data} ->
      %{name: name, achievements: data.achievements, era: data.era, category: data.category}
    end)
    |> Enum.sort_by(fn f -> -length(f.achievements) end)
    {:reply, figures, state}
  end

  @impl true
  def handle_call({:export_chronicle, world_name}, _from, state) do
    md = build_chronicle_markdown(world_name, state)
    {:reply, md, state}
  end

  @impl true
  def handle_call(:history_context, _from, state) do
    ctx = build_history_context(state)
    {:reply, ctx, state}
  end

  @impl true
  def handle_cast({:record_metrics, metrics}, state) do
    window = [{metrics.tick, metrics} | state.metrics_window]
    |> Enum.take(50)

    state = %{state | metrics_window: window}

    # Check for era transition
    state = if metrics.tick - state.last_check_tick >= @era_check_interval do
      check_era_transition(state, metrics)
    else
      state
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:record_figure, agent_name, achievement, category}, state) do
    era_id = if state.current_era, do: state.current_era.id, else: "unknown"

    existing = Map.get(state.key_figures, agent_name, %{
      achievements: [],
      era: era_id,
      category: category
    })

    updated = %{existing |
      achievements: Enum.take([achievement | existing.achievements], 10),
      era: era_id
    }

    {:noreply, %{state | key_figures: Map.put(state.key_figures, agent_name, updated)}}
  end

  @impl true
  def handle_info({:tick, _tick}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event}, state) do
    # Track events for current era
    state = if state.current_era do
      era_id = state.current_era.id
      events = Map.get(state.era_events, era_id, [])
      entry = %{
        tick: event.tick,
        type: event.type,
        summary: event_summary(event),
        emoji: event_emoji(event.type)
      }
      # Keep max 100 events per era
      updated = Enum.take([entry | events], 100)
      %{state | era_events: Map.put(state.era_events, era_id, updated)}
    else
      state
    end

    # Track key figures from events
    state = track_figures_from_event(event, state)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Era Detection ───────────────────────────────────────

  defp check_era_transition(state, metrics) do
    detected = detect_era(state, metrics)

    case detected do
      nil ->
        %{state | last_check_tick: metrics.tick}

      new_era ->
        # Close current era
        closed = %{state.current_era | end_tick: metrics.tick}
        eras = [closed | state.eras]

        # Broadcast era change
        Phoenix.PubSub.broadcast(Modus.PubSub, "story", {:era_change, new_era})

        %{state |
          eras: eras,
          current_era: new_era,
          era_start_tick: metrics.tick,
          era_events: Map.put(state.era_events, new_era.id, []),
          last_check_tick: metrics.tick
        }
    end
  end

  defp detect_era(state, metrics) do
    current_id = if state.current_era, do: state.current_era.id, else: nil
    tick = metrics.tick
    pop = Map.get(metrics, :population, 0) || 0
    _births = Map.get(metrics, :births, 0) || 0
    _deaths = Map.get(metrics, :deaths, 0) || 0
    _trades = Map.get(metrics, :trades, 0) || 0
    conflicts = Map.get(metrics, :conflicts, 0) || 0

    # Calculate rates from metrics window
    {death_rate, birth_rate, trade_rate} = calculate_rates(state.metrics_window)

    era_duration = tick - state.era_start_tick

    cond do
      # Don't transition too quickly (min 500 ticks per era)
      era_duration < 500 ->
        nil

      # Great Famine: high death rate, low population
      current_id != "famine" and death_rate > 0.3 and pop < 8 ->
        lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
        %{
          id: "famine_#{tick}",
          name: Modus.I18n.era_name(lang, :famine),
          emoji: "💀",
          start_tick: tick,
          end_tick: nil,
          description: "Death sweeps the land. Resources dwindle, hope fades.",
          color: "red"
        }

      # Expansion: growing population, many births
      current_id != "expansion" and birth_rate > 0.25 and pop > 12 ->
        lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
        %{
          id: "expansion_#{tick}",
          name: Modus.I18n.era_name(lang, :expansion),
          emoji: "🌱",
          start_tick: tick,
          end_tick: nil,
          description: "The population swells. New life everywhere, the world grows.",
          color: "green"
        }

      # Golden Age: high trade, low conflict, stable population
      current_id != "golden_age" and trade_rate > 0.2 and death_rate < 0.1 and pop > 10 ->
        lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
        %{
          id: "golden_age_#{tick}",
          name: Modus.I18n.era_name(lang, :golden_age),
          emoji: "✨",
          start_tick: tick,
          end_tick: nil,
          description: "Prosperity reigns. Trade flourishes, peace holds, and the world thrives.",
          color: "yellow"
        }

      # Renaissance: after a famine or conflict era, recovery with trade
      is_binary(current_id) and (String.starts_with?(current_id, "famine_") or String.starts_with?(current_id, "conflict_")) and birth_rate > 0.15 and trade_rate > 0.1 ->
        lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
        %{
          id: "renaissance_#{tick}",
          name: Modus.I18n.era_name(lang, :renaissance),
          emoji: "🎨",
          start_tick: tick,
          end_tick: nil,
          description: "From the ashes, renewal. Art, trade, and life bloom again.",
          color: "cyan"
        }

      # Age of Conflict: high conflict rate
      current_id != "conflict" and conflicts > 5 and death_rate > 0.2 ->
        lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
        %{
          id: "conflict_#{tick}",
          name: Modus.I18n.era_name(lang, :conflict),
          emoji: "⚔️",
          start_tick: tick,
          end_tick: nil,
          description: "War and strife tear at the social fabric. Only the strong survive.",
          color: "orange"
        }

      # Long peace after golden age transitions back to expansion
      current_id not in [nil, "founding", "expansion"] and era_duration > 2000 and pop > 8 and death_rate < 0.15 ->
        lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
        %{
          id: "expansion_#{tick}",
          name: Modus.I18n.era_name(lang, :expansion),
          emoji: "🌱",
          start_tick: tick,
          end_tick: nil,
          description: "The population swells once more. A new chapter of growth begins.",
          color: "green"
        }

      true ->
        nil
    end
  end

  defp calculate_rates(window) when length(window) < 3, do: {0.0, 0.0, 0.0}
  defp calculate_rates(window) do
    recent = Enum.take(window, 10) |> Enum.map(&elem(&1, 1))
    total_deaths = recent |> Enum.map(& &1[:deaths] || 0) |> Enum.sum()
    total_births = recent |> Enum.map(& &1[:births] || 0) |> Enum.sum()
    total_trades = recent |> Enum.map(& &1[:trades] || 0) |> Enum.sum()
    n = length(recent)

    {total_deaths / max(n, 1), total_births / max(n, 1), total_trades / max(n, 1)}
  end

  # ── Figure Tracking ─────────────────────────────────────

  defp track_figures_from_event(event, state) do
    case event.type do
      :trade ->
        name = event.data[:name] || event.data[:trader]
        if name, do: record_figure_internal(state, to_string(name), "Completed a trade", :merchant), else: state

      :building_upgrade ->
        name = event.data[:name]
        level = event.data[:level] || 2
        if name, do: record_figure_internal(state, to_string(name), "Built to level #{level}", :builder), else: state

      :death ->
        # Track those who lived long
        name = event.data[:name]
        age = event.data[:age] || event.data[:ticks_lived]
        if name && age && age > 2000 do
          record_figure_internal(state, to_string(name), "Lived #{age} ticks — an elder", :elder)
        else
          state
        end

      _ -> state
    end
  end

  defp record_figure_internal(state, name, achievement, category) do
    era_id = if state.current_era, do: state.current_era.id, else: "unknown"
    existing = Map.get(state.key_figures, name, %{achievements: [], era: era_id, category: category})
    updated = %{existing | achievements: Enum.take([achievement | existing.achievements], 10), era: era_id}
    %{state | key_figures: Map.put(state.key_figures, name, updated)}
  end

  # ── Event Helpers ───────────────────────────────────────

  defp event_summary(event) do
    case event.type do
      :birth -> "#{event.data[:name] || "Someone"} was born"
      :death -> "#{event.data[:name] || "Someone"} died (#{event.data[:cause] || "unknown"})"
      :trade -> "A trade occurred"
      :conflict -> "Conflict erupted"
      :season_change -> "Season changed to #{event.data[:season]}"
      :world_event -> "#{event.data[:type]} (severity #{event.data[:severity] || 1})"
      :building_upgrade -> "#{event.data[:name]} upgraded to level #{event.data[:level]}"
      :neighborhood_formed -> "#{event.data[:name]} neighborhood formed"
      :migration -> "A migrant arrived"
      _ -> "#{event.type}"
    end
  end

  defp event_emoji(:birth), do: "👶"
  defp event_emoji(:death), do: "💀"
  defp event_emoji(:trade), do: "🤝"
  defp event_emoji(:conflict), do: "⚔️"
  defp event_emoji(:season_change), do: "🍃"
  defp event_emoji(:world_event), do: "🌍"
  defp event_emoji(:building_upgrade), do: "⬆️"
  defp event_emoji(:neighborhood_formed), do: "🏘️"
  defp event_emoji(:migration), do: "🚶"
  defp event_emoji(_), do: "⚡"

  # ── History Context for LLM ─────────────────────────────

  defp build_history_context(state) do
    eras = case state.current_era do
      nil -> Enum.reverse(state.eras)
      current -> Enum.reverse([current | state.eras])
    end

    if eras == [] do
      ""
    else
      era_lines = eras
      |> Enum.map(fn era ->
        status = if era.end_tick, do: "ended at tick #{era.end_tick}", else: "ongoing"
        "- #{era.emoji} #{era.name} (tick #{era.start_tick}, #{status})"
      end)
      |> Enum.join("\n")

      figures = state.key_figures
      |> Enum.take(5)
      |> Enum.map(fn {name, data} ->
        "- #{name}: #{List.first(data.achievements) || "notable figure"}"
      end)
      |> Enum.join("\n")

      ctx = "World History:\n#{era_lines}"
      if figures != "" do
        ctx <> "\n\nKey Figures:\n#{figures}"
      else
        ctx
      end
    end
  end

  # ── Chronicle Export ────────────────────────────────────

  defp build_chronicle_markdown(world_name, state) do
    eras = case state.current_era do
      nil -> Enum.reverse(state.eras)
      current -> Enum.reverse([current | state.eras])
    end

    header = """
    # Chronicle of #{world_name}

    > *Sub specie aeternitatis — Under the aspect of eternity.*
    > — Spinoza

    ---

    """

    era_sections = eras
    |> Enum.map(fn era ->
      duration = if era.end_tick do
        "Ticks #{era.start_tick} – #{era.end_tick} (#{era.end_tick - era.start_tick} ticks)"
      else
        "Tick #{era.start_tick} – present (ongoing)"
      end

      events = Map.get(state.era_events, era.id, []) |> Enum.reverse() |> Enum.take(20)
      event_lines = if events == [] do
        "_No recorded events._"
      else
        events
        |> Enum.map(fn e -> "- #{e.emoji} **[t:#{e.tick}]** #{e.summary}" end)
        |> Enum.join("\n")
      end

      # Key figures for this era
      era_figures = state.key_figures
      |> Enum.filter(fn {_name, data} -> data.era == era.id end)
      |> Enum.map(fn {name, data} ->
        achievements = Enum.join(data.achievements, ", ")
        "- **#{name}**: #{achievements}"
      end)

      figures_section = if era_figures == [] do
        ""
      else
        "\n### Key Figures\n\n#{Enum.join(era_figures, "\n")}\n"
      end

      """
      ## #{era.emoji} #{era.name}

      _#{era.description}_

      **#{duration}**

      ### Events

      #{event_lines}
      #{figures_section}
      ---

      """
    end)
    |> Enum.join("\n")

    footer = """

    ---

    _Chronicle generated by MODUS — Where Spinoza Meets Silicon_
    _#{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y at %H:%M UTC")}_
    """

    header <> era_sections <> footer
  end
end
