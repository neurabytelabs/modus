defmodule ModusWeb.UniverseLive do
  @moduledoc """
  Main LiveView — MODUS universe dashboard with 2D renderer.
  v5.0.0 Forma — UI Design Overhaul with glassmorphism design system.
  """
  use ModusWeb, :live_view
  # JS alias available if needed

  alias Modus.Simulation.WorldTemplates
  alias Modus.Simulation.Observatory
  import ModusWeb.DashboardCharts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Modus.Simulation.EventLog.subscribe()
      Phoenix.PubSub.subscribe(Modus.PubSub, "story")
      Phoenix.PubSub.subscribe(Modus.PubSub, "world_events")
    end

    # Load saved worlds for dashboard
    saved_worlds =
      try do
        Modus.Persistence.WorldPersistence.list()
      catch
        _, _ -> []
      end

    # Always start at landing page
    initial_phase = :landing

    {:ok,
     assign(socket,
       page_title: "MODUS",
       # Dashboard
       dashboard_worlds: saved_worlds,
       dashboard_sort: "newest",
       dashboard_delete_confirm: nil,
       # Onboarding
       phase: initial_phase,
       template: "village",
       population: 10,
       danger: "normal",
       world_seed: "",
       grid_size: 100,
       world_language: "en",
       # Simulation
       status: :paused,
       tick: 0,
       agent_count: 0,
       speed: 1,
       time_of_day: "day",
       selected_agent: nil,
       show_add_goal: false,
       chat_open: false,
       chat_messages: [],
       chat_loading: false,
       chat_filter: "all",
       chat_context: [],
       pending_confirm: nil,
       # Settings
       settings_open: false,
       settings_provider:
         if(System.get_env("ANTIGRAVITY_API_KEY"), do: "antigravity", else: "ollama"),
       settings_model:
         if(System.get_env("ANTIGRAVITY_API_KEY"),
           do: "gemini-3-flash",
           else: "llama3.2:3b-instruct-q4_K_M"
         ),
       settings_base_url:
         if(System.get_env("ANTIGRAVITY_API_KEY"),
           do: "http://host.docker.internal:8045",
           else: "http://modus-llm:11434"
         ),
       settings_api_key: System.get_env("ANTIGRAVITY_API_KEY") || "",
       settings_test_result: nil,
       settings_saved: false,
       settings_testing: false,
       # Save/Load
       save_load_open: false,
       saved_worlds: [],
       save_slots: [],
       save_name: "",
       save_load_status: nil,
       selected_slot: 1,
       autosave_status: %{enabled: true, last_tick: 0, last_at: nil, interval: 500},
       # UI
       mind_view_active: false,
       # Seasons
       season_name: "Spring",
       season_emoji: "🌸",
       season_year: 1,
       day_phase: "day",
       # Weather
       weather_name: "Clear",
       weather_emoji: "☀️",
       # Deus — God Mode & Cinematic Camera
       god_mode: false,
       cinematic_mode: false,
       build_mode: false,
       build_brush: "grass",
       build_type: "terrain",
       mobile_panel: nil,
       event_feed: [],
       templates: WorldTemplates.all(),
       trades_count: 0,
       births_count: 0,
       deaths_count: 0,
       # Potentia — Story & Timeline
       timeline_open: false,
       timeline_entries: [],
       toasts: [],
       chronicle_open: false,
       chronicle_md: "",
       history_open: false,
       history_eras: [],
       history_selected_era: nil,
       history_era_events: [],
       history_figures: [],
       # Export & Share
       export_open: false,
       export_tab: :export,
       export_json: "",
       export_base64: "",
       export_status: nil,
       import_status: nil,
       stats_open: false,
       population_history: [],
       obs_world: %{
         population: 0,
         buildings: 0,
         trades: 0,
         births: 0,
         deaths: 0,
         avg_happiness: 0.0,
         avg_conatus: 0.0
       },
       obs_buildings: [],
       obs_leaderboards: %{most_social: [], wealthiest: [], oldest: [], happiest: []},
       obs_net_nodes: [],
       obs_net_edges: [],
       obs_happiness: [],
       obs_trades: [],
       obs_tab: :overview,
       # Agent Designer
       # Rules Engine
       rules_open: false,
       rules: Modus.Simulation.RulesEngine.serialize(),
       rules_presets: Modus.Simulation.RulesEngine.preset_names(),
       # Agent Designer
       agent_designer_open: false,
       agent_designer_mode: :agent,
       designer_name: "",
       designer_occupation: "explorer",
       designer_mood: "calm",
       # Speculum Dashboard
       data_dashboard: false,
       dash_population: [],
       dash_resources: %{},
       dash_nodes: [],
       dash_edges: [],
       dash_moods: [],
       dash_trades: [],
       dash_predators: 0,
       dash_prey: 0,
       designer_o: 50,
       designer_c: 50,
       designer_e: 50,
       designer_a: 50,
       designer_n: 50,
       designer_animal: "deer",
       designer_placing: false,
       text_mode: false,
       zen_mode: false,
       # LLM Metrics
       llm_metrics_open: false,
       llm_metrics: %{
         calls_this_tick: 0,
         total_calls: 0,
         cache_hit_rate: 0.0,
         avg_latency_ms: 0,
         active_model: "none",
         sparkline: []
       },
       # Performance Monitor
       perf_monitor_open: false,
       perf_metrics: %{
         agent_count: 0,
         tick: 0,
         tick_state: :paused,
         memory_total_mb: 0.0,
         memory_processes_mb: 0.0,
         memory_ets_mb: 0.0,
         cpu_percent: 0.0,
         health: :healthy
       },
       # Eventus — Event Notification System
       event_timeline: [],
       event_timeline_open: false,
       breaking_event: nil,
       breaking_dismiss_at: nil,
       # Imperium — Divine Intervention
       divine_panel_open: false,
       divine_tab: :events,
       divine_history: [],
       divine_status: nil
     )}
  end

  # ── Landing Page Events ───────────────────────────────────

  @impl true
  def handle_event("landing_start", _params, socket) do
    saved_worlds = socket.assigns.dashboard_worlds
    phase = if saved_worlds != [], do: :dashboard, else: :onboarding
    {:noreply, assign(socket, phase: phase)}
  end

  # ── Text Mode & Zen Mode ─────────────────────────────────

  def handle_event("toggle_text_mode", _params, socket) do
    {:noreply, assign(socket, text_mode: !socket.assigns.text_mode)}
  end

  def handle_event("toggle_zen_mode", _params, socket) do
    {:noreply, assign(socket, zen_mode: !socket.assigns.zen_mode)}
  end

  def handle_event("keypress", %{"key" => key}, socket) when key in ["d", "D"] do
    show = !socket.assigns.data_dashboard
    dash_assigns = if show, do: refresh_dashboard_data(), else: %{}
    {:noreply, socket |> assign(Map.merge(%{data_dashboard: show}, dash_assigns))}
  end

  def handle_event("close_dashboard", _params, socket) do
    {:noreply, assign(socket, data_dashboard: false)}
  end

  def handle_event("keypress", %{"key" => "p"}, socket) do
    send(self(), :toggle_perf_monitor)
    {:noreply, socket}
  end

  def handle_event("keypress", %{"key" => "P"}, socket) do
    send(self(), :toggle_perf_monitor)
    {:noreply, socket}
  end

  def handle_event("keypress", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_perf_monitor", _params, socket) do
    open = !socket.assigns.perf_monitor_open

    metrics =
      if open do
        try do
          Modus.Performance.Monitor.metrics()
        catch
          _, _ -> socket.assigns.perf_metrics
        end
      else
        socket.assigns.perf_metrics
      end

    {:noreply, assign(socket, perf_monitor_open: open, perf_metrics: metrics)}
  end

  def handle_event("toggle_llm_metrics", _params, socket) do
    open = !socket.assigns.llm_metrics_open

    metrics =
      if open do
        try do
          Modus.Intelligence.LlmMetrics.get_metrics()
        catch
          _, _ -> socket.assigns.llm_metrics
        end
      else
        socket.assigns.llm_metrics
      end

    {:noreply, assign(socket, llm_metrics_open: open, llm_metrics: metrics)}
  end

  def handle_event("random_world", _params, socket) do
    templates = socket.assigns.templates
    t = Enum.random(templates)
    pop = Enum.random(5..30)
    danger = Enum.random(["low", "normal", "high"])
    socket = assign(socket, template: t.id, population: pop, danger: danger, phase: :onboarding)
    # Reuse create_world logic
    {:noreply, socket}
  end

  # ── Dashboard Events ─────────────────────────────────────

  def handle_event("dashboard_new_universe", _params, socket) do
    {:noreply, assign(socket, phase: :onboarding)}
  end

  def handle_event("dashboard_sort", %{"sort" => sort}, socket) do
    sorted = sort_worlds(socket.assigns.dashboard_worlds, sort)
    {:noreply, assign(socket, dashboard_sort: sort, dashboard_worlds: sorted)}
  end

  def handle_event("dashboard_load", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)

    case Modus.Persistence.WorldPersistence.load(id) do
      {:ok, info} ->
        Modus.Simulation.Ticker.run()

        {:noreply,
         socket
         |> assign(phase: :simulation, status: :running)
         |> push_event("world_loaded", %{agents: info.agents, tick: info.tick})}

      {:error, reason} ->
        {:noreply, assign(socket, save_load_status: "❌ #{reason}")}
    end
  end

  def handle_event("dashboard_delete_confirm", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    {:noreply, assign(socket, dashboard_delete_confirm: id)}
  end

  def handle_event("dashboard_delete_cancel", _params, socket) do
    {:noreply, assign(socket, dashboard_delete_confirm: nil)}
  end

  def handle_event("dashboard_delete", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    Modus.Persistence.WorldPersistence.delete(id)
    worlds = Modus.Persistence.WorldPersistence.list()
    sorted = sort_worlds(worlds, socket.assigns.dashboard_sort)
    phase = if sorted == [], do: :onboarding, else: :dashboard

    {:noreply,
     assign(socket, dashboard_worlds: sorted, dashboard_delete_confirm: nil, phase: phase)}
  end

  def handle_event("dashboard_back", _params, socket) do
    worlds =
      try do
        Modus.Persistence.WorldPersistence.list()
      catch
        _, _ -> []
      end

    sorted = sort_worlds(worlds, socket.assigns.dashboard_sort)
    phase = if sorted == [], do: :onboarding, else: :dashboard
    {:noreply, assign(socket, phase: phase, dashboard_worlds: sorted)}
  end

  # ── Onboarding Events ──────────────────────────────────────

  @impl true
  def handle_event("select_template", %{"id" => id}, socket) do
    {:noreply, assign(socket, template: id)}
  end

  def handle_event("set_population", %{"value" => val}, socket) do
    {pop, _} = Integer.parse(val)
    {:noreply, assign(socket, population: max(2, min(pop, 50)))}
  end

  def handle_event("set_danger", %{"value" => val}, socket) do
    {:noreply, assign(socket, danger: val)}
  end

  def handle_event("set_seed", %{"value" => val}, socket) do
    {:noreply, assign(socket, world_seed: val)}
  end

  def handle_event("set_language", %{"value" => val}, socket) when val in ~w(en tr de fr es ja) do
    {:noreply, assign(socket, world_language: val)}
  end

  def handle_event("set_grid_size", %{"value" => val}, socket) do
    {size, _} = Integer.parse(val)
    {:noreply, assign(socket, grid_size: max(20, min(size, 200)))}
  end

  def handle_event("launch_world", _params, socket) do
    # Start World and agents server-side directly
    template = socket.assigns.template
    pop = socket.assigns.population
    danger = socket.assigns.danger
    seed_str = socket.assigns.world_seed
    grid_size = socket.assigns.grid_size
    language = socket.assigns.world_language

    # Set world language in rules engine
    Modus.Simulation.RulesEngine.update(%{language: language})

    require Logger
    alias Modus.Simulation.{World, Ticker, AgentSupervisor}

    Logger.info(
      "MODUS launch_world: template=#{template} pop=#{pop} danger=#{danger} grid=#{grid_size}"
    )

    # Clean up if already running
    try do
      AgentSupervisor.terminate_all()
    catch
      kind, reason -> Logger.warning("terminate_all failed: #{inspect({kind, reason})}")
    end

    if Process.whereis(World) do
      try do
        GenServer.stop(World)
      catch
        :exit, _ -> :ok
      end
    end

    opts = [
      template: String.to_atom(template),
      danger_level: String.to_atom(danger),
      grid_size: {grid_size, grid_size}
    ]

    opts =
      if seed_str != "" do
        case Integer.parse(seed_str) do
          {seed_int, _} -> Keyword.put(opts, :seed, seed_int)
          :error -> opts
        end
      else
        opts
      end

    world = World.new("Genesis", opts)

    case World.start_link(world) do
      {:ok, pid} ->
        Logger.info("MODUS World started: #{inspect(pid)}")
        agents = World.spawn_initial_agents(max(2, min(pop, 50)))
        Logger.info("MODUS spawned #{length(agents)} agents")

      {:error, reason} ->
        Logger.error("MODUS World.start_link failed: #{inspect(reason)}")
    end

    Ticker.run()

    {:noreply,
     socket
     |> assign(phase: :simulation, status: :running)
     |> push_event("create_world", %{
       template: template,
       population: pop,
       danger: danger
     })}
  end

  def handle_event("skip_onboarding", _params, socket) do
    require Logger
    alias Modus.Simulation.{World, Ticker, AgentSupervisor}
    Logger.info("MODUS skip_onboarding")

    try do
      AgentSupervisor.terminate_all()
    catch
      _, _ -> :ok
    end

    if Process.whereis(World) do
      try do
        GenServer.stop(World)
      catch
        :exit, _ -> :ok
      end
    end

    world = World.new("Genesis")

    case World.start_link(world) do
      {:ok, pid} ->
        Logger.info("MODUS World started: #{inspect(pid)}")
        agents = World.spawn_initial_agents(10)
        Logger.info("MODUS spawned #{length(agents)} agents")

      {:error, reason} ->
        Logger.error("MODUS World failed: #{inspect(reason)}")
    end

    Ticker.run()

    {:noreply, assign(socket, phase: :simulation, status: :running)}
  end

  # ── Simulation Events ──────────────────────────────────────

  def handle_event("world_state", params, socket) do
    {:noreply,
     assign(socket,
       tick: params["tick"] || 0,
       agent_count: params["agent_count"] || 0,
       status: String.to_existing_atom(params["status"] || "paused"),
       time_of_day: params["time_of_day"] || socket.assigns.time_of_day
     )}
  end

  def handle_event("select_agent", %{"agent" => agent_data}, socket) do
    require Logger
    Logger.info("MODUS select_agent received: #{inspect(agent_data["name"])}")

    {:noreply,
     assign(socket, selected_agent: agent_data, chat_messages: [], mobile_panel: :agent)}
  end

  def handle_event("deselect_agent", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_agent: nil, chat_open: false, chat_messages: [], mobile_panel: nil)
     |> push_event("deselect_agent", %{})}
  end

  def handle_event("toggle_add_goal", _params, socket) do
    {:noreply, assign(socket, show_add_goal: !socket.assigns.show_add_goal)}
  end

  def handle_event("add_goal", %{"type" => type}, socket) do
    agent_id = socket.assigns.selected_agent["id"]

    if agent_id do
      Modus.Mind.Goals.add_goal(agent_id, String.to_existing_atom(type))
      {:noreply, assign(socket, show_add_goal: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_goal", %{"goal-id" => goal_id}, socket) do
    agent_id = socket.assigns.selected_agent["id"]

    if agent_id do
      Modus.Mind.Goals.remove_goal(agent_id, goal_id)
    end

    {:noreply, socket}
  end

  def handle_event("open_chat", _params, socket), do: {:noreply, assign(socket, chat_open: true)}

  def handle_event("close_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: false, chat_filter: "all")}

  def handle_event("chat_filter", %{"topic" => topic}, socket),
    do: {:noreply, assign(socket, chat_filter: topic)}

  def handle_event("send_chat", %{"message" => msg}, socket) when msg != "" do
    require Logger
    agent_id = socket.assigns.selected_agent["id"]

    # Multi-turn context: keep last 5 messages
    context = Enum.take(socket.assigns.chat_context ++ [msg], -5)

    # Handle confirmation responses
    if socket.assigns.pending_confirm && String.downcase(msg) in ["evet", "yes", "onay", "confirm", "ok"] do
      result = Modus.Nexus.ActionEngine.confirm()
      messages = socket.assigns.chat_messages ++ [%{role: "user", text: msg}]
      response_msg = case result do
        {:ok, text} -> %{role: "system", text: "✅ " <> text, topic: "action"}
        {:error, text} -> %{role: "system", text: "❌ " <> text, topic: "action"}
      end
      messages = messages ++ [response_msg]
      {:noreply, assign(socket, chat_messages: messages, chat_loading: false, chat_context: context, pending_confirm: nil)}
    else
      if socket.assigns.pending_confirm && String.downcase(msg) in ["hayır", "no", "iptal", "cancel"] do
        Modus.Nexus.ActionEngine.cancel()
        messages = socket.assigns.chat_messages ++ [
          %{role: "user", text: msg},
          %{role: "system", text: "↩️ Komut iptal edildi.", topic: "action"}
        ]
        {:noreply, assign(socket, chat_messages: messages, chat_loading: false, chat_context: context, pending_confirm: nil)}
      else
        classification = Modus.Nexus.Router.classify(msg)
        Logger.info("MODUS send_chat: agent_id=#{inspect(agent_id)} msg=#{inspect(msg)} intent=#{classification.intent}/#{classification.sub_intent}")
        messages = socket.assigns.chat_messages ++ [%{role: "user", text: msg}]

        case classification.intent do
          :insight ->
            response = Modus.Nexus.Router.dispatch(classification)
            messages = messages ++ [%{role: "system", text: response, topic: "insight"}]
            {:noreply, assign(socket, chat_messages: messages, chat_loading: false, chat_context: context)}

          :action ->
            response = Modus.Nexus.Router.dispatch(classification)
            {topic, pending} = case response do
              {:confirm, _} -> {"action", classification}
              _ -> {"action", nil}
            end
            response_text = case response do
              {:confirm, text} -> text
              {:ok, text} -> "✅ " <> text
              {:error, text} -> "❌ " <> text
              text when is_binary(text) -> text
            end
            messages = messages ++ [%{role: "system", text: response_text, topic: topic}]
            {:noreply, assign(socket, chat_messages: messages, chat_loading: false, chat_context: context, pending_confirm: pending)}

          _ ->
            {:noreply,
             socket
             |> assign(chat_messages: messages, chat_loading: true, chat_context: context)
             |> push_event("chat_to_agent", %{
               agent_id: agent_id,
               message: msg
             })}
        end
      end
    end
  end

  def handle_event("send_chat", _params, socket), do: {:noreply, socket}

  def handle_event("chat_response", %{"reply" => reply} = params, socket) do
    agent_name =
      if socket.assigns.selected_agent, do: socket.assigns.selected_agent["name"], else: "Agent"

    topic = params["topic"] || "general"

    messages =
      socket.assigns.chat_messages ++
        [%{role: "agent", text: reply, name: agent_name, topic: topic}]

    {:noreply, assign(socket, chat_messages: messages, chat_loading: false)}
  end

  def handle_event("agent_detail_update", %{"detail" => detail}, socket) do
    # Don't update selected_agent while chat modal is open — it causes form re-render and input loss
    if socket.assigns.chat_open do
      {:noreply, socket}
    else
      {:noreply, assign(socket, selected_agent: detail)}
    end
  end

  def handle_event("tick_update", params, socket) do
    # Refresh economy/lifecycle stats every tick update
    eco =
      try do
        Modus.Simulation.Economy.stats()
      catch
        _, _ -> %{trades: 0}
      end

    life =
      try do
        Modus.Simulation.Lifecycle.stats()
      catch
        _, _ -> %{births: 0, deaths: 0}
      end

    season_data = params["season"]

    season_assigns =
      if season_data do
        [
          season_name: season_data["season_name"] || "Spring",
          season_emoji: season_data["emoji"] || "🌸",
          season_year: season_data["year"] || 1,
          day_phase: params["day_phase"] || "day"
        ]
      else
        []
      end

    weather_data = params["weather"]

    weather_assigns =
      if weather_data do
        [
          weather_name: weather_data["name"] || "Clear",
          weather_emoji: weather_data["emoji"] || "☀️"
        ]
      else
        []
      end

    tick = params["tick"] || socket.assigns.tick

    # Auto-refresh observatory every 50 ticks when open
    obs_assigns =
      if socket.assigns.stats_open and is_integer(tick) and rem(tick, 50) == 0 do
        alias Modus.Simulation.Observatory
        history = Observatory.population_history()
        world = Observatory.world_stats()

        [
          population_history: history,
          obs_world: world,
          obs_buildings: Observatory.building_breakdown(),
          obs_leaderboards: Observatory.leaderboards(),
          obs_happiness: Observatory.happiness_timeline(history),
          obs_trades: Observatory.trade_timeline(history)
        ]
      else
        []
      end

    # Refresh perf monitor if open
    perf_assigns =
      if socket.assigns.perf_monitor_open and is_integer(tick) and rem(tick, 10) == 0 do
        metrics =
          try do
            Modus.Performance.Monitor.metrics()
          catch
            _, _ -> socket.assigns.perf_metrics
          end

        [perf_metrics: metrics]
      else
        []
      end

    # Refresh LLM metrics if panel is open
    llm_assigns =
      if socket.assigns.llm_metrics_open do
        metrics =
          try do
            Modus.Intelligence.LlmMetrics.get_metrics()
          catch
            _, _ -> socket.assigns.llm_metrics
          end

        [llm_metrics: metrics]
      else
        []
      end

    {:noreply,
     assign(
       socket,
       [
         {:tick, tick},
         {:agent_count, params["agent_count"] || socket.assigns.agent_count},
         {:time_of_day, params["time_of_day"] || socket.assigns.time_of_day},
         {:trades_count, eco.trades},
         {:births_count, life.births},
         {:deaths_count, life.deaths}
         | season_assigns ++ weather_assigns ++ obs_assigns ++ llm_assigns ++ perf_assigns
       ]
     )}
  end

  def handle_event("status_change", params, socket) do
    status = String.to_existing_atom(params["status"] || "paused")
    {:noreply, assign(socket, status: status)}
  end

  # ── Settings ─────────────────────────────────────────────────

  def handle_event("open_settings", _params, socket) do
    config = Modus.Intelligence.LlmProvider.get_config()

    {:noreply,
     assign(socket,
       settings_open: true,
       settings_provider: to_string(config.provider),
       settings_model: config.model || "",
       settings_base_url: config.base_url || "",
       settings_api_key: config.api_key || "",
       settings_test_result: nil
     )}
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, settings_open: false)}
  end

  def handle_event("settings_change", %{"_target" => _} = params, socket) do
    require Logger
    Logger.info("SETTINGS_CHANGE params=#{inspect(Map.drop(params, ["_target"]))}")
    provider = params["provider"] || socket.assigns.settings_provider
    # Only reset model/url when provider actually changes
    provider_changed = provider != socket.assigns.settings_provider

    {base_url, model} =
      if provider_changed do
        case provider do
          "antigravity" -> {"http://host.docker.internal:8045", "gemini-3-flash"}
          _ -> {"http://modus-llm:11434", "llama3.2:3b-instruct-q4_K_M"}
        end
      else
        {socket.assigns.settings_base_url, socket.assigns.settings_model}
      end

    api_key =
      if provider_changed and provider == "antigravity" do
        System.get_env("ANTIGRAVITY_API_KEY") || socket.assigns.settings_api_key
      else
        params["api_key"] || socket.assigns.settings_api_key
      end

    selected_model =
      if provider_changed do
        model
      else
        m = params["model"] || model
        if m == "__custom__", do: "", else: m
      end

    {:noreply,
     assign(socket,
       settings_provider: provider,
       settings_model: selected_model,
       settings_base_url: params["base_url"] || base_url,
       settings_api_key: api_key,
       settings_test_result: nil
     )}
  end

  def handle_event("save_settings", _params, socket) do
    require Logger

    Logger.info(
      "SAVE_SETTINGS provider=#{socket.assigns.settings_provider} model=#{socket.assigns.settings_model} url=#{socket.assigns.settings_base_url}"
    )

    provider =
      case socket.assigns.settings_provider do
        "antigravity" -> :antigravity
        _ -> :ollama
      end

    api_key =
      if provider == :antigravity and
           (socket.assigns.settings_api_key == nil or socket.assigns.settings_api_key == "") do
        System.get_env("ANTIGRAVITY_API_KEY") || ""
      else
        socket.assigns.settings_api_key
      end

    Modus.Intelligence.LlmProvider.set_config(%{
      provider: provider,
      model: socket.assigns.settings_model,
      base_url: socket.assigns.settings_base_url,
      api_key: api_key
    })

    Process.send_after(self(), :clear_settings_saved, 1500)
    {:noreply, assign(socket, settings_saved: true)}
  end

  def handle_event("test_llm", _params, socket) do
    # Save config first temporarily
    provider =
      case socket.assigns.settings_provider do
        "antigravity" -> :antigravity
        _ -> :ollama
      end

    Modus.Intelligence.LlmProvider.set_config(%{
      provider: provider,
      model: socket.assigns.settings_model,
      base_url: socket.assigns.settings_base_url,
      api_key: socket.assigns.settings_api_key
    })

    # Run test async to show loading state
    pid = self()

    Task.start(fn ->
      result =
        case Modus.Intelligence.LlmProvider.test_connection() do
          :ok -> "ok"
          {:error, reason} -> "error: #{inspect(reason)}"
        end

      send(pid, {:test_llm_result, result})
    end)

    {:noreply, assign(socket, settings_testing: true, settings_test_result: nil)}
  end

  # ── Rules Engine ──────────────────────────────────────────────

  def handle_event("open_rules", _params, socket) do
    rules = Modus.Simulation.RulesEngine.serialize()
    {:noreply, assign(socket, rules_open: true, rules: rules)}
  end

  def handle_event("close_rules", _params, socket) do
    {:noreply, assign(socket, rules_open: false)}
  end

  def handle_event("rules_change", params, socket) do
    changes = %{}

    changes =
      if params["time_speed"],
        do: Map.put(changes, :time_speed, parse_float(params["time_speed"], 1.0)),
        else: changes

    changes =
      if params["social_tendency"],
        do: Map.put(changes, :social_tendency, parse_float(params["social_tendency"], 0.5)),
        else: changes

    changes =
      if params["birth_rate"],
        do: Map.put(changes, :birth_rate, parse_float(params["birth_rate"], 1.0)),
        else: changes

    changes =
      if params["building_speed"],
        do: Map.put(changes, :building_speed, parse_float(params["building_speed"], 1.0)),
        else: changes

    changes =
      if params["mutation_rate"],
        do: Map.put(changes, :mutation_rate, parse_float(params["mutation_rate"], 0.3)),
        else: changes

    changes =
      if params["resource_abundance"],
        do:
          Map.put(
            changes,
            :resource_abundance,
            String.to_existing_atom(params["resource_abundance"])
          ),
        else: changes

    changes =
      if params["danger_level"],
        do: Map.put(changes, :danger_level, String.to_existing_atom(params["danger_level"])),
        else: changes

    changes =
      if params["language"] && params["language"] in ~w(en tr de fr es ja),
        do: Map.put(changes, :language, params["language"]),
        else: changes

    if changes != %{} do
      Modus.Simulation.RulesEngine.update(changes)
    end

    rules = Modus.Simulation.RulesEngine.serialize()
    {:noreply, assign(socket, rules: rules)}
  end

  def handle_event("apply_rules_preset", %{"preset" => preset_name}, socket) do
    case Modus.Simulation.RulesEngine.apply_preset(preset_name) do
      {:ok, _} ->
        rules = Modus.Simulation.RulesEngine.serialize()
        {:noreply, assign(socket, rules: rules)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # ── Save / Load ───────────────────────────────────────────────

  def handle_event("open_save_load", _params, socket) do
    slots =
      try do
        Modus.Persistence.SaveManager.list_slots()
      catch
        _, _ -> []
      end

    autosave =
      try do
        Modus.Persistence.SaveManager.autosave_status()
      catch
        _, _ -> %{enabled: false, last_tick: 0, last_at: nil, interval: 500}
      end

    {:noreply,
     assign(socket,
       save_load_open: true,
       save_slots: slots,
       save_load_status: nil,
       save_name: "",
       selected_slot: 1,
       autosave_status: autosave
     )}
  end

  def handle_event("close_save_load", _params, socket) do
    {:noreply, assign(socket, save_load_open: false)}
  end

  def handle_event("set_save_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, save_name: name)}
  end

  def handle_event("select_slot", %{"slot" => slot_str}, socket) do
    {slot, _} = Integer.parse(slot_str)
    {:noreply, assign(socket, selected_slot: slot)}
  end

  def handle_event("do_save", _params, socket) do
    slot = socket.assigns[:selected_slot] || 1
    name = if socket.assigns.save_name == "", do: nil, else: socket.assigns.save_name

    case Modus.Persistence.SaveManager.save_slot(slot, name) do
      {:ok, info} ->
        slots = Modus.Persistence.SaveManager.list_slots()

        {:noreply,
         assign(socket,
           save_slots: slots,
           save_load_status: "✅ Saved: #{info.name}",
           save_name: ""
         )}

      {:error, reason} ->
        {:noreply, assign(socket, save_load_status: "❌ #{reason}")}
    end
  end

  def handle_event("do_load", %{"slot" => slot_str}, socket) do
    {slot, _} = Integer.parse(slot_str)

    case Modus.Persistence.SaveManager.load_slot(slot) do
      {:ok, info} ->
        try do
          Modus.Simulation.Ticker.run()
        catch
          _, _ -> :ok
        end

        {:noreply,
         socket
         |> assign(save_load_open: false, save_load_status: nil, status: :running)
         |> push_event("world_loaded", %{agents: info.agents, tick: 0})}

      {:error, reason} ->
        {:noreply, assign(socket, save_load_status: "❌ #{inspect(reason)}")}
    end
  end

  def handle_event("do_delete_save", %{"slot" => slot_str}, socket) do
    {slot, _} = Integer.parse(slot_str)
    Modus.Persistence.SaveManager.delete_slot(slot)
    slots = Modus.Persistence.SaveManager.list_slots()
    {:noreply, assign(socket, save_slots: slots, save_load_status: "🗑️ Deleted")}
  end

  def handle_event("do_export_save", _params, socket) do
    case Modus.Persistence.SaveManager.export_json() do
      {:ok, json} ->
        {:noreply,
         assign(socket, save_load_status: "✅ Exported")
         |> push_event("download", %{
           data: json,
           filename: "modus_world.json",
           content_type: "application/json"
         })}

      {:error, reason} ->
        {:noreply, assign(socket, save_load_status: "❌ #{reason}")}
    end
  end

  def handle_event("do_import_save", %{"json" => json}, socket) do
    case Modus.Persistence.SaveManager.import_json(json) do
      {:ok, info} ->
        slots = Modus.Persistence.SaveManager.list_slots()

        {:noreply,
         assign(socket, save_slots: slots, save_load_status: "✅ Imported: #{info.name}")}

      {:error, reason} ->
        {:noreply, assign(socket, save_load_status: "❌ #{reason}")}
    end
  end

  # ── Controls ────────────────────────────────────────────────

  def handle_event("start", _params, socket) do
    {:noreply, push_event(socket, "start_simulation", %{})}
  end

  def handle_event("pause", _params, socket) do
    {:noreply, push_event(socket, "pause_simulation", %{})}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, push_event(socket, "reset_simulation", %{})}
  end

  def handle_event("set_speed", %{"speed" => speed}, socket) do
    {s, _} = Integer.parse(speed)

    {:noreply,
     socket
     |> assign(speed: s)
     |> push_event("set_speed", %{speed: s})}
  end

  # ── Event Injection ────────────────────────────────────────

  def handle_event("inject_event", %{"type" => event_type}, socket) do
    emoji =
      case event_type do
        "natural_disaster" -> "🌋"
        "migrant" -> "🚶"
        "resource_bonus" -> "🌾"
        _ -> "⚡"
      end

    label =
      case event_type do
        "natural_disaster" -> "Natural Disaster"
        "migrant" -> "Migrant Arrived"
        "resource_bonus" -> "Resource Bonus"
        _ -> event_type
      end

    feed = [
      %{emoji: emoji, label: label, tick: socket.assigns.tick}
      | Enum.take(socket.assigns.event_feed, 9)
    ]

    {:noreply,
     socket
     |> assign(event_feed: feed)
     |> push_event("inject_event", %{event_type: event_type})}
  end

  @valid_world_events ~w(storm earthquake meteor_shower plague golden_age flood fire drought famine festival discovery migration_wave conflict)

  def handle_event("trigger_world_event", %{"type" => event_type}, socket)
      when event_type in @valid_world_events do
    emoji =
      case event_type do
        "storm" -> "🌩️"
        "earthquake" -> "🌍"
        "meteor_shower" -> "☄️"
        "plague" -> "🦠"
        "golden_age" -> "✨"
        "flood" -> "🌊"
        "fire" -> "🔥"
        "drought" -> "🏜️"
        "famine" -> "💀🌾"
        "festival" -> "🎉"
        "discovery" -> "🗺️"
        "migration_wave" -> "🚶"
        "conflict" -> "⚔️"
        _ -> "🌍"
      end

    feed = [
      %{emoji: emoji, label: "World Event: #{event_type}", tick: socket.assigns.tick}
      | Enum.take(socket.assigns.event_feed, 9)
    ]

    {:noreply,
     socket
     |> assign(event_feed: feed)
     |> push_event("trigger_world_event", %{event_type: event_type})}
  end

  # ── Mobile Panel Toggle ────────────────────────────────────

  def handle_event("toggle_mind_view", _params, socket) do
    new_val = !socket.assigns.mind_view_active

    {:noreply,
     socket
     |> assign(mind_view_active: new_val)
     |> push_event("toggle_mind_view", %{active: new_val})}
  end

  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    current = socket.assigns.mobile_panel

    new_panel =
      if current == String.to_existing_atom(panel), do: nil, else: String.to_existing_atom(panel)

    {:noreply, assign(socket, mobile_panel: new_panel)}
  end

  # ── Creator: Agent Designer ──────────────────────────────────

  def handle_event("toggle_agent_designer", _params, socket) do
    {:noreply,
     assign(socket,
       agent_designer_open: !socket.assigns.agent_designer_open,
       designer_placing: false
     )}
  end

  def handle_event("set_designer_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, agent_designer_mode: String.to_existing_atom(mode))}
  end

  def handle_event("designer_change", params, socket) do
    socket =
      socket
      |> maybe_assign(params, "name", :designer_name)
      |> maybe_assign(params, "occupation", :designer_occupation)
      |> maybe_assign(params, "mood", :designer_mood)
      |> maybe_assign(params, "animal", :designer_animal)
      |> maybe_assign_int(params, "o", :designer_o)
      |> maybe_assign_int(params, "c", :designer_c)
      |> maybe_assign_int(params, "e", :designer_e)
      |> maybe_assign_int(params, "a", :designer_a)
      |> maybe_assign_int(params, "n", :designer_n)

    {:noreply, socket}
  end

  def handle_event("designer_place", _params, socket) do
    # Toggle placing mode — next map click spawns agent
    {:noreply,
     socket
     |> assign(designer_placing: true)
     |> push_event("designer_place_mode", %{
       mode: to_string(socket.assigns.agent_designer_mode),
       data: %{
         name: socket.assigns.designer_name,
         occupation: socket.assigns.designer_occupation,
         mood: socket.assigns.designer_mood,
         personality: %{
           o: socket.assigns.designer_o,
           c: socket.assigns.designer_c,
           e: socket.assigns.designer_e,
           a: socket.assigns.designer_a,
           n: socket.assigns.designer_n
         },
         animal: socket.assigns.designer_animal
       }
     })}
  end

  def handle_event("agent_placed", _params, socket) do
    {:noreply, assign(socket, designer_placing: false)}
  end

  # ── Creator: Build Mode ──────────────────────────────────────

  def handle_event("toggle_build_mode", _params, socket) do
    new_val = !socket.assigns.build_mode

    {:noreply,
     socket
     |> assign(build_mode: new_val)
     |> push_event("toggle_build_mode", %{active: new_val})}
  end

  def handle_event("set_build_brush", %{"brush" => brush, "type" => type}, socket) do
    {:noreply,
     socket
     |> assign(build_brush: brush, build_type: type)
     |> push_event("set_build_brush", %{brush: brush, type: type})}
  end

  # ── Deus: God Mode, Cinematic Camera, Screenshot ─────────────

  def handle_event("toggle_god_mode", _params, socket) do
    new_val = !socket.assigns.god_mode

    {:noreply,
     socket
     |> assign(god_mode: new_val, mind_view_active: new_val)
     |> push_event("toggle_god_mode", %{active: new_val})
     |> push_event("toggle_mind_view", %{active: new_val})}
  end

  def handle_event("toggle_cinematic", _params, socket) do
    new_val = !socket.assigns.cinematic_mode

    {:noreply,
     socket
     |> assign(cinematic_mode: new_val)
     |> push_event("toggle_cinematic", %{active: new_val})}
  end

  def handle_event("take_screenshot", _params, socket) do
    {:noreply, push_event(socket, "take_screenshot", %{})}
  end

  # ── Potentia: Timeline / Chronicle / Stats ──────────────────

  def handle_event("toggle_timeline", _params, socket) do
    open = !socket.assigns.timeline_open

    entries =
      if open do
        try do
          Modus.Simulation.StoryEngine.get_timeline(limit: 50)
        catch
          _, _ -> []
        end
      else
        []
      end

    {:noreply, assign(socket, timeline_open: open, timeline_entries: entries)}
  end

  def handle_event("open_chronicle", _params, socket) do
    md =
      try do
        Modus.Simulation.StoryEngine.export_markdown()
      catch
        _, _ -> "No chronicle data yet."
      end

    {:noreply, assign(socket, chronicle_open: true, chronicle_md: md)}
  end

  def handle_event("open_history", _params, socket) do
    eras =
      try do
        Modus.Simulation.WorldHistory.get_eras()
      catch
        _, _ -> []
      end

    figures =
      try do
        Modus.Simulation.WorldHistory.key_figures()
      catch
        _, _ -> []
      end

    {:noreply,
     assign(socket,
       history_open: true,
       history_eras: eras,
       history_figures: figures,
       history_selected_era: nil,
       history_era_events: []
     )}
  end

  def handle_event("close_history", _params, socket) do
    {:noreply, assign(socket, history_open: false)}
  end

  def handle_event("select_history_era", %{"era-id" => era_id}, socket) do
    events =
      try do
        Modus.Simulation.WorldHistory.era_events(era_id)
      catch
        _, _ -> []
      end

    {:noreply, assign(socket, history_selected_era: era_id, history_era_events: events)}
  end

  def handle_event("export_world_chronicle", _params, socket) do
    md =
      try do
        Modus.Simulation.WorldHistory.export_chronicle("This World")
      catch
        _, _ -> "No history yet."
      end

    {:noreply, assign(socket, chronicle_open: true, chronicle_md: md)}
  end

  def handle_event("close_chronicle", _params, socket) do
    {:noreply, assign(socket, chronicle_open: false)}
  end

  def handle_event("download_chronicle", _params, socket) do
    md = socket.assigns.chronicle_md

    {:noreply,
     push_event(socket, "download_file", %{
       filename: "modus-chronicle-#{System.system_time(:second)}.md",
       content: md,
       mime: "text/markdown"
     })}
  end

  # ── Export & Share ──────────────────────────────────────────

  def handle_event("open_export", _params, socket) do
    {:noreply,
     assign(socket,
       export_open: true,
       export_tab: :export,
       export_status: nil,
       import_status: nil
     )}
  end

  def handle_event("close_export", _params, socket) do
    {:noreply, assign(socket, export_open: false)}
  end

  def handle_event("export_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, export_tab: String.to_existing_atom(tab))}
  end

  def handle_event("do_export_json", _params, socket) do
    case Modus.Persistence.WorldExport.export_json() do
      {:ok, json} ->
        {:noreply,
         socket
         |> assign(export_json: json, export_status: "✅ Export ready!")
         |> push_event("download_file", %{
           filename: "modus-world-#{System.system_time(:second)}.json",
           content: json,
           mime: "application/json"
         })}

      {:error, reason} ->
        {:noreply, assign(socket, export_status: "❌ #{reason}")}
    end
  end

  def handle_event("do_export_share", _params, socket) do
    case Modus.Persistence.WorldExport.export_base64() do
      {:ok, b64} ->
        {:noreply, assign(socket, export_base64: b64, export_status: "✅ Share link ready!")}

      {:error, reason} ->
        {:noreply, assign(socket, export_status: "❌ #{reason}")}
    end
  end

  def handle_event("do_import_json", %{"json" => json}, socket) do
    case Modus.Persistence.WorldExport.import_json(json) do
      {:ok, info} ->
        state = build_channel_state()

        {:noreply,
         socket
         |> assign(
           phase: :simulation,
           status: :running,
           import_status: "✅ Imported #{info.name} (#{info.agents} agents)"
         )
         |> push_event("world_loaded", state)}

      {:error, reason} ->
        {:noreply, assign(socket, import_status: "❌ #{reason}")}
    end
  end

  def handle_event("do_import_share", %{"share_code" => code}, socket) do
    case Modus.Persistence.WorldExport.import_base64(code) do
      {:ok, info} ->
        state = build_channel_state()

        {:noreply,
         socket
         |> assign(
           phase: :simulation,
           status: :running,
           import_status: "✅ Imported #{info.name} (#{info.agents} agents)"
         )
         |> push_event("world_loaded", state)}

      {:error, reason} ->
        {:noreply, assign(socket, import_status: "❌ #{reason}")}
    end
  end

  def handle_event("screenshot_with_overlay", _params, socket) do
    world_name =
      try do
        Modus.Simulation.World.get_state().name
      catch
        _, _ -> "MODUS"
      end

    tick =
      try do
        Modus.Simulation.Ticker.current_tick()
      catch
        _, _ -> 0
      end

    {:noreply,
     push_event(socket, "screenshot_with_overlay", %{world_name: world_name, tick: tick})}
  end

  def handle_event("open_stats", _params, socket) do
    alias Modus.Simulation.Observatory
    history = Observatory.population_history()
    world = Observatory.world_stats()
    buildings = Observatory.building_breakdown()
    leaderboards = Observatory.leaderboards()
    {net_nodes, net_edges} = Observatory.relationship_network()
    happiness_tl = Observatory.happiness_timeline(history)
    trade_tl = Observatory.trade_timeline(history)

    {:noreply,
     assign(socket,
       stats_open: true,
       population_history: history,
       obs_world: world,
       obs_buildings: buildings,
       obs_leaderboards: leaderboards,
       obs_net_nodes: net_nodes,
       obs_net_edges: net_edges,
       obs_happiness: happiness_tl,
       obs_trades: trade_tl,
       obs_tab: :overview
     )}
  end

  def handle_event("close_stats", _params, socket) do
    {:noreply, assign(socket, stats_open: false)}
  end

  def handle_event("obs_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, obs_tab: String.to_existing_atom(tab))}
  end

  def handle_event("obs_refresh", _params, socket) do
    # Re-fetch all observatory data
    alias Modus.Simulation.Observatory
    history = Observatory.population_history()
    world = Observatory.world_stats()
    buildings = Observatory.building_breakdown()
    leaderboards = Observatory.leaderboards()
    {net_nodes, net_edges} = Observatory.relationship_network()

    {:noreply,
     assign(socket,
       population_history: history,
       obs_world: world,
       obs_buildings: buildings,
       obs_leaderboards: leaderboards,
       obs_net_nodes: net_nodes,
       obs_net_edges: net_edges,
       obs_happiness: Observatory.happiness_timeline(history),
       obs_trades: Observatory.trade_timeline(history)
     )}
  end

  # ── Eventus: Event Timeline Toggle ──────────────────────

  def handle_event("toggle_event_timeline", _params, socket) do
    open = !socket.assigns.event_timeline_open
    {:noreply, assign(socket, event_timeline_open: open)}
  end

  def handle_event("dismiss_breaking", _params, socket) do
    {:noreply, assign(socket, breaking_event: nil)}
  end

  # ── Imperium: Divine Intervention Panel ─────────────────

  def handle_event("toggle_divine_panel", _params, socket) do
    open = !socket.assigns.divine_panel_open

    history =
      if open do
        try do
          Modus.Simulation.DivineIntervention.history(limit: 30)
        catch
          _, _ -> []
        end
      else
        []
      end

    {:noreply,
     assign(socket, divine_panel_open: open, divine_history: history, divine_status: nil)}
  end

  def handle_event("divine_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, divine_tab: String.to_existing_atom(tab))}
  end

  def handle_event("divine_command", %{"cmd" => cmd} = params, socket) do
    command = String.to_existing_atom(cmd)

    cmd_params =
      params
      |> Map.delete("cmd")
      |> Map.delete("_target")
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    # Add selected agent id if agent command
    cmd_params =
      if socket.assigns.selected_agent && Map.get(cmd_params, :agent_id) == nil do
        Map.put(cmd_params, :agent_id, socket.assigns.selected_agent["id"])
      else
        cmd_params
      end

    result =
      try do
        Modus.Simulation.DivineIntervention.execute(command, cmd_params)
      catch
        _, reason -> {:error, "#{inspect(reason)}"}
      end

    status =
      case result do
        {:ok, data} -> "✅ #{cmd}: #{inspect(data)}"
        {:error, reason} -> "❌ #{reason}"
      end

    history =
      try do
        Modus.Simulation.DivineIntervention.history(limit: 30)
      catch
        _, _ -> []
      end

    {:noreply, assign(socket, divine_history: history, divine_status: status)}
  end

  def handle_event("divine_clear_history", _params, socket) do
    Modus.Simulation.DivineIntervention.clear_history()
    {:noreply, assign(socket, divine_history: [], divine_status: "🗑️ Geçmiş temizlendi")}
  end

  def handle_event(
        "world_event_toast",
        %{"emoji" => emoji, "type" => type, "severity" => severity},
        socket
      ) do
    severity_word =
      case severity do
        1 -> "Minor"
        2 -> "Severe"
        3 -> "Catastrophic"
        _ -> ""
      end

    toast = %{
      id: System.unique_integer([:positive]) |> to_string(),
      emoji: emoji,
      text: "#{severity_word} #{String.replace(type, "_", " ")} strikes the world!",
      tick: socket.assigns.tick
    }

    toasts = Enum.take([toast | socket.assigns.toasts], 5)
    Process.send_after(self(), {:dismiss_toast, toast.id}, 8_000)
    {:noreply, assign(socket, toasts: toasts)}
  end

  def handle_event("dismiss_toast", %{"id" => id}, socket) do
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == id))
    {:noreply, assign(socket, toasts: toasts)}
  end

  def handle_event("season_change_toast", %{"emoji" => emoji, "season_name" => name}, socket) do
    toast = %{
      id: System.unique_integer([:positive]) |> to_string(),
      emoji: emoji,
      text: "#{name} has arrived!",
      tick: socket.assigns.tick
    }

    toasts = Enum.take([toast | socket.assigns.toasts], 5)
    Process.send_after(self(), {:dismiss_toast, toast.id}, 10_000)
    {:noreply, assign(socket, toasts: toasts, season_name: name, season_emoji: emoji)}
  end

  # ── Private Helpers (handle_event) ───────────────────────────

  defp sort_worlds(worlds, "oldest"), do: Enum.sort_by(worlds, & &1.saved_at, :asc)
  defp sort_worlds(worlds, "most_populated"), do: Enum.sort_by(worlds, & &1.agents, :desc)
  defp sort_worlds(worlds, _newest), do: Enum.sort_by(worlds, & &1.saved_at, :desc)

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} ->
        f

      :error ->
        case Integer.parse(val) do
          {i, _} -> i / 1
          :error -> default
        end
    end
  end

  defp parse_float(val, _default) when is_float(val), do: val
  defp parse_float(val, _default) when is_integer(val), do: val / 1
  defp parse_float(_, default), do: default

  defp maybe_assign(socket, params, key, field) do
    case Map.get(params, key) do
      nil -> socket
      val -> assign(socket, [{field, val}])
    end
  end

  defp maybe_assign_int(socket, params, key, field) do
    case Map.get(params, key) do
      nil ->
        socket

      val when is_binary(val) ->
        case Integer.parse(val) do
          {i, _} -> assign(socket, [{field, max(0, min(i, 100))}])
          :error -> socket
        end

      val when is_integer(val) ->
        assign(socket, [{field, max(0, min(val, 100))}])

      _ ->
        socket
    end
  end

  defp build_channel_state do
    agents =
      try do
        Modus.AgentRegistry
        |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
        |> length()
      catch
        _, _ -> 0
      end

    tick =
      try do
        Modus.Simulation.Ticker.current_tick()
      catch
        _, _ -> 0
      end

    %{agents: agents, tick: tick}
  end

  # ── PubSub Events ───────────────────────────────────────────

  @impl true
  def handle_info({:event, event}, socket) do
    emoji =
      case event.type do
        :death -> "💀"
        :birth -> "👶"
        :conversation -> "💬"
        :conflict -> "⚔️"
        :resource_gathered -> "🌾"
        _ -> "⚡"
      end

    name = event.data[:name] || event.data["name"] || resolve_agent_names(event.agents)

    label =
      case event.type do
        :death -> "#{name} died (#{event.data[:cause] || "unknown"})"
        :birth -> "#{name} was born"
        :conversation -> "#{name} had a conversation"
        :conflict -> "Conflict!"
        :resource_gathered -> "#{name} gathered resources"
        _ -> to_string(event.type)
      end

    feed = [
      %{emoji: emoji, label: label, tick: event.tick} | Enum.take(socket.assigns.event_feed, 19)
    ]

    {:noreply, assign(socket, event_feed: feed)}
  end

  def handle_info({:toast, entry}, socket) do
    toast = %{
      id: System.unique_integer([:positive]) |> to_string(),
      emoji: entry.emoji,
      text: entry.narrative,
      tick: entry.tick
    }

    toasts = Enum.take([toast | socket.assigns.toasts], 5)
    # Auto-dismiss after 6 seconds
    Process.send_after(self(), {:dismiss_toast, toast.id}, 6_000)

    # Update timeline if open
    socket =
      if socket.assigns.timeline_open do
        entries =
          try do
            Modus.Simulation.StoryEngine.get_timeline(limit: 50)
          catch
            _, _ -> []
          end

        assign(socket, timeline_entries: entries)
      else
        socket
      end

    {:noreply, assign(socket, toasts: toasts)}
  end

  def handle_info({:dismiss_toast, id}, socket) do
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == id))
    {:noreply, assign(socket, toasts: toasts)}
  end

  def handle_info(:toggle_perf_monitor, socket) do
    open = !socket.assigns.perf_monitor_open

    metrics =
      if open do
        try do
          Modus.Performance.Monitor.metrics()
        catch
          _, _ -> socket.assigns.perf_metrics
        end
      else
        socket.assigns.perf_metrics
      end

    {:noreply, assign(socket, perf_monitor_open: open, perf_metrics: metrics)}
  end

  def handle_info(:clear_settings_saved, socket) do
    {:noreply, assign(socket, settings_saved: false, settings_open: false)}
  end

  def handle_info({:test_llm_result, result}, socket) do
    {:noreply, assign(socket, settings_testing: false, settings_test_result: result)}
  end

  # ── Eventus: World Events PubSub ────────────────────────

  def handle_info({:world_event, event_data}, socket) when is_map(event_data) do
    # Build timeline entry
    severity_word =
      case event_data[:severity] || event_data["severity"] do
        1 -> "Minor"
        2 -> "Severe"
        3 -> "Catastrophic"
        _ -> ""
      end

    event_type = event_data[:type] || event_data["type"] || "unknown"
    emoji = event_data[:emoji] || event_data["emoji"] || "⚡"
    category = event_data[:category] || event_data["category"] || "disaster"
    level = event_data[:level] || event_data["level"] || "toast"
    chain_source = event_data[:chain_source] || event_data["chain_source"]
    artifact = event_data[:artifact] || event_data["artifact"]

    label =
      cond do
        artifact ->
          artifact_name = artifact[:name] || artifact["name"] || "Artifact"
          "#{artifact_name} discovered!"

        chain_source ->
          "#{severity_word} #{String.replace(to_string(event_type), "_", " ")} (caused by #{chain_source})"

        true ->
          "#{severity_word} #{String.replace(to_string(event_type), "_", " ")} strikes!"
      end

    entry = %{
      id: System.unique_integer([:positive]) |> to_string(),
      emoji: emoji,
      text: label,
      type: to_string(event_type),
      category: to_string(category),
      severity: event_data[:severity] || event_data["severity"] || 1,
      tick: socket.assigns.tick,
      chain_source: chain_source,
      artifact: artifact,
      timestamp: System.system_time(:second)
    }

    # Add to timeline (max 50)
    timeline = Enum.take([entry | socket.assigns.event_timeline], 50)

    # Toast
    toast = %{
      id: entry.id,
      emoji: emoji,
      text: label,
      tick: socket.assigns.tick
    }

    toasts = Enum.take([toast | socket.assigns.toasts], 5)
    Process.send_after(self(), {:dismiss_toast, toast.id}, 5_000)

    # Breaking banner for severe events
    socket =
      if to_string(level) == "breaking" do
        Process.send_after(self(), :dismiss_breaking, 10_000)
        assign(socket, breaking_event: entry)
      else
        socket
      end

    # Update event feed too
    feed_entry = %{emoji: emoji, label: label, tick: socket.assigns.tick}
    feed = Enum.take([feed_entry | socket.assigns.event_feed], 20)

    {:noreply, assign(socket, event_timeline: timeline, toasts: toasts, event_feed: feed)}
  end

  def handle_info({:event_ended, _event_data}, socket) do
    {:noreply, socket}
  end

  def handle_info(:dismiss_breaking, socket) do
    {:noreply, assign(socket, breaking_event: nil)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Render ──────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <%= case @phase do %>
      <% :landing -> %>
        <%= render_landing(assigns) %>
      <% :dashboard -> %>
        <%= render_dashboard(assigns) %>
      <% :onboarding -> %>
        <%= render_onboarding(assigns) %>
      <% _ -> %>
        <%= render_simulation(assigns) %>
    <% end %>
    """
  end

  # ── Landing Page ─────────────────────────────────────────

  defp render_landing(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050508] text-slate-200 font-mono flex flex-col items-center justify-center px-4 relative overflow-hidden">
      <%!-- Background blurs --%>
      <div class="absolute inset-0 overflow-hidden pointer-events-none">
        <div class="absolute top-1/4 left-1/4 w-[500px] h-[500px] bg-purple-600/10 rounded-full blur-3xl animate-pulse"></div>
        <div class="absolute bottom-1/4 right-1/4 w-[500px] h-[500px] bg-cyan-600/10 rounded-full blur-3xl animate-pulse" style="animation-delay: 1s"></div>
        <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[300px] h-[300px] bg-purple-500/5 rounded-full blur-3xl"></div>
      </div>

      <div class="relative z-10 text-center max-w-3xl mx-auto">
        <%!-- Logo --%>
        <h1 class="text-7xl md:text-8xl font-bold tracking-tighter mb-4">
          MODUS<span class="text-purple-400">_</span>
        </h1>
        <p class="text-2xl md:text-3xl font-light text-slate-300 mb-2">Create Worlds. Watch Them Live.</p>
        <p class="text-sm text-slate-500 mb-12">v5.0.0 Forma · AI-Powered Universe Simulation</p>

        <%!-- Feature Cards --%>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-12">
          <div class="p-6 rounded-2xl border border-white/10 bg-white/[0.02] backdrop-blur-sm hover:border-purple-500/30 transition-all">
            <div class="text-4xl mb-3">🧠</div>
            <h3 class="text-lg font-semibold text-slate-200 mb-2">Thinking Agents</h3>
            <p class="text-sm text-slate-500">AI-powered minds with emotions, memory, personality, and free will.</p>
          </div>
          <div class="p-6 rounded-2xl border border-white/10 bg-white/[0.02] backdrop-blur-sm hover:border-cyan-500/30 transition-all">
            <div class="text-4xl mb-3">🌍</div>
            <h3 class="text-lg font-semibold text-slate-200 mb-2">Living Ecosystems</h3>
            <p class="text-sm text-slate-500">Dynamic weather, seasons, resources, birth & death cycles.</p>
          </div>
          <div class="p-6 rounded-2xl border border-white/10 bg-white/[0.02] backdrop-blur-sm hover:border-purple-500/30 transition-all">
            <div class="text-4xl mb-3">🔬</div>
            <h3 class="text-lg font-semibold text-slate-200 mb-2">Spinoza Mind Engine</h3>
            <p class="text-sm text-slate-500">Conatus, affects, social networks — philosophy meets silicon.</p>
          </div>
        </div>

        <%!-- CTA --%>
        <button
          phx-click="landing_start"
          class="px-8 py-4 rounded-2xl bg-gradient-to-r from-purple-600 to-cyan-600 text-white font-semibold text-lg hover:from-purple-500 hover:to-cyan-500 transition-all shadow-lg shadow-purple-500/20 hover:shadow-purple-500/40 hover:scale-105 transform"
        >
          Start Creating →
        </button>

        <p class="text-[10px] text-slate-600 mt-8">Built on Elixir/BEAM · Pixi.js · 30+ modules · Spinoza's Ethics</p>
      </div>
    </div>
    """
  end

  # ── Multi-Universe Dashboard ─────────────────────────────

  defp render_dashboard(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050508] text-slate-200 font-mono overflow-y-auto">
      <%!-- Header --%>
      <div class="relative flex flex-col items-center pt-16 pb-8 px-4">
        <div class="absolute inset-0 overflow-hidden pointer-events-none">
          <div class="absolute top-1/4 left-1/3 w-80 h-80 bg-purple-600/8 rounded-full blur-3xl"></div>
          <div class="absolute top-1/3 right-1/4 w-80 h-80 bg-cyan-600/8 rounded-full blur-3xl"></div>
        </div>
        <div class="relative text-center mb-8">
          <h1 class="text-5xl md:text-6xl font-bold tracking-tighter mb-2">
            MODUS<span class="text-purple-400">_</span>
          </h1>
          <p class="text-sm text-slate-500">v5.0.0 Forma · You're not limited to one world — create many.</p>
        </div>

        <%!-- Sort Controls --%>
        <div class="relative flex items-center gap-2 mb-6">
          <span class="text-[10px] uppercase tracking-wider text-slate-600">Sort:</span>
          <%= for {val, label} <- [{"newest", "Newest"}, {"oldest", "Oldest"}, {"most_populated", "Most Pop."}] do %>
            <button
              phx-click="dashboard_sort"
              phx-value-sort={val}
              class={"px-3 py-1 text-[10px] rounded-lg border transition-all #{if @dashboard_sort == val, do: "border-purple-500/50 bg-purple-500/10 text-purple-300", else: "border-white/10 bg-white/3 text-slate-500 hover:border-white/20"}"}
            >
              <%= label %>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Universe Gallery --%>
      <div class="max-w-4xl mx-auto px-4 pb-16">
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <%!-- Create New Universe Card --%>
          <button
            phx-click="dashboard_new_universe"
            class="group flex flex-col items-center justify-center p-8 rounded-xl border-2 border-dashed border-white/10 hover:border-purple-500/40 bg-white/[0.02] hover:bg-purple-500/5 transition-all min-h-[220px]"
          >
            <span class="text-4xl mb-3 group-hover:scale-110 transition-transform">➕</span>
            <span class="text-sm font-bold text-slate-400 group-hover:text-purple-300 transition-colors">Create New Universe</span>
            <span class="text-[10px] text-slate-600 mt-1">Start from scratch</span>
          </button>

          <%!-- Saved World Cards --%>
          <%= for world <- @dashboard_worlds do %>
            <div class="relative rounded-xl border border-white/10 bg-white/[0.02] hover:border-purple-500/30 hover:bg-white/[0.04] transition-all overflow-hidden group">
              <%!-- Delete Confirmation Overlay --%>
              <%= if @dashboard_delete_confirm == world.id do %>
                <div class="absolute inset-0 z-10 bg-black/80 backdrop-blur-sm flex flex-col items-center justify-center gap-3 p-4 rounded-xl">
                  <span class="text-sm text-slate-300">Delete "<%= world.name %>"?</span>
                  <div class="flex gap-2">
                    <button phx-click="dashboard_delete" phx-value-id={world.id}
                      class="px-4 py-1.5 text-xs rounded-lg bg-red-500/20 border border-red-500/40 text-red-300 hover:bg-red-500/30 transition-all">
                      🗑️ Delete
                    </button>
                    <button phx-click="dashboard_delete_cancel"
                      class="px-4 py-1.5 text-xs rounded-lg bg-white/5 border border-white/10 text-slate-400 hover:bg-white/10 transition-all">
                      Cancel
                    </button>
                  </div>
                </div>
              <% end %>

              <%!-- Card Content --%>
              <div class="p-4">
                <%!-- 5x5 Terrain Thumbnail --%>
                <div class="flex justify-center mb-3">
                  <div class="grid grid-cols-8 gap-px w-16 h-16 rounded-lg overflow-hidden border border-white/10">
                    <%= for i <- 0..63 do %>
                      <div class={"w-full h-full #{WorldTemplates.thumb_color(world.template, i)}"} />
                    <% end %>
                  </div>
                </div>

                <%!-- World Info --%>
                <h3 class="text-sm font-bold text-slate-100 truncate text-center mb-2"><%= world.name %></h3>
                <div class="flex items-center justify-center gap-3 text-[10px] text-slate-500 mb-3">
                  <span>🗺️ <%= world.template %></span>
                  <span>👥 <%= world.agents %></span>
                  <span>⏱️ t:<%= world.tick %></span>
                </div>
                <div class="text-[9px] text-slate-600 text-center mb-3">
                  <%= if world.saved_at do %>
                    <%= Calendar.strftime(world.saved_at, "%b %d, %H:%M") %>
                  <% end %>
                </div>

                <%!-- Actions --%>
                <div class="flex gap-2">
                  <button phx-click="dashboard_load" phx-value-id={world.id}
                    class="flex-1 py-2 text-xs rounded-lg bg-gradient-to-r from-purple-600 to-cyan-600 text-white font-bold tracking-wider hover:from-purple-500 hover:to-cyan-500 transition-all text-center">
                    ▶ Play
                  </button>
                  <button phx-click="dashboard_delete_confirm" phx-value-id={world.id}
                    class="px-3 py-2 text-xs rounded-lg bg-white/5 border border-white/10 text-slate-500 hover:text-red-400 hover:border-red-500/30 transition-all">
                    🗑️
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Onboarding Wizard ──────────────────────────────────────

  defp render_onboarding(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050508] text-slate-200 font-mono overflow-y-auto">
      <%!-- Hero Section --%>
      <div class="relative flex flex-col items-center justify-center min-h-[60vh] px-4 pt-16 pb-8">
        <div class="absolute inset-0 overflow-hidden pointer-events-none">
          <div class="absolute top-1/4 left-1/4 w-96 h-96 bg-purple-600/10 rounded-full blur-3xl"></div>
          <div class="absolute bottom-1/4 right-1/4 w-96 h-96 bg-cyan-600/10 rounded-full blur-3xl"></div>
        </div>
        <div class="relative text-center mb-6">
          <h1 class="text-6xl md:text-7xl font-bold tracking-tighter mb-3">
            MODUS<span class="text-purple-400">_</span>
          </h1>
          <p class="text-lg text-slate-400 mb-2">Where Spinoza Meets Silicon</p>
          <p class="text-sm text-slate-600 max-w-md mx-auto">An AI-powered universe simulation built on Elixir/BEAM. Agents with emotions, memory, relationships, and free will — powered by Spinoza's philosophy of <em>conatus</em>.</p>
        </div>
        <div class="relative flex flex-wrap justify-center gap-3 mb-8 text-[10px] text-slate-500">
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">🧠 Conatus Engine</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">💬 LLM Conversations</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">🌍 Dynamic Environment</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">👶 Birth & Death Cycles</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">📚 Agent Learning</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">📜 Story Generation</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">👁️ God Mode</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">🔨 World Builder</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">🌿 Nature Resources</span>
          <span class="px-2 py-1 bg-white/5 rounded border border-white/10">🎛️ Custom Rules Engine</span>
        </div>
        <p class="text-xs text-slate-600 mb-6">v5.0.0 Forma · 92+ modules · Elixir/BEAM · Pixi.js</p>
      </div>

      <%!-- Create World Section --%>
      <div class="flex justify-center px-4 pb-16">
      <div class="w-full max-w-lg">

        <%!-- Step Indicator --%>
        <div class="flex items-center justify-center gap-2 mb-8">
          <div class="flex items-center gap-1.5 text-xs">
            <span class="w-6 h-6 rounded-full bg-purple-500/20 border border-purple-500/50 text-purple-400 flex items-center justify-center text-[10px] font-bold">1</span>
            <span class="text-purple-400 font-medium">Template</span>
          </div>
          <span class="text-slate-700">→</span>
          <div class="flex items-center gap-1.5 text-xs">
            <span class="w-6 h-6 rounded-full bg-white/5 border border-white/10 text-slate-500 flex items-center justify-center text-[10px] font-bold">2</span>
            <span class="text-slate-500">Rules</span>
          </div>
          <span class="text-slate-700">→</span>
          <div class="flex items-center gap-1.5 text-xs">
            <span class="w-6 h-6 rounded-full bg-white/5 border border-white/10 text-slate-500 flex items-center justify-center text-[10px] font-bold">3</span>
            <span class="text-slate-500">Create!</span>
          </div>
        </div>

        <%!-- Quick Start --%>
        <div class="mb-6 flex justify-center">
          <button
            phx-click="random_world"
            class="px-4 py-2 rounded-xl border border-amber-500/30 bg-amber-500/10 text-amber-400 text-sm hover:bg-amber-500/20 transition-all"
          >
            🎲 Random World — Quick Start
          </button>
        </div>

        <%!-- Step 1: Template --%>
        <div class="mb-6">
          <h3 class="text-[10px] uppercase tracking-wider text-slate-500 mb-3">Choose a World Template</h3>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 max-h-[420px] overflow-y-auto pr-1">
            <%= for t <- @templates do %>
              <% {diff_label, diff_color} = WorldTemplates.difficulty_badge(t) %>
              <button
                phx-click="select_template"
                phx-value-id={t.id}
                class={"p-3 rounded-xl border text-left transition-all #{if @template == t.id, do: "border-purple-500 bg-purple-500/10 shadow-lg shadow-purple-500/10", else: "border-white/10 bg-white/5 hover:border-white/20"}"}
              >
                <%!-- 8x8 Mini Terrain Preview --%>
                <div class="flex justify-center mb-2">
                  <div class="grid grid-cols-8 gap-px w-16 h-16 rounded-lg overflow-hidden border border-white/10">
                    <%= for i <- 0..63 do %>
                      <div class={"w-full h-full #{WorldTemplates.thumb_color(t.id, i)}"} />
                    <% end %>
                  </div>
                </div>
                <div class="text-lg text-center mb-0.5"><%= t.emoji %> <%= t.name %></div>
                <div class="text-[10px] text-slate-500 text-center"><%= t.desc %></div>
                <div class={"text-[9px] text-center mt-1 #{diff_color}"}><%= diff_label %></div>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Step 2: Population --%>
        <div class="mb-6">
          <h3 class="text-[10px] uppercase tracking-wider text-slate-500 mb-3">
            Population: <span class="text-purple-400"><%= @population %></span>
          </h3>
          <input
            type="range"
            min="2"
            max="50"
            value={@population}
            phx-change="set_population"
            name="value"
            class="w-full accent-purple-500 bg-white/5"
          />
          <div class="flex justify-between text-[10px] text-slate-600 mt-1">
            <span>2</span><span>25</span><span>50</span>
          </div>
        </div>

        <%!-- Step 3: Danger --%>
        <div class="mb-8">
          <h3 class="text-[10px] uppercase tracking-wider text-slate-500 mb-3">Danger Level</h3>
          <div class="flex gap-2">
            <%= for {val, label, emoji} <- [{"low", "Peaceful", "🕊️"}, {"normal", "Normal", "⚖️"}, {"high", "Harsh", "💀"}] do %>
              <button
                phx-click="set_danger"
                phx-value-value={val}
                class={"flex-1 py-2 px-3 rounded-lg border text-center text-xs transition-all #{if @danger == val, do: "border-purple-500 bg-purple-500/10", else: "border-white/10 bg-white/5 hover:border-white/20"}"}
              >
                <div class="text-lg"><%= emoji %></div>
                <div class="mt-0.5"><%= label %></div>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Step 4: World Language --%>
        <div class="mb-6">
          <h3 class="text-[10px] uppercase tracking-wider text-slate-500 mb-3">
            🌍 World Language: <span class="text-purple-400"><%= Modus.I18n.flag(@world_language) %> <%= Modus.I18n.label(@world_language) %></span>
          </h3>
          <div class="grid grid-cols-3 sm:grid-cols-6 gap-2">
            <%= for {code, flag, label} <- Modus.I18n.language_options() do %>
              <button
                phx-click="set_language"
                phx-value-value={code}
                class={"flex flex-col items-center py-2 px-2 rounded-lg border text-center text-xs transition-all #{if @world_language == code, do: "border-purple-500 bg-purple-500/10", else: "border-white/10 bg-white/5 hover:border-white/20"}"}
              >
                <div class="text-xl"><%= flag %></div>
                <div class="mt-0.5 text-[10px]"><%= label %></div>
              </button>
            <% end %>
          </div>
          <p class="text-[10px] text-slate-600 mt-1">Agents speak, think, and name themselves in this language</p>
        </div>

        <%!-- Step 5: Grid Size --%>
        <div class="mb-6">
          <h3 class="text-[10px] uppercase tracking-wider text-slate-500 mb-3">
            World Size: <span class="text-purple-400"><%= @grid_size %>×<%= @grid_size %></span>
          </h3>
          <input
            type="range"
            min="20"
            max="200"
            step="10"
            value={@grid_size}
            phx-change="set_grid_size"
            name="value"
            class="w-full accent-purple-500 bg-white/5"
          />
          <div class="flex justify-between text-[10px] text-slate-600 mt-1">
            <span>20</span><span>100</span><span>200</span>
          </div>
        </div>

        <%!-- Step 5: World Seed --%>
        <div class="mb-8">
          <h3 class="text-[10px] uppercase tracking-wider text-slate-500 mb-3">World Seed (optional)</h3>
          <input
            type="text"
            value={@world_seed}
            phx-change="set_seed"
            name="value"
            placeholder="Leave empty for random..."
            class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-purple-500/50"
          />
          <p class="text-[10px] text-slate-600 mt-1">Same seed = same world</p>
        </div>

        <%!-- Launch --%>
        <button
          phx-click="launch_world"
          class="w-full py-3 rounded-xl bg-gradient-to-r from-purple-600 to-cyan-600 text-white font-bold tracking-wider hover:from-purple-500 hover:to-cyan-500 transition-all shadow-lg shadow-purple-500/20"
        >
          ▶ CREATE WORLD
        </button>

        <button phx-click="skip_onboarding" class="w-full mt-3 py-2 text-xs text-slate-600 hover:text-slate-400 transition-colors">
          Skip — use defaults
        </button>

        <%= if @dashboard_worlds != [] do %>
          <button phx-click="dashboard_back" class="w-full mt-2 py-2 text-xs text-slate-600 hover:text-purple-400 transition-colors">
            ← Back to Universe Gallery
          </button>
        <% end %>
      </div>
      </div>
    </div>
    """
  end

  # ── Simulation View ────────────────────────────────────────

  defp render_simulation(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-[#050508] text-slate-200 font-mono overflow-hidden" phx-window-keydown="keypress">
      <%!-- Speculum Data Dashboard --%>
      <%= if @data_dashboard do %>
        <div class="fixed inset-0 z-50 bg-[#0A0A0F]/95 backdrop-blur-xl flex flex-col items-center justify-center p-6 overflow-auto">
          <div class="w-full max-w-7xl">
            <div class="flex justify-between items-center mb-6">
              <h2 class="text-2xl font-bold bg-gradient-to-r from-cyan-400 to-purple-400 bg-clip-text text-transparent">
                📊 SPECULUM — Analytics Dashboard
              </h2>
              <button phx-click="close_dashboard" class="text-slate-400 hover:text-white text-xl">✕</button>
            </div>
            <div class="grid grid-cols-3 gap-4">
              <div class="bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-4 shadow-lg shadow-cyan-500/5">
                <h3 class="text-xs font-semibold text-cyan-400 uppercase tracking-wider mb-2">Population</h3>
                <.population_chart data={@dash_population} />
              </div>
              <div class="bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-4 shadow-lg shadow-purple-500/5">
                <h3 class="text-xs font-semibold text-purple-400 uppercase tracking-wider mb-2">Resources</h3>
                <.resource_chart data={@dash_resources} />
              </div>
              <div class="bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-4 shadow-lg shadow-cyan-500/5">
                <h3 class="text-xs font-semibold text-cyan-400 uppercase tracking-wider mb-2">Relationships</h3>
                <.relationship_chart nodes={@dash_nodes} edges={@dash_edges} />
              </div>
              <div class="bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-4 shadow-lg shadow-purple-500/5">
                <h3 class="text-xs font-semibold text-purple-400 uppercase tracking-wider mb-2">Mood</h3>
                <.mood_chart data={@dash_moods} />
              </div>
              <div class="bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-4 shadow-lg shadow-cyan-500/5">
                <h3 class="text-xs font-semibold text-cyan-400 uppercase tracking-wider mb-2">Trade Volume</h3>
                <.trade_chart data={@dash_trades} />
              </div>
              <div class="bg-white/5 backdrop-blur-md border border-white/10 rounded-2xl p-4 shadow-lg shadow-purple-500/5">
                <h3 class="text-xs font-semibold text-purple-400 uppercase tracking-wider mb-2">Ecosystem</h3>
                <.ecosystem_chart predators={@dash_predators} prey={@dash_prey} agents={@agent_count} />
              </div>
            </div>
            <p class="text-center text-slate-500 text-xs mt-4">Press <kbd class="px-1.5 py-0.5 bg-white/10 rounded text-slate-300">D</kbd> to close</p>
          </div>
        </div>
      <% end %>
      <%!-- Imperium: Divine Intervention Panel --%>
      <%= if @divine_panel_open do %>
        <div class="fixed inset-0 z-50 bg-[#0A0A0F]/95 backdrop-blur-xl flex flex-col items-center justify-start p-6 overflow-auto">
          <div class="w-full max-w-4xl">
            <%!-- Header --%>
            <div class="flex justify-between items-center mb-6">
              <div>
                <h2 class="text-2xl font-bold bg-gradient-to-r from-amber-400 to-red-400 bg-clip-text text-transparent">
                  ⚡👑 IMPERIUM — İlahi Müdahale
                </h2>
                <p class="text-xs text-slate-500 mt-1">Deus sive Natura — Tanrılar izler, bazen müdahale eder.</p>
              </div>
              <button phx-click="toggle_divine_panel" class="text-slate-400 hover:text-white text-xl">✕</button>
            </div>

            <%!-- Tab Navigation --%>
            <div class="flex gap-2 mb-6">
              <%= for {tab, label, emoji} <- [{:events, "Olaylar", "🌍"}, {:agents, "Ajanlar", "👤"}, {:world, "Dünya", "🌤️"}, {:chains, "Zincirler", "⛓️"}, {:history, "Geçmiş", "📜"}] do %>
                <button phx-click="divine_tab" phx-value-tab={tab}
                  class={"px-4 py-2 text-xs rounded-lg border transition-all #{if @divine_tab == tab, do: "border-amber-500/50 bg-amber-500/10 text-amber-300", else: "border-white/10 bg-white/5 text-slate-500 hover:border-white/20"}"}>
                  <%= emoji %> <%= label %>
                </button>
              <% end %>
            </div>

            <%!-- Status Message --%>
            <%= if @divine_status do %>
              <div class="mb-4 px-4 py-2 rounded-lg bg-white/5 border border-white/10 text-xs text-slate-300">
                <%= @divine_status %>
              </div>
            <% end %>

            <%!-- Tab Content --%>
            <%= case @divine_tab do %>
              <% :events -> %>
                <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 gap-3">
                  <%= for cmd <- Enum.filter(Modus.Simulation.DivineIntervention.available_commands(), &(&1.category == :event)) do %>
                    <button phx-click="divine_command" phx-value-cmd={cmd.id}
                      class="flex flex-col items-center gap-2 p-4 rounded-xl border border-white/10 bg-white/[0.03] hover:border-amber-500/40 hover:bg-amber-500/5 transition-all group">
                      <span class="text-3xl group-hover:scale-110 transition-transform"><%= cmd.emoji %></span>
                      <span class="text-[11px] font-medium text-slate-300"><%= cmd.label %></span>
                      <span class="text-[9px] text-slate-600"><%= cmd.desc %></span>
                    </button>
                  <% end %>
                </div>

              <% :agents -> %>
                <div class="space-y-4">
                  <%= if @selected_agent do %>
                    <div class="px-4 py-3 rounded-xl border border-purple-500/30 bg-purple-500/5 mb-4">
                      <span class="text-xs text-purple-300">Seçili Ajan: <strong><%= @selected_agent["name"] %></strong></span>
                    </div>
                  <% else %>
                    <div class="px-4 py-3 rounded-xl border border-amber-500/30 bg-amber-500/5 mb-4">
                      <span class="text-xs text-amber-300">⚠️ Ajan komutları için önce haritadan bir ajan seçin</span>
                    </div>
                  <% end %>
                  <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
                    <%= for cmd <- Enum.filter(Modus.Simulation.DivineIntervention.available_commands(), &(&1.category == :agent)) do %>
                      <button phx-click="divine_command" phx-value-cmd={cmd.id}
                        class={"flex flex-col items-center gap-2 p-4 rounded-xl border transition-all group #{if @selected_agent || cmd.id == :spawn_agent, do: "border-white/10 bg-white/[0.03] hover:border-purple-500/40 hover:bg-purple-500/5", else: "border-white/5 bg-white/[0.01] opacity-50 cursor-not-allowed"}"}>
                        <span class="text-3xl group-hover:scale-110 transition-transform"><%= cmd.emoji %></span>
                        <span class="text-[11px] font-medium text-slate-300"><%= cmd.label %></span>
                        <span class="text-[9px] text-slate-600"><%= cmd.desc %></span>
                      </button>
                    <% end %>
                  </div>
                </div>

              <% :world -> %>
                <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
                  <%= for cmd <- Enum.filter(Modus.Simulation.DivineIntervention.available_commands(), &(&1.category == :world)) do %>
                    <button phx-click="divine_command" phx-value-cmd={cmd.id}
                      class="flex flex-col items-center gap-2 p-4 rounded-xl border border-white/10 bg-white/[0.03] hover:border-cyan-500/40 hover:bg-cyan-500/5 transition-all group">
                      <span class="text-3xl group-hover:scale-110 transition-transform"><%= cmd.emoji %></span>
                      <span class="text-[11px] font-medium text-slate-300"><%= cmd.label %></span>
                      <span class="text-[9px] text-slate-600"><%= cmd.desc %></span>
                    </button>
                  <% end %>
                </div>

              <% :chains -> %>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <%= for cmd <- Enum.filter(Modus.Simulation.DivineIntervention.available_commands(), &(&1.category == :chain)) do %>
                    <button phx-click="divine_command" phx-value-cmd={cmd.id}
                      class="flex flex-col items-center gap-3 p-6 rounded-xl border border-white/10 bg-white/[0.03] hover:border-red-500/40 hover:bg-red-500/5 transition-all group">
                      <span class="text-4xl group-hover:scale-110 transition-transform"><%= cmd.emoji %></span>
                      <span class="text-sm font-bold text-slate-200"><%= cmd.label %></span>
                      <span class="text-[10px] text-slate-500"><%= cmd.desc %></span>
                    </button>
                  <% end %>
                </div>

              <% :history -> %>
                <div class="space-y-2">
                  <div class="flex justify-between items-center mb-3">
                    <span class="text-xs text-slate-500">
                      Toplam komut: <span class="text-amber-400"><%= try do Modus.Simulation.DivineIntervention.total_commands() catch _, _ -> 0 end %></span>
                    </span>
                    <button phx-click="divine_clear_history" class="text-[10px] text-red-400 hover:text-red-300 px-2 py-1 rounded border border-red-500/20 hover:border-red-500/40">
                      🗑️ Temizle
                    </button>
                  </div>
                  <%= if @divine_history == [] do %>
                    <p class="text-xs text-slate-600 italic text-center py-8">Henüz ilahi müdahale yok...</p>
                  <% else %>
                    <%= for entry <- @divine_history do %>
                      <div class="flex items-center gap-3 px-3 py-2 rounded-lg border border-white/5 bg-white/[0.02]">
                        <span class={"w-2 h-2 rounded-full #{if entry.result == :ok, do: "bg-green-500", else: "bg-red-500"}"} />
                        <span class="text-xs text-amber-400 font-mono"><%= entry.command %></span>
                        <span class="text-[10px] text-slate-600 ml-auto tabular-nums">t:<%= entry.tick %></span>
                      </div>
                    <% end %>
                  <% end %>
                </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Zen Mode indicator --%>
      <%= if @zen_mode do %>
        <div class="fixed top-3 right-3 z-50 text-[10px] text-slate-600 bg-black/50 px-2 py-1 rounded backdrop-blur-sm">Z</div>
      <% end %>
      <%!-- Text Mode indicator --%>
      <%= if @text_mode do %>
        <div class="fixed top-3 left-3 z-50 text-[10px] text-cyan-400 bg-black/50 px-2 py-1 rounded backdrop-blur-sm">📝 TEXT MODE</div>
      <% end %>
      <%!-- Top Bar --%>
      <nav class={"modus-topbar px-4 md:px-6 h-14 flex items-center justify-between shrink-0 z-20" <> if(@zen_mode, do: " hidden", else: "")}>
        <div class="flex items-center gap-3">
          <span class="text-xl font-bold tracking-tighter">
            MODUS<span class="text-purple-400">_</span>
          </span>
          <span class="text-xs text-slate-600 hidden sm:inline">v5.0.0 · Forma</span>
          <%= if @rules["preset"] && @rules["preset"] != "Custom" do %>
            <span class="text-[10px] px-2 py-0.5 rounded bg-amber-500/10 border border-amber-500/30 text-amber-400 hidden sm:inline">
              🎛️ <%= @rules["preset"] %>
            </span>
          <% end %>
        </div>

        <div class="flex items-center gap-3 md:gap-6">
          <%!-- Stats --%>
          <div class="flex items-center gap-3 md:gap-4 text-xs text-slate-500">
            <%!-- Season indicator --%>
            <div class="flex items-center gap-1 px-2 py-0.5 rounded bg-slate-800/60 border border-slate-700/50">
              <span class="text-sm"><%= @season_emoji %></span>
              <span class="text-slate-300 font-medium text-[10px] uppercase tracking-wider"><%= @season_name %></span>
              <span class="text-slate-600 text-[9px]">Y<%= @season_year %></span>
            </div>
            <%!-- Weather indicator --%>
            <div class="flex items-center gap-1 px-2 py-0.5 rounded bg-slate-800/60 border border-slate-700/50">
              <span class="text-sm"><%= @weather_emoji %></span>
              <span class="text-slate-300 font-medium text-[10px] uppercase tracking-wider"><%= @weather_name %></span>
            </div>
            <%!-- Zoom level indicator --%>
            <div class="flex items-center gap-1 px-2 py-0.5 rounded bg-slate-800/60 border border-slate-700/50 hidden sm:flex" title="Zoom: +/- keys | F: Fog of War">
              <span class="text-sm">🔍</span>
              <span class="text-slate-300 font-medium text-[10px] uppercase tracking-wider" id="zoom-level-indicator">LOCAL</span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-sm"><%= if @time_of_day == "night", do: "🌙", else: "☀️" %></span>
              <span class="text-slate-600 hidden sm:inline">TICK</span>
              <span class="text-cyan-400 font-bold tabular-nums"><%= @tick %></span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-slate-600 hidden sm:inline">POP</span>
              <span class="text-purple-400 font-bold tabular-nums"><%= @agent_count %></span>
            </div>
            <div class="flex items-center gap-1.5 hidden sm:flex">
              <span class="text-green-400 tabular-nums" title="Trades">🤝<%= @trades_count %></span>
              <span class="text-cyan-400 tabular-nums" title="Births">👶<%= @births_count %></span>
              <span class="text-red-400 tabular-nums" title="Deaths">💀<%= @deaths_count %></span>
            </div>
            <span class={"px-2 py-0.5 rounded text-[10px] uppercase tracking-wider #{status_color(@status)}"}>
              <%= @status %>
            </span>
          </div>

          <%!-- Speed Controls --%>
          <div class="flex items-center gap-1">
            <%= for s <- [1, 5, 10] do %>
              <button
                phx-click="set_speed"
                phx-value-speed={s}
                class={"px-2 py-1 text-[10px] rounded transition-all #{if @speed == s, do: "bg-cyan-500/20 text-cyan-400 border border-cyan-500/30", else: "text-slate-600 hover:text-slate-400"}"}
              >
                <%= s %>x
              </button>
            <% end %>
          </div>

          <%!-- Play/Pause/Reset --%>
          <div class="flex items-center gap-1.5">
            <%= if @status == :running do %>
              <button phx-click="pause" class="ctrl-btn">⏸</button>
            <% else %>
              <button phx-click="start" class="ctrl-btn ctrl-btn-primary">▶</button>
            <% end %>
            <button phx-click="reset" class="ctrl-btn">↻</button>
          </div>

          <%!-- Agent Designer --%>
          <button phx-click="toggle_agent_designer" class={"ctrl-btn #{if @agent_designer_open, do: "ctrl-btn-active"}"} title="Agent Designer — Create Characters & Animals">
            ➕🧑
          </button>

          <%!-- Build Mode --%>
          <button phx-click="toggle_build_mode" class={"ctrl-btn #{if @build_mode, do: "ctrl-btn-active"}"} title="Build Mode — World Builder">
            🔨
          </button>

          <%!-- God Mode --%>
          <button phx-click="toggle_god_mode" class={"ctrl-btn #{if @god_mode, do: "ctrl-btn-active"}"} title="God Mode — See All Agent Internals">
            👁️
          </button>

          <%!-- Divine Intervention (Imperium) --%>
          <button phx-click="toggle_divine_panel" class={"ctrl-btn #{if @divine_panel_open, do: "ctrl-btn-active"}"} title="Divine Intervention — God Commands">
            ⚡👑
          </button>

          <%!-- Cinematic Camera --%>
          <button phx-click="toggle_cinematic" class={"ctrl-btn #{if @cinematic_mode, do: "ctrl-btn-active"}"} title="Cinematic Camera — Auto-follow Events">
            🎬
          </button>

          <%!-- Screenshot with World Name Overlay --%>
          <button phx-click="screenshot_with_overlay" class="ctrl-btn" title="Screenshot with World Name Overlay">
            📸
          </button>

          <%!-- Mind View Toggle --%>
          <button id="mind-view-btn" phx-click="toggle_mind_view" class={"ctrl-btn #{if @mind_view_active, do: "ctrl-btn-primary"}"} title="Mind View">
            🧠
          </button>

          <%!-- Timeline --%>
          <button phx-click="toggle_timeline" class={"ctrl-btn #{if @timeline_open, do: "ctrl-btn-primary"}"} title="Story Timeline">
            📜
          </button>

          <%!-- Event Timeline (Eventus) --%>
          <button phx-click="toggle_event_timeline" class={"ctrl-btn #{if @event_timeline_open, do: "ctrl-btn-active"}"} title="Event Timeline">
            🔔<%= if length(@event_timeline) > 0 do %><span class="text-[8px] text-red-400"><%= length(@event_timeline) %></span><% end %>
          </button>

          <%!-- LLM Metrics (M key) --%>
          <button phx-click="toggle_llm_metrics" class={"ctrl-btn #{if @llm_metrics_open, do: "ctrl-btn-primary"}"} title="LLM Metrics (M)">
            ⚡
          </button>

          <%!-- Observatory --%>
          <button phx-click="open_stats" class={"ctrl-btn #{if @stats_open, do: "ctrl-btn-primary"}"} title="Observatory Dashboard">
            📊
          </button>

          <%!-- World History --%>
          <button phx-click="open_history" class={"ctrl-btn #{if @history_open, do: "ctrl-btn-primary"}"} title="World History">
            📖
          </button>

          <%!-- Universe Gallery --%>
          <button phx-click="dashboard_back" class="ctrl-btn" title="Universe Gallery">
            🌍
          </button>

          <%!-- Save/Load --%>
          <button phx-click="open_save_load" class="ctrl-btn" title="Save / Load World">
            💾
          </button>

          <%!-- Export & Share --%>
          <button phx-click="open_export" class={"ctrl-btn #{if @export_open, do: "ctrl-btn-active"}"} title="Export / Import / Share World">
            📤
          </button>

          <%!-- Rules Engine --%>
          <button phx-click="open_rules" class={"ctrl-btn #{if @rules_open, do: "ctrl-btn-active"}"} title="World Rules">
            🎛️
          </button>

          <%!-- LLM indicator + Settings --%>
          <button phx-click="open_settings" class="ctrl-btn flex items-center gap-1.5" title="LLM Settings">
            <span class="text-[9px] text-slate-500 hidden sm:inline">
              <%= if @settings_provider == "antigravity", do: "🚀", else: "🦙" %>
              <%= String.slice(@settings_model, 0..12) %>
            </span>
            ⚙️
          </button>
        </div>
      </nav>

      <%!-- Main Area --%>
      <div class="flex-1 flex min-h-0 relative">
        <%!-- Left Sidebar: Event Injection + Timeline --%>
        <div class={"shrink-0 modus-sidebar overflow-y-auto z-10 transition-all duration-300 " <>
          if(@zen_mode, do: "hidden ", else: "hidden md:block ") <> if(@timeline_open, do: "md:w-64", else: "md:w-48")}>
          <div class="p-3">
            <%= if @agent_designer_open do %>
              <%!-- Agent Designer Panel --%>
              <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-3">➕ Agent Designer</h3>

              <%!-- Mode Toggle: Agent vs Animal --%>
              <div class="flex gap-1 mb-3">
                <button phx-click="set_designer_mode" phx-value-mode="agent"
                  class={"flex-1 py-1.5 text-[10px] rounded-lg border text-center transition-all " <>
                    if(@agent_designer_mode == :agent, do: "border-purple-500 bg-purple-500/10 text-purple-300", else: "border-white/10 bg-white/5 text-slate-500 hover:border-white/20")}>
                  🧑 Agent
                </button>
                <button phx-click="set_designer_mode" phx-value-mode="animal"
                  class={"flex-1 py-1.5 text-[10px] rounded-lg border text-center transition-all " <>
                    if(@agent_designer_mode == :animal, do: "border-cyan-500 bg-cyan-500/10 text-cyan-300", else: "border-white/10 bg-white/5 text-slate-500 hover:border-white/20")}>
                  🦌 Animal
                </button>
              </div>

              <form phx-change="designer_change">
              <%= if @agent_designer_mode == :agent do %>
                <%!-- Name --%>
                <div class="mb-3">
                  <label class="text-[9px] uppercase tracking-wider text-slate-600 block mb-1">Name</label>
                  <input type="text" name="name" value={@designer_name} placeholder="Agent name..."
                    class="w-full bg-white/5 border border-white/10 rounded-lg px-2 py-1.5 text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-purple-500/50" />
                </div>

                <%!-- Occupation --%>
                <div class="mb-3">
                  <label class="text-[9px] uppercase tracking-wider text-slate-600 block mb-1">Occupation</label>
                  <select name="occupation"
                    class="w-full bg-white/5 border border-white/10 rounded-lg px-2 py-1.5 text-xs text-slate-200 focus:outline-none focus:border-purple-500/50">
                    <%= for {occ, emoji} <- [{"farmer", "🌾"}, {"merchant", "💰"}, {"explorer", "🧭"}, {"healer", "💚"}, {"builder", "🏗️"}, {"guard", "🛡️"}, {"hunter", "🏹"}, {"fisher", "🎣"}, {"artist", "🎨"}, {"scholar", "📚"}] do %>
                      <option value={occ} selected={@designer_occupation == occ}><%= emoji %> <%= String.capitalize(occ) %></option>
                    <% end %>
                  </select>
                </div>

                <%!-- Mood --%>
                <div class="mb-3">
                  <label class="text-[9px] uppercase tracking-wider text-slate-600 block mb-1">Starting Mood</label>
                  <div class="grid grid-cols-2 gap-1">
                    <%= for {mood, emoji} <- [{"happy", "😊"}, {"calm", "😌"}, {"anxious", "😰"}, {"eager", "🔥"}] do %>
                      <button type="button" phx-click="designer_change" phx-value-mood={mood}
                        class={"flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] transition-all " <>
                          if(@designer_mood == mood,
                            do: "bg-purple-500/20 border border-purple-500/40 text-purple-300",
                            else: "bg-white/3 border border-white/5 text-slate-400 hover:border-white/10")}>
                        <span><%= emoji %></span><span><%= String.capitalize(mood) %></span>
                      </button>
                    <% end %>
                  </div>
                </div>

                <%!-- Big Five Personality Sliders --%>
                <div class="mb-3">
                  <label class="text-[9px] uppercase tracking-wider text-slate-600 block mb-2">Personality (Big Five)</label>
                  <%= for {trait, label, val} <- [{"o", "Openness", @designer_o}, {"c", "Conscientiousness", @designer_c}, {"e", "Extraversion", @designer_e}, {"a", "Agreeableness", @designer_a}, {"n", "Neuroticism", @designer_n}] do %>
                    <div class="mb-1.5">
                      <div class="flex justify-between text-[9px] mb-0.5">
                        <span class="text-slate-500"><%= label %></span>
                        <span class="text-cyan-400 tabular-nums"><%= val %></span>
                      </div>
                      <input type="range" name={trait} min="0" max="100" value={val}
                        class="w-full accent-purple-500 h-1" />
                    </div>
                  <% end %>
                </div>

              <% else %>
                <%!-- Animal Type --%>
                <div class="mb-3">
                  <label class="text-[9px] uppercase tracking-wider text-slate-600 block mb-2">Animal Type</label>
                  <div class="space-y-1.5">
                    <%= for {animal, emoji, desc} <- [{"deer", "🦌", "Peaceful grazer"}, {"rabbit", "🐇", "Quick & shy"}, {"wolf", "🐺", "Pack predator"}] do %>
                      <button type="button" phx-click="designer_change" phx-value-animal={animal}
                        class={"flex items-center gap-2 w-full px-2 py-2 rounded-lg text-[11px] transition-all " <>
                          if(@designer_animal == animal,
                            do: "bg-cyan-500/20 border border-cyan-500/40 text-cyan-300",
                            else: "bg-white/3 border border-white/5 text-slate-400 hover:border-white/10")}>
                        <span class="text-lg"><%= emoji %></span>
                        <div>
                          <div class="font-medium"><%= String.capitalize(animal) %></div>
                          <div class="text-[9px] text-slate-600"><%= desc %></div>
                        </div>
                      </button>
                    <% end %>
                  </div>
                </div>
              <% end %>
              </form>

              <%!-- Place Button --%>
              <button phx-click="designer_place"
                class={"w-full py-2 rounded-lg text-xs font-bold tracking-wider transition-all mt-2 " <>
                  if(@designer_placing,
                    do: "bg-green-500/20 border border-green-500/40 text-green-300 animate-pulse",
                    else: "bg-gradient-to-r from-purple-600 to-cyan-600 text-white hover:from-purple-500 hover:to-cyan-500")}>
                <%= if @designer_placing do %>
                  📍 Click on map to place...
                <% else %>
                  📍 Place on Map
                <% end %>
              </button>

              <div class="text-[9px] text-slate-600 mt-2 leading-relaxed">
                Design your character, then click "Place on Map" and click the world to spawn them.
              </div>

            <% else %>
            <%= if @build_mode do %>
              <%!-- Build Mode Palette --%>
              <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-3">🔨 World Builder</h3>

              <%!-- Terrain Brushes --%>
              <div class="mb-4">
                <div class="text-[9px] uppercase tracking-wider text-slate-600 mb-2">Terrain</div>
                <div class="grid grid-cols-2 gap-1.5">
                  <%= for {terrain, emoji, label} <- [{"grass", "🌿", "Grass"}, {"forest", "🌲", "Forest"}, {"water", "💧", "Water"}, {"mountain", "⛰️", "Mountain"}, {"desert", "🏜️", "Desert"}, {"sand", "🏖️", "Sand"}, {"farm", "🌾", "Farm"}, {"flowers", "🌸", "Flowers"}] do %>
                    <button
                      phx-click="set_build_brush"
                      phx-value-brush={terrain}
                      phx-value-type="terrain"
                      class={"flex items-center gap-1.5 px-2 py-1.5 rounded-lg text-[11px] transition-all " <>
                        if(@build_brush == terrain && @build_type == "terrain",
                          do: "bg-purple-500/20 border border-purple-500/40 text-purple-300",
                          else: "bg-white/3 border border-white/5 text-slate-400 hover:border-white/10")}
                    >
                      <span class="text-sm"><%= emoji %></span>
                      <span><%= label %></span>
                    </button>
                  <% end %>
                </div>
              </div>

              <%!-- Resource Node Brushes --%>
              <div class="mb-4">
                <div class="text-[9px] uppercase tracking-wider text-slate-600 mb-2">Resource Nodes</div>
                <div class="grid grid-cols-1 gap-1.5">
                  <%= for {node, emoji, label} <- [{"food_source", "🍖", "Food Source"}, {"water_well", "💧", "Water Well"}, {"wood_pile", "🪵", "Wood Pile"}, {"stone_quarry", "⛏️", "Stone Quarry"}] do %>
                    <button
                      phx-click="set_build_brush"
                      phx-value-brush={node}
                      phx-value-type="resource"
                      class={"flex items-center gap-1.5 px-2 py-1.5 rounded-lg text-[11px] transition-all " <>
                        if(@build_brush == node && @build_type == "resource",
                          do: "bg-cyan-500/20 border border-cyan-500/40 text-cyan-300",
                          else: "bg-white/3 border border-white/5 text-slate-400 hover:border-white/10")}
                    >
                      <span class="text-sm"><%= emoji %></span>
                      <span><%= label %></span>
                    </button>
                  <% end %>
                </div>
              </div>

              <%!-- Building Brushes (God Mode placement) --%>
              <div class="mb-4">
                <div class="text-[9px] uppercase tracking-wider text-slate-600 mb-2">Buildings</div>
                <div class="grid grid-cols-2 gap-1.5">
                  <%= for {btype, emoji, label} <- [{"hut", "🛋", "Hut"}, {"house", "🏠", "House"}, {"farm", "🌾", "Farm"}, {"market", "🏪", "Market"}, {"well", "🪣", "Well"}, {"watchtower", "🗼", "Tower"}] do %>
                    <button
                      phx-click="set_build_brush"
                      phx-value-brush={btype}
                      phx-value-type="building"
                      class={"flex items-center gap-1.5 px-2 py-1.5 rounded-lg text-[11px] transition-all " <>
                        if(@build_brush == btype && @build_type == "building",
                          do: "bg-amber-500/20 border border-amber-500/40 text-amber-300",
                          else: "bg-white/3 border border-white/5 text-slate-400 hover:border-white/10")}
                    >
                      <span class="text-sm"><%= emoji %></span>
                      <span><%= label %></span>
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="text-[9px] text-slate-600 leading-relaxed">
                Click/drag on map to paint.<br/>
                Resources respawn after 200 ticks.<br/>
                Buildings placed by God Mode have no owner.
              </div>

            <% else %>
            <%= if @timeline_open do %>
              <%!-- Timeline View --%>
              <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-3">📜 World Timeline</h3>
              <%= if @timeline_entries == [] do %>
                <p class="text-xs text-slate-600 italic">No notable events yet. Let the world run...</p>
              <% else %>
                <div class="space-y-2">
                  <%= for entry <- @timeline_entries do %>
                    <div class="border-l-2 border-purple-500/30 pl-2 py-1">
                      <div class="flex items-center gap-1.5">
                        <span class="text-sm"><%= entry.emoji %></span>
                        <span class="text-[9px] text-slate-600 tabular-nums">t:<%= entry.tick %></span>
                      </div>
                      <p class="text-[11px] text-slate-300 mt-0.5 leading-relaxed"><%= entry.narrative %></p>
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% else %>
              <%!-- Event Injection --%>
              <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-3">Inject Event</h3>
              <div class="space-y-2">
                <button phx-click="inject_event" phx-value-type="natural_disaster" class="event-btn">
                  <span class="text-lg">🌋</span>
                  <span class="text-xs">Disaster</span>
                </button>
                <button phx-click="inject_event" phx-value-type="migrant" class="event-btn">
                  <span class="text-lg">🚶</span>
                  <span class="text-xs">Migrant</span>
                </button>
                <button phx-click="inject_event" phx-value-type="resource_bonus" class="event-btn">
                  <span class="text-lg">🌾</span>
                  <span class="text-xs">Resources</span>
                </button>
              </div>

              <%!-- World Events (God Mode) --%>
              <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mt-5 mb-3">🌍 Trigger World Event</h3>
              <div class="grid grid-cols-2 gap-1.5">
                <button phx-click="trigger_world_event" phx-value-type="storm" class="event-btn">
                  <span class="text-lg">🌩️</span>
                  <span class="text-[10px]">Storm</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="earthquake" class="event-btn">
                  <span class="text-lg">🌍</span>
                  <span class="text-[10px]">Earthquake</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="meteor_shower" class="event-btn">
                  <span class="text-lg">☄️</span>
                  <span class="text-[10px]">Meteor</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="plague" class="event-btn">
                  <span class="text-lg">🦠</span>
                  <span class="text-[10px]">Plague</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="golden_age" class="event-btn">
                  <span class="text-lg">✨</span>
                  <span class="text-[10px]">Golden Age</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="flood" class="event-btn">
                  <span class="text-lg">🌊</span>
                  <span class="text-[10px]">Flood</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="fire" class="event-btn">
                  <span class="text-lg">🔥</span>
                  <span class="text-[10px]">Fire</span>
                </button>
              </div>

              <%!-- Eventus v2: New Event Types --%>
              <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mt-4 mb-3">🎭 Eventus v2</h3>
              <div class="grid grid-cols-2 gap-1.5">
                <button phx-click="trigger_world_event" phx-value-type="drought" class="event-btn">
                  <span class="text-lg">🏜️</span>
                  <span class="text-[10px]">Drought</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="famine" class="event-btn">
                  <span class="text-lg">💀🌾</span>
                  <span class="text-[10px]">Famine</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="festival" class="event-btn">
                  <span class="text-lg">🎉</span>
                  <span class="text-[10px]">Festival</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="discovery" class="event-btn">
                  <span class="text-lg">🗺️</span>
                  <span class="text-[10px]">Discovery</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="migration_wave" class="event-btn">
                  <span class="text-lg">🚶</span>
                  <span class="text-[10px]">Migration</span>
                </button>
                <button phx-click="trigger_world_event" phx-value-type="conflict" class="event-btn">
                  <span class="text-lg">⚔️</span>
                  <span class="text-[10px]">Conflict</span>
                </button>
              </div>

              <%!-- Event Feed --%>
              <%= if @event_feed != [] do %>
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mt-5 mb-2">Recent Events</h3>
                <div class="space-y-1.5">
                  <%= for event <- @event_feed do %>
                    <div class="text-[11px] text-slate-400 flex items-center gap-1.5">
                      <span><%= event.emoji %></span>
                      <span class="truncate"><%= event.label %></span>
                      <span class="text-slate-600 ml-auto text-[9px]">t:<%= event.tick %></span>
                    </div>
                  <% end %>
                </div>
              <% end %>
            <% end %>
            <% end %>
            <% end %>
          </div>
        </div>

        <%!-- Canvas Container --%>
        <div id="world-canvas" phx-hook="WorldCanvas" phx-update="ignore" class="flex-1 min-w-0 relative overflow-hidden">
          <%!-- Loading Skeleton --%>
          <div id="canvas-skeleton" class="absolute inset-0 flex items-center justify-center pointer-events-none">
            <div class="flex flex-col items-center gap-3">
              <div class="w-12 h-12 border-2 border-purple-500/30 border-t-purple-500 rounded-full animate-spin"></div>
              <span class="text-xs text-slate-600 animate-pulse">Initializing universe...</span>
            </div>
          </div>

          <div class={"absolute bottom-4 left-4 text-[10px] text-slate-600 pointer-events-none hidden md:block" <> if(@zen_mode, do: " !hidden", else: "")}>
            Click agent to inspect · Drag to pan · Scroll to zoom · <span class="text-slate-500">Space</span>=pause · <span class="text-slate-500">1/5/0</span>=speed · <span class="text-slate-500">G</span>=god · <span class="text-slate-500">C</span>=cinematic · <span class="text-slate-500">P</span>=screenshot · <span class="text-slate-500">M</span>=minimap · <span class="text-slate-500">T</span>=text · <span class="text-slate-500">Z</span>=zen · <span class="text-slate-500">Esc</span>=deselect
          </div>
        </div>

        <%!-- Right Panel: Agent Detail (desktop) --%>
        <%= if @selected_agent && !@zen_mode do %>
          <div class={"shrink-0 modus-sidebar-right overflow-y-auto z-10 transition-all duration-300 " <>
            "fixed inset-x-0 bottom-0 top-14 md:static md:w-80 " <>
            if(@mobile_panel == :agent, do: "translate-y-0", else: "translate-y-full md:translate-y-0")}>
            <div class="p-4">
              <%!-- God Mode Banner --%>
              <%= if @god_mode do %>
                <div class="mb-3 px-2 py-1 rounded bg-cyan-500/10 border border-cyan-500/30 text-[10px] text-cyan-400 text-center uppercase tracking-wider">
                  👁️ God Mode Active
                </div>
              <% end %>

              <%!-- Header --%>
              <div class="flex items-center justify-between mb-4">
                <div>
                  <h2 class="text-lg font-bold text-slate-100"><%= @selected_agent["name"] %></h2>
                  <span class="text-xs text-purple-400"><%= @selected_agent["occupation"] %></span>
                </div>
                <button phx-click="deselect_agent" class="text-slate-600 hover:text-slate-400 text-lg">✕</button>
              </div>

              <%!-- Status --%>
              <div class="text-xs text-slate-500 mb-4 flex items-center gap-2">
                <span class={"w-2 h-2 rounded-full #{if @selected_agent["alive"], do: "bg-green-500 shadow-lg shadow-green-500/50", else: "bg-red-500"}"} />
                <%= if @selected_agent["alive"], do: "Alive", else: "Dead" %>
                · Age: <%= @selected_agent["age"] || 0 %>
                · Conatus: <%= @selected_agent["conatus"] || 0 %>
              </div>

              <%!-- Conatus & Affect --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Mind State</h3>
                <%!-- Conatus Energy --%>
                <div class="mb-2">
                  <div class="flex justify-between text-[10px] mb-0.5">
                    <span class="text-slate-500">⚡ Conatus Energy</span>
                    <span class="text-slate-400 tabular-nums"><%= Float.round(ensure_float(@selected_agent["conatus_energy"] || 0.7) * 100, 1) %>%</span>
                  </div>
                  <div class="h-2 bg-white/5 rounded-full overflow-hidden">
                    <% ce = ensure_float(@selected_agent["conatus_energy"] || 0.7) %>
                    <div class={"h-full rounded-full transition-all duration-500 #{cond do ce > 0.6 -> "bg-green-500"; ce > 0.3 -> "bg-yellow-500"; true -> "bg-red-500" end}"} style={"width: #{min(ce * 100, 100)}%"} />
                  </div>
                </div>
                <%!-- Affect State --%>
                <div class="mb-2">
                  <div class="flex items-center gap-2 text-sm">
                    <span>
                      <%= case @selected_agent["affect_state"] || "neutral" do
                        "joy" -> "😊"
                        "sadness" -> "😢"
                        "desire" -> "🔥"
                        "fear" -> "😨"
                        _ -> "😐"
                      end %>
                    </span>
                    <span class="text-slate-300 capitalize"><%= @selected_agent["affect_state"] || "neutral" %></span>
                  </div>
                </div>
                <%!-- Affect History --%>
                <%= if @selected_agent["affect_history"] && @selected_agent["affect_history"] != [] do %>
                  <div class="mt-2">
                    <div class="text-[10px] text-slate-600 mb-1">Recent transitions:</div>
                    <%= for t <- @selected_agent["affect_history"] || [] do %>
                      <div class="text-[10px] text-slate-400 mb-0.5 flex items-center gap-1">
                        <span class="text-slate-600">t:<%= t["tick"] %></span>
                        <span class="text-slate-500"><%= t["from"] %></span>
                        <span class="text-slate-600">→</span>
                        <span class="text-cyan-400"><%= t["to"] %></span>
                        <span class="text-slate-600 truncate ml-1"><%= t["reason"] %></span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%!-- Memories --%>
              <%= if @selected_agent["memories"] && @selected_agent["memories"] != [] do %>
                <div class="mb-4">
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">🧠 Memories</h3>
                  <div class="space-y-1">
                    <%= for m <- @selected_agent["memories"] do %>
                      <div class="text-[10px] text-slate-400 flex items-center gap-1 border-l-2 border-purple-500/20 pl-2">
                        <span>
                          <%= case m["affect_to"] do
                            "joy" -> "😊"
                            "sadness" -> "😢"
                            "desire" -> "🔥"
                            "fear" -> "😨"
                            _ -> "😐"
                          end %>
                        </span>
                        <span class="text-slate-600">t:<%= m["tick"] %></span>
                        <span class="truncate"><%= m["reason"] %></span>
                        <span class="text-slate-600 ml-auto text-[9px]">s:<%= m["salience"] %></span>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Last Reasoning --%>
              <%= if @selected_agent["last_reasoning"] do %>
                <div class="mb-4">
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">💭 Last Reasoning</h3>
                  <div class="text-xs text-slate-300 bg-purple-500/10 border border-purple-500/20 rounded-lg p-2">
                    <%= @selected_agent["last_reasoning"] %>
                  </div>
                </div>
              <% end %>

              <%!-- Needs Bars --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Needs</h3>
                <%= if @selected_agent["needs"] do %>
                  <%= for {need, val, emoji} <- [{"hunger", @selected_agent["needs"]["hunger"], "🌾"}, {"social", @selected_agent["needs"]["social"], "💬"}, {"rest", @selected_agent["needs"]["rest"], "😴"}, {"shelter", @selected_agent["needs"]["shelter"], "🏠"}] do %>
                    <div class="mb-1.5">
                      <div class="flex justify-between text-[10px] mb-0.5">
                        <span class="text-slate-500"><%= emoji %> <%= String.capitalize(need) %></span>
                        <span class="text-slate-400 tabular-nums"><%= val || 0 %></span>
                      </div>
                      <div class="h-1.5 bg-white/5 rounded-full overflow-hidden">
                        <div class={"h-full rounded-full transition-all duration-500 #{need_bar_color(need, val || 0)}"} style={"width: #{min(val || 0, 100)}%"} />
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <%!-- Skills (Sapientia) --%>
              <%= if @selected_agent["skills"] && @selected_agent["skills"] != %{} do %>
                <div class="mb-4">
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">📚 Skills</h3>
                  <%= for {skill, data} <- @selected_agent["skills"] || %{} do %>
                    <% skill_emoji = case skill do
                      "farming" -> "🌾"
                      "building" -> "🏗️"
                      "social" -> "💬"
                      "exploration" -> "🧭"
                      "healing" -> "💚"
                      "trading" -> "💰"
                      _ -> "⭐"
                    end %>
                    <div class="mb-1.5">
                      <div class="flex justify-between text-[10px] mb-0.5">
                        <span class="text-slate-500"><%= skill_emoji %> <%= String.capitalize(skill) %></span>
                        <span class="text-slate-400 tabular-nums">Lv.<%= data["level"] || 0 %> · <%= data["xp"] || 0 %> xp</span>
                      </div>
                      <div class="h-1.5 bg-white/5 rounded-full overflow-hidden">
                        <div class="h-full bg-amber-500/70 rounded-full transition-all duration-500" style={"width: #{data["progress"] || 0}%"} />
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- Personality --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Personality (Big Five)</h3>
                <%= if @selected_agent["personality"] do %>
                  <%= for {trait, val} <- [{"O", @selected_agent["personality"]["openness"]}, {"C", @selected_agent["personality"]["conscientiousness"]}, {"E", @selected_agent["personality"]["extraversion"]}, {"A", @selected_agent["personality"]["agreeableness"]}, {"N", @selected_agent["personality"]["neuroticism"]}] do %>
                    <div class="flex items-center gap-2 mb-1">
                      <span class="text-[10px] text-cyan-400 w-3 font-bold"><%= trait %></span>
                      <div class="flex-1 h-1 bg-white/5 rounded-full overflow-hidden">
                        <div class="h-full bg-cyan-500/60 rounded-full transition-all duration-500" style={"width: #{(val || 0) * 100}%"} />
                      </div>
                      <span class="text-[10px] text-slate-500 tabular-nums w-6 text-right"><%= Float.round(ensure_float(val || 0), 2) %></span>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <%!-- Relationships --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">🤝 Relationships</h3>
                <%= if @selected_agent["relationships"] && @selected_agent["relationships"] != [] do %>
                  <div class="space-y-1.5">
                    <%= for rel <- @selected_agent["relationships"] do %>
                      <div class="mb-1">
                        <div class="flex justify-between text-[10px] mb-0.5">
                          <span class="text-slate-400">
                            <%= rel_type_emoji(rel["type"]) %>
                            <%= resolve_agent_name(rel["agent_id"]) %>
                          </span>
                          <span class={"text-[9px] #{rel_type_color(rel["type"])}"}><%= rel["type"] %></span>
                        </div>
                        <div class="h-1.5 bg-white/5 rounded-full overflow-hidden">
                          <div class={"h-full rounded-full transition-all duration-500 #{rel_bar_color(rel["strength"] || 0)}"} style={"width: #{min((rel["strength"] || 0) * 100, 100)}%"} />
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-xs text-slate-600 italic">No relationships yet</p>
                <% end %>
              </div>

              <%!-- Recent Conversations --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">💬 Recent Conversations</h3>
                <%= if conversation_events(@selected_agent) != [] do %>
                  <div class="space-y-1.5">
                    <%= for event <- conversation_events(@selected_agent) do %>
                      <div class="text-[10px] text-slate-400 border-l-2 border-cyan-500/20 pl-2">
                        <span class="text-slate-600">t:<%= event["tick"] %></span>
                        <%= if event["data"] && event["data"]["dialogue"] do %>
                          <%= cond do %>
                            <% is_list(event["data"]["dialogue"]) -> %>
                              <%= for line <- Enum.take(event["data"]["dialogue"], 2) do %>
                                <div class="text-slate-300 mt-0.5">
                                  <span class="text-cyan-400"><%= line["speaker"] %>:</span>
                                  <span class="truncate"><%= line["line"] %></span>
                                </div>
                              <% end %>
                            <% is_binary(event["data"]["dialogue"]) -> %>
                              <div class="text-slate-300 mt-0.5 truncate"><%= String.slice(event["data"]["dialogue"], 0..120) %></div>
                            <% true -> %>
                              <span class="italic">Conversation</span>
                          <% end %>
                        <% else %>
                          <span class="italic">Conversation</span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-xs text-slate-600 italic">No conversations yet</p>
                <% end %>
              </div>

              <%!-- Recent Events --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Recent Events</h3>
                <%= if @selected_agent["recent_events"] && @selected_agent["recent_events"] != [] do %>
                  <%= for event <- @selected_agent["recent_events"] do %>
                    <div class="text-xs text-slate-400 mb-1.5 border-l-2 border-white/5 pl-2">
                      <span class="text-cyan-400"><%= event_emoji(event["type"]) %> <%= event["type"] %></span>
                      <span class="text-slate-600"> t:<%= event["tick"] %></span>
                    </div>
                  <% end %>
                <% else %>
                  <p class="text-xs text-slate-600 italic">No events yet</p>
                <% end %>
              </div>

              <%!-- Inventory --%>
              <%= if @selected_agent["inventory"] && @selected_agent["inventory"] != %{} do %>
                <div class="mb-4">
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">🎒 Inventory</h3>
                  <div class="grid grid-cols-2 gap-1.5">
                    <%= for {item, amount} <- @selected_agent["inventory"] || %{} do %>
                      <% item_emoji = case item do
                        "wood" -> "🪵"
                        "stone" -> "⛏️"
                        "fish" -> "🐟"
                        "fresh_water" -> "💧"
                        "crops" -> "🌾"
                        "herbs" -> "🌿"
                        "wild_berries" -> "🫐"
                        "food" -> "🍖"
                        _ -> "📦"
                      end %>
                      <div class="flex items-center gap-1.5 px-2 py-1 rounded bg-white/3 border border-white/5 text-[10px]">
                        <span><%= item_emoji %></span>
                        <span class="text-slate-400"><%= item %></span>
                        <span class="text-cyan-400 ml-auto tabular-nums"><%= amount %></span>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Goals --%>
              <div class="mb-4">
                <div class="flex items-center justify-between mb-2">
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600">🎯 Goals</h3>
                  <button phx-click="toggle_add_goal" class="text-[10px] text-purple-400 hover:text-purple-300 transition-colors">+ Add</button>
                </div>
                <%= if @show_add_goal do %>
                  <div class="mb-2 p-2 rounded bg-white/3 border border-purple-500/20 space-y-1.5">
                    <%= for {type, label, emoji} <- [{"build_home", "Build a Home", "🏠"}, {"make_friends", "Make Friends", "🤝"}, {"explore_map", "Explore Map", "🗺️"}, {"gather_resources", "Gather Resources", "📦"}, {"survive_winter", "Survive Winter", "❄️"}] do %>
                      <button phx-click="add_goal" phx-value-type={type} class="w-full text-left px-2 py-1 rounded text-[10px] text-slate-400 hover:bg-white/5 hover:text-slate-200 transition-colors">
                        <%= emoji %> <%= label %>
                      </button>
                    <% end %>
                  </div>
                <% end %>
                <%= if @selected_agent["goals"] && @selected_agent["goals"] != [] do %>
                  <div class="space-y-2">
                    <%= for goal <- @selected_agent["goals"] do %>
                      <div class="p-2 rounded bg-white/3 border border-white/5">
                        <div class="flex items-center justify-between mb-1">
                          <span class="text-[10px] text-slate-300">
                            <%= goal_emoji(goal["type"]) %> <%= goal_label(goal["type"], goal["target"]) %>
                          </span>
                          <%= if goal["status"] == "completed" do %>
                            <span class="text-[9px] text-green-400">✓ Done</span>
                          <% else %>
                            <button phx-click="remove_goal" phx-value-goal-id={goal["id"]} class="text-[9px] text-red-400/50 hover:text-red-400">✕</button>
                          <% end %>
                        </div>
                        <div class="h-1.5 bg-white/5 rounded-full overflow-hidden">
                          <div class={"h-full rounded-full transition-all duration-700 #{if goal["status"] == "completed", do: "bg-green-500", else: "bg-purple-500/70"}"} style={"width: #{(goal["progress"] || 0) * 100}%"} />
                        </div>
                        <span class="text-[9px] text-slate-600 tabular-nums"><%= round((goal["progress"] || 0) * 100) %>%</span>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-xs text-slate-600 italic">No goals yet</p>
                <% end %>
              </div>

              <%!-- Culture --%>
              <%= if @selected_agent["culture"] do %>
                <div class="mb-4">
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">🎭 Culture</h3>
                  <%!-- Catchphrases --%>
                  <%= if @selected_agent["culture"]["catchphrases"] && @selected_agent["culture"]["catchphrases"] != [] do %>
                    <div class="mb-2">
                      <div class="text-[10px] text-slate-500 mb-1">Catchphrases:</div>
                      <%= for phrase <- @selected_agent["culture"]["catchphrases"] do %>
                        <div class="text-[10px] text-slate-300 mb-1 flex items-center gap-1 border-l-2 border-amber-500/20 pl-2">
                          <span class="italic truncate">"<%= phrase["text"] %>"</span>
                          <span class="text-slate-600 ml-auto text-[9px] shrink-0"><%= phrase["strength"] %></span>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <p class="text-[10px] text-slate-600 italic mb-2">No catchphrases yet</p>
                  <% end %>
                  <%!-- Traditions --%>
                  <%= if @selected_agent["culture"]["traditions"] && @selected_agent["culture"]["traditions"] != [] do %>
                    <div>
                      <div class="text-[10px] text-slate-500 mb-1">Community Traditions:</div>
                      <%= for trad <- @selected_agent["culture"]["traditions"] do %>
                        <div class="text-[10px] text-slate-400 mb-1.5 p-1.5 rounded bg-white/3 border border-white/5">
                          <div class="flex justify-between">
                            <span class="text-amber-400"><%= trad["name"] %></span>
                            <span class="text-slate-600 text-[9px]"><%= trad["season"] %> · <%= trad["strength"] %></span>
                          </div>
                          <div class="text-slate-500 mt-0.5 truncate"><%= trad["description"] %></div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%!-- Chat Button --%>
              <button phx-click="open_chat" class="w-full ctrl-btn ctrl-btn-primary text-center">
                💬 Chat with <%= @selected_agent["name"] %>
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Mobile Bottom Bar --%>
        <div class={"fixed bottom-0 inset-x-0 md:hidden bg-[#0A0A0F]/95 backdrop-blur-md border-t border-white/5 z-30 px-2 py-2 flex items-center justify-around" <> if(@zen_mode, do: " hidden", else: "")}>
          <button phx-click="inject_event" phx-value-type="natural_disaster" class="mobile-action-btn">🌋</button>
          <button phx-click="inject_event" phx-value-type="migrant" class="mobile-action-btn">🚶</button>
          <button phx-click="inject_event" phx-value-type="resource_bonus" class="mobile-action-btn">🌾</button>
          <div class="w-px h-6 bg-white/10"></div>
          <%= if @selected_agent do %>
            <button phx-click="toggle_panel" phx-value-panel="agent" class="mobile-action-btn text-purple-400">👤</button>
          <% end %>
        </div>
      </div>

      <%!-- Settings Modal --%>
      <%= if @settings_open do %>
        <div class="fixed inset-0 modus-modal-overlay z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-md flex flex-col shadow-2xl" phx-click-away="close_settings">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <span class="font-bold text-slate-100">⚙️ LLM Settings</span>
              <button phx-click="close_settings" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>
            <form phx-change="settings_change" phx-submit="save_settings" class="p-4 space-y-4">
              <%!-- Provider --%>
              <div>
                <label class="text-[10px] uppercase tracking-wider text-slate-600 block mb-1">Provider</label>
                <select name="provider"
                  class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-purple-500/50">
                  <option value="ollama" selected={@settings_provider == "ollama"}>🦙 Ollama (local)</option>
                  <option value="antigravity" selected={@settings_provider == "antigravity"}>🚀 Antigravity (gateway)</option>
                </select>
              </div>

              <%!-- Model --%>
              <div>
                <label class="text-[10px] uppercase tracking-wider text-slate-600 block mb-1">Model</label>
                <select id={"model-select-#{@settings_provider}"} name="model"
                  class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-purple-500/50">
                  <%= if @settings_provider == "ollama" do %>
                    <option value="llama3.2:3b-instruct-q4_K_M" selected={@settings_model == "llama3.2:3b-instruct-q4_K_M"}>🦙 Llama 3.2 3B (Q4)</option>
                  <% else %>
                    <option value="gemini-3-flash" selected={@settings_model == "gemini-3-flash"}>⚡ Gemini 3 Flash</option>
                    <option value="gemini-3-pro-high" selected={@settings_model == "gemini-3-pro-high"}>🧠 Gemini 3 Pro High</option>
                    <option value="claude-sonnet-4-5-thinking" selected={@settings_model == "claude-sonnet-4-5-thinking"}>💜 Claude Sonnet 4.5</option>
                    <option value="claude-opus-4-6-thinking" selected={@settings_model == "claude-opus-4-6-thinking"}>👑 Claude Opus 4.6</option>
                    <option value="gpt-4.1" selected={@settings_model == "gpt-4.1"}>🟢 GPT-4.1</option>
                    <option value="__custom__" selected={@settings_model not in ~w(gemini-3-flash gemini-3-pro-high claude-sonnet-4-5-thinking claude-opus-4-6-thinking gpt-4.1)}>✏️ Custom...</option>
                  <% end %>
                </select>
                <%= if @settings_provider == "antigravity" and @settings_model not in ~w(gemini-3-flash gemini-3-pro-high claude-sonnet-4-5-thinking claude-opus-4-6-thinking gpt-4.1) do %>
                  <input type="text" name="model" value={@settings_model} placeholder="Custom model name..."
                    class="w-full mt-2 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-purple-500/50" />
                <% end %>
              </div>

              <%!-- Base URL --%>
              <div>
                <label class="text-[10px] uppercase tracking-wider text-slate-600 block mb-1">Base URL</label>
                <input type="text" name="base_url" value={@settings_base_url}
                  class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-purple-500/50" />
              </div>

              <%!-- API Key --%>
              <%= if @settings_provider == "antigravity" do %>
                <div>
                  <label class="text-[10px] uppercase tracking-wider text-slate-600 block mb-1">API Key</label>
                  <input type="password" name="api_key" value={@settings_api_key}
                    class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-purple-500/50" />
                </div>
              <% end %>

              <%!-- Test Result --%>
              <%= if @settings_test_result do %>
                <div class={"text-sm px-3 py-2 rounded-lg #{if @settings_test_result == "ok", do: "bg-green-500/10 text-green-400", else: "bg-red-500/10 text-red-400"}"}>
                  <%= if @settings_test_result == "ok" do %>
                    ✅ Connection successful
                  <% else %>
                    ❌ <%= @settings_test_result %>
                  <% end %>
                </div>
              <% end %>

              <%!-- Save feedback --%>
              <%= if @settings_saved do %>
                <div class="text-sm px-3 py-2 rounded-lg bg-green-500/10 text-green-400 text-center">
                  ✅ Saved!
                </div>
              <% end %>

              <%!-- Buttons --%>
              <div class="flex gap-2">
                <button type="button" phx-click="test_llm" class="ctrl-btn flex-1 text-center" disabled={@settings_testing}>
                  <%= if @settings_testing, do: "⏳ Testing...", else: "🔌 Test" %>
                </button>
                <button type="submit" class="ctrl-btn ctrl-btn-primary flex-1 text-center">💾 Save</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <%!-- Rules Engine Modal --%>
      <%= if @rules_open do %>
        <div class="fixed inset-0 modus-modal-overlay z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-md max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_rules">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <span class="font-bold text-slate-100">🎛️ World Rules</span>
              <button phx-click="close_rules" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>
            <div class="p-4 space-y-4 overflow-y-auto">
              <%!-- Presets --%>
              <div>
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Presets</h3>
                <div class="flex flex-wrap gap-1.5">
                  <%= for preset <- @rules_presets do %>
                    <button phx-click="apply_rules_preset" phx-value-preset={preset}
                      class={"px-3 py-1.5 text-[10px] rounded-lg border transition-all " <>
                        if(@rules["preset"] == preset,
                          do: "border-amber-500/50 bg-amber-500/10 text-amber-300",
                          else: "border-white/10 bg-white/3 text-slate-500 hover:border-white/20")}>
                      <%= preset %>
                    </button>
                  <% end %>
                </div>
              </div>

              <form phx-change="rules_change">
                <%!-- Time Speed --%>
                <div class="mb-3">
                  <div class="flex justify-between text-[10px] mb-1">
                    <span class="text-slate-500">⏱️ Time Speed</span>
                    <span class="text-cyan-400 tabular-nums"><%= @rules["time_speed"] %>x</span>
                  </div>
                  <input type="range" name="time_speed" min="0.5" max="3.0" step="0.1" value={@rules["time_speed"]}
                    class="w-full accent-purple-500 h-1" />
                  <div class="flex justify-between text-[9px] text-slate-600 mt-0.5">
                    <span>0.5x</span><span>1x</span><span>3x</span>
                  </div>
                </div>

                <%!-- Resource Abundance --%>
                <div class="mb-3">
                  <div class="text-[10px] text-slate-500 mb-1">🌾 Resource Abundance</div>
                  <div class="flex gap-1.5">
                    <%= for {val, label} <- [{"scarce", "Scarce"}, {"normal", "Normal"}, {"abundant", "Abundant"}] do %>
                      <button type="button" phx-click="rules_change" phx-value-resource_abundance={val}
                        class={"flex-1 py-1.5 text-[10px] rounded-lg border text-center transition-all " <>
                          if(@rules["resource_abundance"] == val,
                            do: "border-purple-500 bg-purple-500/10 text-purple-300",
                            else: "border-white/10 bg-white/5 text-slate-500 hover:border-white/20")}>
                        <%= label %>
                      </button>
                    <% end %>
                  </div>
                </div>

                <%!-- Danger Level --%>
                <div class="mb-3">
                  <div class="text-[10px] text-slate-500 mb-1">⚠️ Danger Level</div>
                  <div class="flex gap-1.5">
                    <%= for {val, label} <- [{"peaceful", "🕊️"}, {"moderate", "⚖️"}, {"harsh", "💀"}, {"extreme", "☠️"}] do %>
                      <button type="button" phx-click="rules_change" phx-value-danger_level={val}
                        class={"flex-1 py-1.5 text-[10px] rounded-lg border text-center transition-all " <>
                          if(@rules["danger_level"] == val,
                            do: "border-red-500 bg-red-500/10 text-red-300",
                            else: "border-white/10 bg-white/5 text-slate-500 hover:border-white/20")}>
                        <%= label %>
                      </button>
                    <% end %>
                  </div>
                </div>

                <%!-- Social Tendency --%>
                <div class="mb-3">
                  <div class="flex justify-between text-[10px] mb-1">
                    <span class="text-slate-500">💬 Social Tendency</span>
                    <span class="text-cyan-400 tabular-nums"><%= @rules["social_tendency"] %></span>
                  </div>
                  <input type="range" name="social_tendency" min="0.0" max="1.0" step="0.1" value={@rules["social_tendency"]}
                    class="w-full accent-purple-500 h-1" />
                </div>

                <%!-- Birth Rate --%>
                <div class="mb-3">
                  <div class="flex justify-between text-[10px] mb-1">
                    <span class="text-slate-500">👶 Birth Rate</span>
                    <span class="text-cyan-400 tabular-nums"><%= @rules["birth_rate"] %>x</span>
                  </div>
                  <input type="range" name="birth_rate" min="0.0" max="2.0" step="0.1" value={@rules["birth_rate"]}
                    class="w-full accent-purple-500 h-1" />
                </div>

                <%!-- Building Speed --%>
                <div class="mb-3">
                  <div class="flex justify-between text-[10px] mb-1">
                    <span class="text-slate-500">🏗️ Building Speed</span>
                    <span class="text-cyan-400 tabular-nums"><%= @rules["building_speed"] %>x</span>
                  </div>
                  <input type="range" name="building_speed" min="0.5" max="3.0" step="0.1" value={@rules["building_speed"]}
                    class="w-full accent-purple-500 h-1" />
                </div>

                <%!-- Mutation Rate --%>
                <div class="mb-3">
                  <div class="flex justify-between text-[10px] mb-1">
                    <span class="text-slate-500">🧬 Mutation Rate</span>
                    <span class="text-cyan-400 tabular-nums"><%= @rules["mutation_rate"] %></span>
                  </div>
                  <input type="range" name="mutation_rate" min="0.0" max="1.0" step="0.1" value={@rules["mutation_rate"]}
                    class="w-full accent-purple-500 h-1" />
                </div>
              </form>

              <div class="text-[9px] text-slate-600 leading-relaxed">
                Rules apply immediately. Changes are saved with the world state.
                <br/>Current: <span class="text-amber-400"><%= @rules["preset"] || "Custom" %></span>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Save/Load Modal — v3.7.0 Persistentia --%>
      <%= if @save_load_open do %>
        <div class="fixed inset-0 modus-modal-overlay z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F]/95 backdrop-blur-xl border border-white/10 rounded-2xl w-[600px] max-h-[480px] flex flex-col shadow-2xl shadow-cyan-500/5" phx-click-away="close_save_load">
            <%!-- Header with auto-save indicator --%>
            <div class="px-5 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <div class="flex items-center gap-3">
                <span class="font-bold text-slate-100">💾 Save / Load World</span>
                <%!-- Auto-save pulsing indicator --%>
                <div class="flex items-center gap-1.5">
                  <div class={"w-2 h-2 rounded-full #{if @autosave_status.enabled, do: "bg-emerald-400 animate-pulse", else: "bg-slate-600"}"} />
                  <span class="text-[9px] text-slate-500">
                    <%= if @autosave_status.last_at do %>
                      Auto-saved <%= @autosave_status.last_at |> String.slice(11, 5) %>
                    <% else %>
                      Auto-save every <%= @autosave_status.interval %> ticks
                    <% end %>
                  </span>
                </div>
              </div>
              <button phx-click="close_save_load" class="text-slate-600 hover:text-slate-400 transition-colors">✕</button>
            </div>

            <div class="p-4 space-y-3 overflow-y-auto flex-1">
              <%!-- Save name input + buttons --%>
              <div class="flex gap-2 items-center">
                <input type="text" name="name" value={@save_name} placeholder="Save name (optional)"
                  phx-change="set_save_name" phx-debounce="300"
                  class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-xs text-slate-200 placeholder-slate-600 focus:outline-none focus:border-cyan-500/50 transition-colors" />
                <button phx-click="do_save" class="ctrl-btn ctrl-btn-primary px-3 text-xs">💾 Save</button>
                <button phx-click="do_export_save" class="ctrl-btn px-3 text-xs text-emerald-400 hover:text-emerald-300">📤 Export</button>
              </div>

              <%!-- Status --%>
              <%= if @save_load_status do %>
                <div class="text-xs px-3 py-1.5 rounded-lg bg-white/5 text-slate-300"><%= @save_load_status %></div>
              <% end %>

              <%!-- 5 Save Slot Cards --%>
              <div class="text-[10px] uppercase tracking-wider text-slate-600 mb-1">Save Slots</div>
              <div class="space-y-2">
                <%= for slot <- @save_slots do %>
                  <div
                    phx-click="select_slot" phx-value-slot={slot.slot}
                    class={"flex items-center gap-3 p-3 rounded-xl border transition-all cursor-pointer " <>
                      if(@selected_slot == slot.slot,
                        do: "bg-cyan-500/10 border-cyan-500/30 shadow-lg shadow-cyan-500/5",
                        else: "bg-white/[0.02] border-white/5 hover:border-white/10 hover:bg-white/[0.04]")}>
                    <%!-- Slot number / thumbnail placeholder --%>
                    <div class={"w-10 h-10 rounded-lg flex items-center justify-center text-sm font-bold shrink-0 " <>
                      if(Map.get(slot, :empty),
                        do: "bg-white/5 text-slate-600",
                        else: "bg-gradient-to-br from-cyan-500/20 to-purple-500/20 text-cyan-400 border border-cyan-500/20")}>
                      <%= slot.slot %>
                    </div>
                    <%!-- Slot info --%>
                    <div class="flex-1 min-w-0">
                      <%= if Map.get(slot, :empty) do %>
                        <div class="text-xs text-slate-600 italic">Empty Slot</div>
                      <% else %>
                        <div class="text-sm font-medium text-slate-200 truncate"><%= slot.name %></div>
                        <div class="text-[10px] text-slate-500 flex items-center gap-2">
                          <span>🌍 <%= slot.world_name %></span>
                          <span>👥 <%= slot.population %></span>
                          <span>📅 Day <%= slot.day_count %></span>
                          <span>⏱️ t<%= slot.tick %></span>
                        </div>
                        <div class="text-[9px] text-slate-600 mt-0.5">
                          🌱 seed: <%= slot.seed || "?" %> · 💾 <%= if slot.size_bytes, do: "#{div(slot.size_bytes, 1024)}KB", else: "?" %>
                          <%= if slot.saved_at do %> · <%= slot.saved_at |> String.slice(0, 16) %><% end %>
                        </div>
                      <% end %>
                    </div>
                    <%!-- Actions --%>
                    <%= unless Map.get(slot, :empty) do %>
                      <div class="flex gap-1 shrink-0">
                        <button phx-click="do_load" phx-value-slot={slot.slot} class="ctrl-btn ctrl-btn-primary text-[10px] px-2.5">▶ Load</button>
                        <button phx-click="do_delete_save" phx-value-slot={slot.slot} class="ctrl-btn text-[10px] px-2 text-red-400/70 hover:text-red-300">🗑️</button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%!-- Import JSON --%>
              <details class="group">
                <summary class="text-[10px] uppercase tracking-wider text-slate-600 cursor-pointer hover:text-slate-400 transition-colors">
                  📥 Import JSON
                </summary>
                <form phx-submit="do_import_save" class="mt-2 flex gap-2">
                  <textarea name="json" placeholder='Paste exported JSON here...' rows="3"
                    class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-[10px] text-slate-300 placeholder-slate-600 focus:outline-none focus:border-cyan-500/50 font-mono resize-none" />
                  <button type="submit" class="ctrl-btn px-3 text-xs text-cyan-400 hover:text-cyan-300 self-end">📥 Import</button>
                </form>
              </details>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Chat & Conversation Panel (v3.4.0 Nexus) --%>
      <%= if @chat_open && @selected_agent do %>
        <div class="fixed top-0 right-0 bottom-0 w-[350px] z-50 flex flex-col
          bg-[#0A0A0F]/80 backdrop-blur-xl border-l border-white/10
          shadow-[-8px_0_32px_rgba(139,92,246,0.08)]"
          phx-click-away="close_chat">

          <%!-- Header --%>
          <div class="px-4 py-3 border-b border-white/[0.06] flex items-center gap-3 shrink-0
            bg-gradient-to-r from-purple-500/[0.04] to-cyan-500/[0.04]">
            <div class="w-9 h-9 rounded-full bg-gradient-to-br from-purple-500/30 to-cyan-500/30 border border-white/10
              flex items-center justify-center text-lg shrink-0">
              <%= chat_mood_emoji(@selected_agent) %>
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-bold text-sm text-slate-100 truncate"><%= @selected_agent["name"] %></div>
              <div class="text-[10px] text-slate-500 flex items-center gap-1.5">
                <span><%= @selected_agent["occupation"] %></span>
                <span class="text-slate-700">·</span>
                <span class="text-emerald-400/70">online</span>
              </div>
            </div>
            <button phx-click="close_chat"
              class="w-7 h-7 rounded-lg bg-white/5 hover:bg-white/10 text-slate-500 hover:text-slate-300
                flex items-center justify-center transition-all text-xs">✕</button>
          </div>

          <%!-- Conversation Type Filter --%>
          <div class="px-3 py-2 border-b border-white/[0.04] flex items-center gap-1.5 shrink-0">
            <%= for {topic, icon, label} <- [{"all", "💬", "All"}, {"trade", "💰", "Trade"}, {"alliance", "🤝", "Alliance"}, {"gossip", "👂", "Gossip"}, {"warning", "⚠️", "Warning"}] do %>
              <button phx-click="chat_filter" phx-value-topic={topic}
                class={"px-2 py-1 rounded-md text-[10px] border transition-all #{if Map.get(assigns, :chat_filter, "all") == topic, do: "border-purple-500/40 bg-purple-500/10 text-purple-300", else: "border-transparent bg-white/[0.03] text-slate-500 hover:bg-white/[0.06]"}"}>
                <span class="mr-0.5"><%= icon %></span><%= label %>
              </button>
            <% end %>
          </div>

          <%!-- Message List --%>
          <div class="flex-1 overflow-y-auto px-3 py-3 space-y-3 scroll-smooth" id="chat-messages">
            <%= if @chat_messages == [] do %>
              <div class="flex flex-col items-center justify-center h-full text-center px-4">
                <div class="text-3xl mb-3 opacity-40"><%= chat_mood_emoji(@selected_agent) %></div>
                <p class="text-xs text-slate-600 italic">Start a conversation with <%= @selected_agent["name"] %>...</p>
                <p class="text-[10px] text-slate-700 mt-1">They seem <%= @selected_agent["affect_state"] || "neutral" %> right now.</p>
              </div>
            <% end %>
            <%= for {msg, idx} <- Enum.with_index(@chat_messages) do %>
              <div class={"flex #{if msg.role == "user", do: "justify-end", else: "justify-start"}"}>
                <%!-- Agent avatar (left side) --%>
                <%= if msg.role in ["agent", "system"] do %>
                  <div class={"w-7 h-7 rounded-full border flex items-center justify-center text-xs shrink-0 mr-2 mt-1 #{cond do
                    msg[:topic] == "insight" -> "bg-gradient-to-br from-cyan-500/30 to-blue-500/30 border-cyan-500/20"
                    msg[:topic] == "action" -> "bg-gradient-to-br from-amber-500/30 to-orange-500/30 border-amber-500/20"
                    true -> "bg-gradient-to-br from-cyan-500/20 to-purple-500/20 border-white/10"
                  end}"}>
                    <%= cond do %>
                      <% msg[:topic] == "insight" -> %>🔍
                      <% msg[:topic] == "action" -> %>⚡
                      <% true -> %><%= chat_mood_emoji(@selected_agent) %>
                    <% end %>
                  </div>
                <% end %>
                <div class={"max-w-[78%] group"}>
                  <%!-- Topic icon + name --%>
                  <%= if msg.role in ["agent", "system"] do %>
                    <div class="flex items-center gap-1 mb-0.5 px-1">
                      <%= if msg[:topic] do %>
                        <span class="text-[10px]"><%= topic_icon(msg[:topic]) %></span>
                      <% end %>
                      <span class={"text-[10px] font-medium #{cond do
                        msg[:topic] == "insight" -> "text-cyan-400/80"
                        msg[:topic] == "action" -> "text-amber-400/80"
                        true -> "text-cyan-400/80"
                      end}"}><%= cond do %>
                        <% msg[:topic] == "insight" -> %>Nexus Insight
                        <% msg[:topic] == "action" -> %>Nexus Action
                        <% true -> %><%= msg[:name] || @selected_agent["name"] %>
                      <% end %></span>
                      <span class="text-[9px] text-slate-700 ml-auto opacity-0 group-hover:opacity-100 transition-opacity">
                        <%= chat_timestamp(idx) %>
                      </span>
                    </div>
                  <% end %>
                  <%!-- Message bubble --%>
                  <div class={"px-3 py-2 rounded-2xl text-[13px] leading-relaxed
                    #{cond do
                      msg.role == "user" -> "bg-gradient-to-br from-purple-500/20 to-purple-600/10 text-purple-100 border border-purple-500/10 rounded-br-md"
                      msg[:topic] == "insight" -> "bg-gradient-to-br from-cyan-500/15 to-blue-500/10 text-cyan-100 border border-cyan-500/20 rounded-bl-md backdrop-blur-sm"
                      msg[:topic] == "action" -> "bg-gradient-to-br from-amber-500/15 to-orange-500/10 text-amber-100 border border-amber-500/20 rounded-bl-md backdrop-blur-sm"
                      true -> "bg-white/[0.04] text-slate-300 border border-white/[0.06] rounded-bl-md backdrop-blur-sm"
                    end}"}>
                    <%= msg.text %>
                  </div>
                  <%= if msg.role == "user" do %>
                    <div class="flex justify-end mt-0.5 px-1">
                      <span class="text-[9px] text-slate-700 opacity-0 group-hover:opacity-100 transition-opacity">
                        <%= chat_timestamp(idx) %>
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
            <%= if @chat_loading do %>
              <div class="flex justify-start">
                <div class="w-7 h-7 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-xs shrink-0 mr-2">
                  <%= chat_mood_emoji(@selected_agent) %>
                </div>
                <div class="bg-white/[0.04] border border-white/[0.06] px-4 py-2.5 rounded-2xl rounded-bl-md">
                  <div class="flex gap-1">
                    <div class="w-1.5 h-1.5 rounded-full bg-slate-500 animate-bounce" style="animation-delay: 0ms"></div>
                    <div class="w-1.5 h-1.5 rounded-full bg-slate-500 animate-bounce" style="animation-delay: 150ms"></div>
                    <div class="w-1.5 h-1.5 rounded-full bg-slate-500 animate-bounce" style="animation-delay: 300ms"></div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Input Area --%>
          <form phx-submit="send_chat" id="chat-form"
            class="px-3 py-3 border-t border-white/[0.06] shrink-0
              bg-gradient-to-t from-[#0A0A0F] to-transparent">
            <div class="flex gap-2 items-end">
              <div class="flex-1 relative">
                <input type="text" name="message" id="chat-input"
                  placeholder={"Talk to #{@selected_agent["name"]}..."}
                  autocomplete="off"
                  class="w-full bg-white/[0.04] border border-white/[0.08] rounded-xl px-3.5 py-2.5 text-[13px]
                    text-slate-200 placeholder-slate-600
                    focus:outline-none focus:border-purple-500/30 focus:bg-white/[0.06]
                    transition-all" />
              </div>
              <button type="submit"
                class="w-9 h-9 rounded-xl bg-gradient-to-br from-purple-500 to-cyan-500
                  text-white flex items-center justify-center shrink-0
                  hover:from-purple-400 hover:to-cyan-400 transition-all
                  shadow-lg shadow-purple-500/20 hover:shadow-purple-500/30
                  active:scale-95">
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"/>
                </svg>
              </button>
            </div>
          </form>
        </div>
      <% end %>
    </div>

      <%!-- LLM Metrics Panel (toggle with M key / ⚡ button) --%>
      <%= if @llm_metrics_open do %>
        <div class="fixed bottom-4 right-4 z-40 w-[300px] rounded-xl border border-cyan-500/20 bg-[#0A0A0F]/95 backdrop-blur-md shadow-lg shadow-cyan-500/5 p-3 font-mono">
          <div class="flex items-center justify-between mb-2">
            <span class="text-[10px] uppercase tracking-wider text-cyan-400 font-bold">⚡ LLM Metrics</span>
            <button phx-click="toggle_llm_metrics" class="text-slate-600 hover:text-slate-400 text-xs">✕</button>
          </div>

          <%!-- Active Model --%>
          <div class="flex items-center gap-2 mb-2">
            <span class="w-1.5 h-1.5 rounded-full bg-cyan-400 animate-pulse"></span>
            <span class="text-[11px] text-slate-300 truncate"><%= @llm_metrics.active_model %></span>
          </div>

          <%!-- Stats Grid --%>
          <div class="grid grid-cols-3 gap-2 mb-2">
            <div class="text-center">
              <div class="text-lg font-bold text-cyan-400 tabular-nums"><%= @llm_metrics.calls_this_tick %></div>
              <div class="text-[8px] uppercase text-slate-600">calls/tick</div>
            </div>
            <div class="text-center">
              <div class="text-lg font-bold text-emerald-400 tabular-nums"><%= @llm_metrics.cache_hit_rate %>%</div>
              <div class="text-[8px] uppercase text-slate-600">cache hits</div>
            </div>
            <div class="text-center">
              <% latency = if is_number(@llm_metrics.avg_latency_ms), do: round(@llm_metrics.avg_latency_ms), else: 0 %>
              <div class={"text-lg font-bold tabular-nums #{if latency < 500, do: "text-emerald-400", else: if(latency < 2000, do: "text-amber-400", else: "text-red-400")}"}><%= latency %>ms</div>
              <div class="text-[8px] uppercase text-slate-600">latency</div>
            </div>
          </div>

          <%!-- Sparkline (SVG) --%>
          <div class="h-8 w-full">
            <svg viewBox="0 0 300 32" class="w-full h-full" preserveAspectRatio="none">
              <%= if @llm_metrics.sparkline != [] do %>
                <% max_val = max(Enum.max(@llm_metrics.sparkline), 1) %>
                <% points = @llm_metrics.sparkline |> Enum.with_index() |> Enum.map(fn {v, i} ->
                  x = i / max(length(@llm_metrics.sparkline) - 1, 1) * 300
                  y = 30 - (v / max_val * 28)
                  "#{x},#{y}"
                end) |> Enum.join(" ") %>
                <polyline points={points} fill="none" stroke="#06B6D4" stroke-width="1.5" stroke-linejoin="round" />
              <% else %>
                <line x1="0" y1="30" x2="300" y2="30" stroke="#1e293b" stroke-width="0.5" />
              <% end %>
            </svg>
          </div>
          <div class="text-[8px] text-slate-600 text-right">calls/tick (last 50)</div>

          <%!-- Total --%>
          <div class="mt-1 text-[9px] text-slate-600 flex justify-between">
            <span>total: <%= @llm_metrics.total_calls %> calls</span>
            <span>budget: <%= try do Modus.Intelligence.BudgetTracker.get_remaining() rescue _ -> "?" end %>/<%= try do Modus.Intelligence.BudgetTracker.max_per_tick() rescue _ -> "?" end %></span>
          </div>
        </div>
      <% end %>

      <%!-- Performance Monitor Panel (toggle with P key) --%>
      <%= if @perf_monitor_open do %>
        <% pm = @perf_metrics %>
        <% health_color = case pm.health do
          :healthy -> "text-emerald-400"
          :warning -> "text-amber-400"
          :critical -> "text-red-400"
        end %>
        <% health_border = case pm.health do
          :healthy -> "border-emerald-500/20"
          :warning -> "border-amber-500/20"
          :critical -> "border-red-500/20"
        end %>
        <% mem_pct = min(pm.memory_total_mb / 512.0 * 100, 100) %>
        <% mem_bar_color = cond do
          mem_pct > 80 -> "bg-red-500"
          mem_pct > 50 -> "bg-amber-500"
          true -> "bg-emerald-500"
        end %>
        <div class={"fixed top-16 right-4 z-40 w-[250px] rounded-xl border #{health_border} bg-[#0A0A0F]/95 backdrop-blur-md shadow-lg p-3 font-mono"}>
          <div class="flex items-center justify-between mb-2">
            <span class={"text-[10px] uppercase tracking-wider font-bold #{health_color}"}>📊 Performance</span>
            <div class="flex items-center gap-2">
              <span class={"w-1.5 h-1.5 rounded-full #{String.replace(health_color, "text-", "bg-")} #{if pm.health != :healthy, do: "animate-pulse", else: ""}"} />
              <button phx-click="toggle_perf_monitor" class="text-slate-600 hover:text-slate-400 text-xs">✕</button>
            </div>
          </div>

          <%!-- Agent Count & Tick --%>
          <div class="grid grid-cols-2 gap-2 mb-2">
            <div>
              <div class="text-xl font-bold text-purple-400 tabular-nums"><%= pm.agent_count %></div>
              <div class="text-[8px] uppercase text-slate-600">agents</div>
            </div>
            <div>
              <div class="text-xl font-bold text-cyan-400 tabular-nums"><%= pm.tick %></div>
              <div class="text-[8px] uppercase text-slate-600">tick</div>
            </div>
          </div>

          <%!-- Memory Bar --%>
          <div class="mb-2">
            <div class="flex justify-between text-[9px] mb-0.5">
              <span class="text-slate-500">Memory</span>
              <span class={health_color}><%= pm.memory_total_mb %> MB</span>
            </div>
            <div class="h-1.5 bg-white/5 rounded-full overflow-hidden">
              <div class={"h-full rounded-full transition-all #{mem_bar_color}"} style={"width: #{mem_pct}%"} />
            </div>
            <div class="flex justify-between text-[8px] text-slate-600 mt-0.5">
              <span>proc: <%= pm.memory_processes_mb %>MB</span>
              <span>ets: <%= pm.memory_ets_mb %>MB</span>
            </div>
          </div>

          <%!-- CPU --%>
          <div class="flex items-center justify-between text-[10px]">
            <span class="text-slate-500">CPU</span>
            <span class={"font-bold tabular-nums #{cond do
              pm.cpu_percent > 80 -> "text-red-400"
              pm.cpu_percent > 50 -> "text-amber-400"
              true -> "text-emerald-400"
            end}"}><%= pm.cpu_percent %>%</span>
          </div>

          <%!-- Health Status --%>
          <div class={"mt-2 text-center text-[9px] uppercase tracking-wider #{health_color}"}>
            <%= case pm.health do
              :healthy -> "✅ All Systems Healthy"
              :warning -> "⚠️ Warning — High Load"
              :critical -> "🔴 Critical — Reduce Agents"
            end %>
          </div>
        </div>
      <% end %>

      <%!-- Event Timeline Sidebar (Eventus v3.5.0) --%>
      <%= if @event_timeline_open do %>
        <div class="fixed top-14 right-0 bottom-0 w-72 z-40 bg-[#0A0A0F]/95 backdrop-blur-md border-l border-white/10 overflow-hidden flex flex-col animate-slide-in">
          <div class="px-3 py-2 border-b border-white/5 flex items-center justify-between shrink-0">
            <span class="text-[10px] uppercase tracking-wider text-slate-500 font-bold">🔔 Event Timeline</span>
            <button phx-click="toggle_event_timeline" class="text-slate-600 hover:text-slate-400 text-xs">✕</button>
          </div>
          <div class="flex-1 overflow-y-auto px-3 py-2 space-y-1.5">
            <%= if @event_timeline == [] do %>
              <p class="text-xs text-slate-600 italic text-center py-8">No events yet. Let the world run...</p>
            <% else %>
              <% grouped = Enum.group_by(@event_timeline, fn e -> div(e.tick, 100) end) %>
              <%= for {day_group, entries} <- Enum.sort_by(grouped, &elem(&1, 0), :desc) do %>
                <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-2 mb-1 flex items-center gap-2">
                  <span class="flex-1 h-px bg-white/5"></span>
                  <span>Day <%= day_group + 1 %></span>
                  <span class="flex-1 h-px bg-white/5"></span>
                </div>
                <%= for entry <- entries do %>
                  <% card_color = case entry.category do
                    "disaster" -> "border-l-red-500 bg-red-500/5"
                    "celebration" -> "border-l-amber-500 bg-amber-500/5"
                    "discovery" -> "border-l-cyan-500 bg-cyan-500/5"
                    "migration" -> "border-l-emerald-500 bg-emerald-500/5"
                    _ -> "border-l-purple-500 bg-purple-500/5"
                  end %>
                  <% severity_dots = case entry.severity do
                    3 -> "🔴🔴🔴"
                    2 -> "🟡🟡"
                    _ -> "🟢"
                  end %>
                  <div class={"border-l-2 rounded-r-lg p-2 #{card_color}"}>
                    <div class="flex items-center gap-1.5">
                      <span class="text-sm"><%= entry.emoji %></span>
                      <span class="text-[10px] text-slate-300 flex-1 truncate"><%= entry.text %></span>
                    </div>
                    <div class="flex items-center gap-2 mt-1">
                      <span class="text-[8px] text-slate-600">t:<%= entry.tick %></span>
                      <span class="text-[8px]"><%= severity_dots %></span>
                      <%= if entry.chain_source do %>
                        <span class="text-[8px] text-purple-400/60">⛓ <%= entry.chain_source %></span>
                      <% end %>
                      <%= if entry.artifact do %>
                        <span class="text-[8px] text-cyan-400">
                          <%= (entry.artifact[:emoji] || entry.artifact["emoji"] || "🗺️") %>
                          <%= (entry.artifact[:name] || entry.artifact["name"] || "") %>
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Breaking Event Banner (Eventus v3.5.0) --%>
      <%= if @breaking_event do %>
        <% banner_color = case @breaking_event.category do
          "disaster" -> "from-red-900/90 to-red-800/80 border-red-500/50"
          "celebration" -> "from-amber-900/90 to-yellow-800/80 border-amber-500/50"
          "discovery" -> "from-cyan-900/90 to-teal-800/80 border-cyan-500/50"
          "migration" -> "from-emerald-900/90 to-green-800/80 border-emerald-500/50"
          _ -> "from-purple-900/90 to-indigo-800/80 border-purple-500/50"
        end %>
        <% text_color = case @breaking_event.category do
          "disaster" -> "text-red-200"
          "celebration" -> "text-amber-200"
          "discovery" -> "text-cyan-200"
          "migration" -> "text-emerald-200"
          _ -> "text-purple-200"
        end %>
        <div class={"fixed top-14 inset-x-0 z-50 animate-banner-slide"}>
          <div class={"flex items-center justify-center gap-3 px-6 py-3 bg-gradient-to-r #{banner_color} border-b backdrop-blur-md"}>
            <span class="text-2xl animate-pulse"><%= @breaking_event.emoji %></span>
            <div class="flex flex-col">
              <span class={"text-sm font-bold uppercase tracking-wider #{text_color}"}>
                ⚡ Breaking Event
              </span>
              <span class={"text-xs #{text_color} opacity-80"}><%= @breaking_event.text %></span>
            </div>
            <%= if @breaking_event.chain_source do %>
              <span class="text-[9px] text-white/40 ml-2">chain: <%= @breaking_event.chain_source %></span>
            <% end %>
            <button phx-click="dismiss_breaking" class="ml-4 text-white/40 hover:text-white/80 text-sm">✕</button>
          </div>
        </div>
      <% end %>

      <%!-- Toast Notifications (color-coded by category) --%>
      <%= if @toasts != [] do %>
        <div class={"fixed top-#{if @breaking_event, do: "28", else: "16"} left-1/2 -translate-x-1/2 z-50 space-y-2 pointer-events-none flex flex-col items-center"}>
          <%= for toast <- @toasts do %>
            <% toast_category = Enum.find(@event_timeline, fn e -> e.id == toast.id end) %>
            <% toast_border = case toast_category && toast_category.category do
              "disaster" -> "border-red-500/40 shadow-red-500/10"
              "celebration" -> "border-amber-500/40 shadow-amber-500/10"
              "discovery" -> "border-cyan-500/40 shadow-cyan-500/10"
              "migration" -> "border-emerald-500/40 shadow-emerald-500/10"
              _ -> "border-purple-500/30 shadow-purple-500/10"
            end %>
            <div class={"pointer-events-auto flex items-center gap-2 px-4 py-2 rounded-lg bg-[#0A0A0F]/95 border shadow-lg backdrop-blur-md animate-toast-pop max-w-sm #{toast_border}"}>
              <span class="text-lg"><%= toast.emoji %></span>
              <div class="flex-1 min-w-0">
                <p class="text-xs text-slate-200"><%= toast.text %></p>
                <span class="text-[9px] text-slate-600">tick <%= toast.tick %></span>
              </div>
              <button phx-click="dismiss_toast" phx-value-id={toast.id} class="text-slate-600 hover:text-slate-400 text-xs ml-1">✕</button>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- World History Modal --%>
      <%= if @history_open do %>
        <div class="fixed inset-0 modus-modal-overlay z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-3xl max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_history">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <span class="font-bold text-slate-100">📖 World History</span>
              <div class="flex items-center gap-2">
                <button phx-click="export_world_chronicle" class="text-[10px] px-2 py-1 bg-purple-500/20 text-purple-300 rounded hover:bg-purple-500/30 border border-purple-500/20">
                  📜 Export Chronicle
                </button>
                <button phx-click="close_history" class="text-slate-600 hover:text-slate-400">✕</button>
              </div>
            </div>
            <div class="flex flex-1 overflow-hidden">
              <%!-- Era Timeline (left) --%>
              <div class="w-1/3 border-r border-white/5 overflow-y-auto p-3 space-y-2">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Eras</h3>
                <%= if @history_eras == [] do %>
                  <p class="text-xs text-slate-600 italic">No eras detected yet...</p>
                <% else %>
                  <%= for era <- @history_eras do %>
                    <button
                      phx-click="select_history_era"
                      phx-value-era-id={era.id}
                      class={"w-full text-left p-2 rounded-lg border transition-all cursor-pointer " <>
                        if(@history_selected_era == era.id,
                          do: "bg-purple-500/20 border-purple-500/40",
                          else: "bg-white/3 border-white/5 hover:bg-white/5")}
                    >
                      <div class="flex items-center gap-1.5">
                        <span class="text-lg"><%= era.emoji %></span>
                        <span class="text-xs font-medium text-slate-200"><%= era.name %></span>
                      </div>
                      <div class="text-[9px] text-slate-500 mt-1">
                        t:<%= era.start_tick %><%= if era.end_tick, do: " → #{era.end_tick}", else: " → now" %>
                      </div>
                      <%= if era.end_tick == nil do %>
                        <span class="inline-block mt-1 text-[8px] px-1.5 py-0.5 bg-green-500/20 text-green-400 rounded-full">current</span>
                      <% end %>
                    </button>
                  <% end %>
                <% end %>

                <%!-- Key Figures --%>
                <%= if @history_figures != [] do %>
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mt-4 mb-2">Key Figures</h3>
                  <%= for fig <- Enum.take(@history_figures, 8) do %>
                    <div class="p-2 bg-white/3 rounded-lg border border-white/5">
                      <div class="text-xs font-medium text-cyan-300"><%= fig.name %></div>
                      <div class="text-[9px] text-slate-500 mt-0.5">
                        <%= List.first(fig.achievements) || "Notable figure" %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <%!-- Era Detail (right) --%>
              <div class="flex-1 overflow-y-auto p-4">
                <%= if @history_selected_era do %>
                  <% selected = Enum.find(@history_eras, fn e -> e.id == @history_selected_era end) %>
                  <%= if selected do %>
                    <div class="mb-4">
                      <h2 class="text-lg font-bold text-slate-100"><%= selected.emoji %> <%= selected.name %></h2>
                      <p class="text-xs text-slate-400 mt-1 italic"><%= selected.description %></p>
                      <div class="text-[9px] text-slate-600 mt-1">
                        Duration: <%= if selected.end_tick, do: "#{selected.end_tick - selected.start_tick} ticks", else: "ongoing" %>
                      </div>
                    </div>

                    <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Events</h3>
                    <%= if @history_era_events == [] do %>
                      <p class="text-xs text-slate-600 italic">No events recorded for this era.</p>
                    <% else %>
                      <div class="space-y-1.5">
                        <%= for event <- @history_era_events do %>
                          <div class="border-l-2 border-purple-500/30 pl-2 py-0.5">
                            <div class="flex items-center gap-1.5">
                              <span class="text-sm"><%= event.emoji %></span>
                              <span class="text-[9px] text-slate-600 tabular-nums">t:<%= event.tick %></span>
                            </div>
                            <p class="text-[11px] text-slate-300 mt-0.5"><%= event.summary %></p>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                <% else %>
                  <div class="flex items-center justify-center h-full">
                    <p class="text-xs text-slate-600 italic">← Select an era to view its history</p>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Chronicle Export Modal --%>
      <%= if @chronicle_open do %>
        <div class="fixed inset-0 modus-modal-overlay z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-2xl max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_chronicle">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <span class="font-bold text-slate-100">📖 World Chronicle</span>
              <button phx-click="close_chronicle" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>
            <div class="p-4 overflow-y-auto flex-1">
              <pre class="text-xs text-slate-300 whitespace-pre-wrap font-mono leading-relaxed"><%= @chronicle_md %></pre>
            </div>
            <div class="px-4 py-3 border-t border-white/5 shrink-0 flex gap-2">
              <button phx-click="download_chronicle" class="text-[10px] px-3 py-1.5 bg-purple-500/20 text-purple-300 rounded hover:bg-purple-500/30 border border-purple-500/20">⬇ Download .md</button>
              <p class="text-[10px] text-slate-600 self-center">Or copy the text above.</p>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Export & Share Modal --%>
      <%= if @export_open do %>
        <div class="fixed inset-0 modus-modal-overlay z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-lg max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_export">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <div class="flex items-center gap-2">
                <span class="font-bold text-slate-100">📤 Export & Share</span>
                <span class="text-[9px] text-slate-600">v5.0.0 Forma</span>
              </div>
              <button phx-click="close_export" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>

            <%!-- Tabs --%>
            <div class="px-4 pt-2 flex gap-1 border-b border-white/5 shrink-0">
              <%= for {tab, label, icon} <- [{:export, "Export", "⬇"}, {:import, "Import", "⬆"}, {:share, "Share", "🔗"}] do %>
                <button
                  phx-click="export_tab"
                  phx-value-tab={tab}
                  class={"px-3 py-1.5 text-[10px] uppercase tracking-wider border-b-2 transition-all #{if @export_tab == tab, do: "border-purple-500 text-purple-300", else: "border-transparent text-slate-600 hover:text-slate-400"}"}
                >
                  <%= icon %> <%= label %>
                </button>
              <% end %>
            </div>

            <div class="p-4 overflow-y-auto flex-1">
              <%= case @export_tab do %>
                <% :export -> %>
                  <p class="text-xs text-slate-400 mb-4">Export your world as a portable JSON file. Includes terrain, agents, buildings, rules, and history.</p>
                  <button phx-click="do_export_json" class="w-full py-3 bg-purple-500/20 text-purple-300 rounded-lg hover:bg-purple-500/30 border border-purple-500/20 text-sm font-bold transition-all">
                    ⬇ Download World JSON
                  </button>
                  <%= if @export_status do %>
                    <p class="text-xs text-center mt-3 text-slate-400"><%= @export_status %></p>
                  <% end %>

                <% :import -> %>
                  <p class="text-xs text-slate-400 mb-4">Import a world from a JSON file or share code.</p>

                  <%!-- File upload via JS --%>
                  <div class="mb-4">
                    <label class="block text-[10px] text-slate-600 uppercase tracking-wider mb-2">From JSON File</label>
                    <div id="import-dropzone" phx-hook="ImportFile" class="border-2 border-dashed border-white/10 rounded-lg p-6 text-center hover:border-purple-500/30 transition-colors cursor-pointer">
                      <p class="text-xs text-slate-500">Click or drag & drop a .json file</p>
                      <input type="file" accept=".json" class="hidden" id="import-file-input" />
                    </div>
                  </div>

                  <%!-- Share code import --%>
                  <div class="mb-4">
                    <label class="block text-[10px] text-slate-600 uppercase tracking-wider mb-2">From Share Code</label>
                    <form phx-submit="do_import_share">
                      <textarea name="share_code" rows="3" placeholder="Paste share code here..." class="w-full bg-white/5 border border-white/10 rounded-lg p-2 text-xs text-slate-300 font-mono resize-none focus:border-purple-500/30 focus:outline-none"></textarea>
                      <button type="submit" class="mt-2 w-full py-2 bg-cyan-500/20 text-cyan-300 rounded-lg hover:bg-cyan-500/30 border border-cyan-500/20 text-xs font-bold transition-all">
                        ⬆ Import from Share Code
                      </button>
                    </form>
                  </div>

                  <%= if @import_status do %>
                    <p class="text-xs text-center mt-2 text-slate-400"><%= @import_status %></p>
                  <% end %>

                <% :share -> %>
                  <p class="text-xs text-slate-400 mb-4">Generate a share code that anyone can use to import your world. No file needed!</p>
                  <button phx-click="do_export_share" class="w-full py-3 bg-cyan-500/20 text-cyan-300 rounded-lg hover:bg-cyan-500/30 border border-cyan-500/20 text-sm font-bold transition-all">
                    🔗 Generate Share Code
                  </button>
                  <%= if @export_base64 != "" do %>
                    <div class="mt-4">
                      <label class="block text-[10px] text-slate-600 uppercase tracking-wider mb-2">Share Code</label>
                      <textarea id="share-code-output" readonly rows="4" class="w-full bg-white/5 border border-white/10 rounded-lg p-2 text-[10px] text-slate-300 font-mono resize-none select-all"><%= @export_base64 %></textarea>
                      <button id="copy-share-code" phx-hook="CopyToClipboard" data-target="share-code-output" class="mt-2 w-full py-2 bg-emerald-500/20 text-emerald-300 rounded-lg hover:bg-emerald-500/30 border border-emerald-500/20 text-xs font-bold transition-all">
                        📋 Copy to Clipboard
                      </button>
                    </div>
                  <% end %>
                  <%= if @export_status do %>
                    <p class="text-xs text-center mt-3 text-slate-400"><%= @export_status %></p>
                  <% end %>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Stats Modal --%>
      <%= if @stats_open do %>
        <div class="fixed inset-0 modus-modal-overlay z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-3xl max-h-[85vh] flex flex-col shadow-2xl" phx-click-away="close_stats">
            <%!-- Header --%>
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <div class="flex items-center gap-3">
                <span class="font-bold text-slate-100">📊 Observatory</span>
                <span class="text-[9px] text-slate-600">v5.0.0 Forma</span>
              </div>
              <div class="flex items-center gap-2">
                <button phx-click="obs_refresh" class="text-[10px] px-2 py-1 rounded bg-white/5 border border-white/10 text-slate-500 hover:text-slate-300 hover:border-white/20 transition-all">↻ Refresh</button>
                <button phx-click="close_stats" class="text-slate-600 hover:text-slate-400">✕</button>
              </div>
            </div>

            <%!-- Tabs --%>
            <div class="px-4 pt-2 flex gap-1 border-b border-white/5 shrink-0">
              <%= for {tab, label} <- [{:overview, "Overview"}, {:leaderboard, "Leaderboard"}, {:network, "Network"}] do %>
                <button
                  phx-click="obs_tab"
                  phx-value-tab={tab}
                  class={"px-3 py-1.5 text-[10px] uppercase tracking-wider border-b-2 transition-all #{if @obs_tab == tab, do: "border-purple-500 text-purple-300", else: "border-transparent text-slate-600 hover:text-slate-400"}"}
                >
                  <%= label %>
                </button>
              <% end %>
            </div>

            <%!-- Content --%>
            <div class="p-4 overflow-y-auto flex-1">
              <%= case @obs_tab do %>
                <% :overview -> %>
                  <%!-- World Stats Summary --%>
                  <div class="grid grid-cols-4 gap-2 mb-4">
                    <div class="bg-white/3 rounded-lg p-2.5 border border-white/5 text-center">
                      <div class="text-xl font-bold text-purple-400"><%= @obs_world.population %></div>
                      <div class="text-[9px] text-slate-600 uppercase">Population</div>
                    </div>
                    <div class="bg-white/3 rounded-lg p-2.5 border border-white/5 text-center">
                      <div class="text-xl font-bold text-amber-400"><%= @obs_world.buildings %></div>
                      <div class="text-[9px] text-slate-600 uppercase">Buildings</div>
                    </div>
                    <div class="bg-white/3 rounded-lg p-2.5 border border-white/5 text-center">
                      <div class="text-xl font-bold text-cyan-400"><%= Float.round(@obs_world.avg_happiness * 100, 0) %>%</div>
                      <div class="text-[9px] text-slate-600 uppercase">Happiness</div>
                    </div>
                    <div class="bg-white/3 rounded-lg p-2.5 border border-white/5 text-center">
                      <div class="text-xl font-bold text-emerald-400"><%= Float.round(@obs_world.avg_conatus * 100, 0) %>%</div>
                      <div class="text-[9px] text-slate-600 uppercase">Conatus</div>
                    </div>
                  </div>

                  <div class="grid grid-cols-3 gap-2 mb-4">
                    <div class="bg-white/3 rounded-lg p-2 border border-white/5 text-center">
                      <div class="text-lg font-bold text-green-400">🤝 <%= @obs_world.trades %></div>
                      <div class="text-[9px] text-slate-600">Trades</div>
                    </div>
                    <div class="bg-white/3 rounded-lg p-2 border border-white/5 text-center">
                      <div class="text-lg font-bold text-cyan-400">👶 <%= @obs_world.births %></div>
                      <div class="text-[9px] text-slate-600">Births</div>
                    </div>
                    <div class="bg-white/3 rounded-lg p-2 border border-white/5 text-center">
                      <div class="text-lg font-bold text-red-400">💀 <%= @obs_world.deaths %></div>
                      <div class="text-[9px] text-slate-600">Deaths</div>
                    </div>
                  </div>

                  <%!-- Population Line Chart (CSS bars) --%>
                  <%= if @population_history != [] do %>
                    <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">📈 Population Over Time</h3>
                    <div class="bg-white/3 rounded-lg p-3 border border-white/5 mb-4">
                      <% max_pop = @population_history |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) %>
                      <% sampled = @population_history |> Enum.take_every(max(div(length(@population_history), 50), 1)) |> Enum.take(50) %>
                      <div class="flex items-end gap-px h-24">
                        <%= for {_tick, pop} <- sampled do %>
                          <% height = if max_pop > 0, do: pop / max_pop * 100, else: 0 %>
                          <div
                            class="flex-1 bg-purple-500/60 rounded-t-sm min-w-[2px] hover:bg-purple-400/80 transition-colors"
                            style={"height: #{height}%"}
                            title={"Pop: #{pop}"}
                          />
                        <% end %>
                      </div>
                      <div class="flex justify-between text-[9px] text-slate-600 mt-1">
                        <span>t:<%= elem(List.first(@population_history), 0) %></span>
                        <span>t:<%= elem(List.last(@population_history), 0) %></span>
                      </div>
                    </div>

                    <%!-- Happiness Index Chart --%>
                    <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">😊 Happiness Index</h3>
                    <div class="bg-white/3 rounded-lg p-3 border border-white/5 mb-4">
                      <% h_sampled = @obs_happiness |> Enum.take_every(max(div(length(@obs_happiness), 50), 1)) |> Enum.take(50) %>
                      <div class="flex items-end gap-px h-16">
                        <%= for {_tick, h} <- h_sampled do %>
                          <% hcolor = cond do
                            h >= 0.7 -> "bg-emerald-500/60 hover:bg-emerald-400/80"
                            h >= 0.4 -> "bg-amber-500/60 hover:bg-amber-400/80"
                            true -> "bg-red-500/60 hover:bg-red-400/80"
                          end %>
                          <div
                            class={"flex-1 rounded-t-sm min-w-[2px] transition-colors #{hcolor}"}
                            style={"height: #{h * 100}%"}
                            title={"Happiness: #{Float.round(h * 100, 0)}%"}
                          />
                        <% end %>
                      </div>
                    </div>

                    <%!-- Trade Volume Chart --%>
                    <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">🤝 Trade Volume</h3>
                    <div class="bg-white/3 rounded-lg p-3 border border-white/5 mb-4">
                      <% t_sampled = @obs_trades |> Enum.take_every(max(div(length(@obs_trades), 50), 1)) |> Enum.take(50) %>
                      <% max_trade = t_sampled |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) %>
                      <div class="flex items-end gap-px h-16">
                        <%= for {_tick, t} <- t_sampled do %>
                          <% height = if max_trade > 0, do: t / max_trade * 100, else: 0 %>
                          <div
                            class="flex-1 bg-cyan-500/60 rounded-t-sm min-w-[2px] hover:bg-cyan-400/80 transition-colors"
                            style={"height: #{height}%"}
                            title={"Trades: #{t}"}
                          />
                        <% end %>
                      </div>
                    </div>
                  <% else %>
                    <p class="text-xs text-slate-600 italic text-center py-8">No data yet. Run the simulation for a while...</p>
                  <% end %>

                  <%!-- Building Breakdown --%>
                  <%= if @obs_buildings != [] do %>
                    <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">🏗️ Buildings</h3>
                    <div class="bg-white/3 rounded-lg p-3 border border-white/5">
                      <% max_b = @obs_buildings |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) %>
                      <%= for {type, count} <- @obs_buildings do %>
                        <div class="flex items-center gap-2 mb-1.5">
                          <span class="text-[10px] text-slate-400 w-20 text-right"><%= type %></span>
                          <div class="flex-1 bg-white/5 rounded h-4 overflow-hidden">
                            <div
                              class="h-full bg-amber-500/50 rounded transition-all"
                              style={"width: #{count / max_b * 100}%"}
                            />
                          </div>
                          <span class="text-[10px] text-amber-400 w-6 text-right font-bold"><%= count %></span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                <% :leaderboard -> %>
                  <%!-- Agent Leaderboards --%>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <%= for {category, entries} <- [
                      {"🤝 Most Social", @obs_leaderboards.most_social},
                      {"💰 Wealthiest", @obs_leaderboards.wealthiest},
                      {"😊 Happiest", @obs_leaderboards.happiest},
                      {"🧓 Oldest", @obs_leaderboards.oldest}
                    ] do %>
                      <div class="bg-white/3 rounded-lg border border-white/5 overflow-hidden">
                        <div class="px-3 py-2 border-b border-white/5 text-[10px] uppercase tracking-wider text-slate-500 font-bold">
                          <%= category %>
                        </div>
                        <div class="p-2">
                          <%= if entries == [] do %>
                            <p class="text-[10px] text-slate-600 italic px-2 py-3 text-center">No data yet</p>
                          <% else %>
                            <%= for {entry, rank} <- Enum.with_index(entries, 1) do %>
                              <div class={"flex items-center gap-2 px-2 py-1.5 rounded #{if rank == 1, do: "bg-white/5"}"}>
                                <span class={"text-xs font-bold w-5 text-right #{if rank == 1, do: "text-amber-400", else: "text-slate-600"}"}>#<%= rank %></span>
                                <span class="text-xs text-slate-200 flex-1 truncate"><%= entry.name %></span>
                                <span class="text-[10px] text-slate-500"><%= entry.label %></span>
                              </div>
                            <% end %>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>

                <% :network -> %>
                  <%!-- Relationship Network SVG --%>
                  <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-3">🔗 Relationship Network</h3>
                  <%= if @obs_net_nodes == [] do %>
                    <div class="bg-white/3 rounded-lg border border-white/5 p-8 text-center">
                      <p class="text-xs text-slate-600 italic">No relationships formed yet. Agents need to interact...</p>
                    </div>
                  <% else %>
                    <div class="bg-white/3 rounded-lg border border-white/5 p-3 overflow-hidden">
                      <svg viewBox="0 0 500 400" class="w-full" style="max-height: 400px;">
                        <%!-- Generate node positions in a circle layout --%>
                        <% node_count = length(@obs_net_nodes) %>
                        <% node_positions = @obs_net_nodes |> Enum.with_index() |> Enum.map(fn {node, i} ->
                          angle = i / max(node_count, 1) * 2 * :math.pi()
                          cx = 250 + :math.cos(angle) * min(150, 50 + node_count * 8)
                          cy = 200 + :math.sin(angle) * min(140, 50 + node_count * 8)
                          {node.id, cx, cy, node.name}
                        end) %>
                        <% pos_map = Map.new(node_positions, fn {id, cx, cy, _} -> {id, {cx, cy}} end) %>

                        <%!-- Edges --%>
                        <%= for edge <- @obs_net_edges do %>
                          <% {x1, y1} = Map.get(pos_map, edge.from, {250, 200}) %>
                          <% {x2, y2} = Map.get(pos_map, edge.to, {250, 200}) %>
                          <% opacity = max(0.15, min(0.8, edge.strength)) %>
                          <% color = case edge.type do
                            :friend -> "#22d3ee"
                            :close_friend -> "#a78bfa"
                            :best_friend -> "#c084fc"
                            _ -> "#475569"
                          end %>
                          <line
                            x1={Float.round(x1, 1)} y1={Float.round(y1, 1)}
                            x2={Float.round(x2, 1)} y2={Float.round(y2, 1)}
                            stroke={color}
                            stroke-width={Float.round(max(0.5, edge.strength * 3), 1)}
                            opacity={Float.round(opacity, 2)}
                          />
                        <% end %>

                        <%!-- Nodes --%>
                        <%= for {id, cx, cy, name} <- node_positions do %>
                          <% friends_count = Enum.count(@obs_net_edges, fn e -> e.from == id or e.to == id end) %>
                          <% radius = min(12, 4 + friends_count * 1.5) %>
                          <circle
                            cx={Float.round(cx, 1)} cy={Float.round(cy, 1)}
                            r={Float.round(radius, 1)}
                            fill="#a78bfa"
                            fill-opacity="0.6"
                            stroke="#c084fc"
                            stroke-width="1"
                          />
                          <text
                            x={Float.round(cx, 1)} y={Float.round(cy - radius - 4, 1)}
                            text-anchor="middle"
                            fill="#94a3b8"
                            font-size="8"
                            font-family="monospace"
                          >
                            <%= String.slice(name, 0..8) %>
                          </text>
                        <% end %>
                      </svg>
                    </div>
                    <div class="flex items-center gap-4 mt-2 justify-center text-[9px] text-slate-600">
                      <span class="flex items-center gap-1"><span class="inline-block w-3 h-0.5 bg-cyan-500 rounded"></span> Friend</span>
                      <span class="flex items-center gap-1"><span class="inline-block w-3 h-0.5 bg-purple-400 rounded"></span> Close</span>
                      <span class="flex items-center gap-1"><span class="inline-block w-3 h-0.5 bg-purple-300 rounded"></span> Best</span>
                      <span>🔵 = more connections</span>
                    </div>
                  <% end %>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

    <%!-- Styles now in app.css design system (v5.0.0 Forma) --%>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────

  # ── Chat Panel Helpers (v3.4.0 Nexus) ────────────────────

  defp chat_mood_emoji(agent) when is_map(agent) do
    case agent["affect_state"] || agent[:affect_state] do
      "joy" -> "😊"
      :joy -> "😊"
      "sadness" -> "😢"
      :sadness -> "😢"
      "fear" -> "😨"
      :fear -> "😨"
      "anger" -> "😠"
      :anger -> "😠"
      "desire" -> "😏"
      :desire -> "😏"
      "surprise" -> "😲"
      :surprise -> "😲"
      _ -> "🤖"
    end
  end

  defp chat_mood_emoji(_), do: "🤖"

  defp topic_icon(topic) do
    case topic do
      :trade -> "💰"
      "trade" -> "💰"
      :alliance -> "🤝"
      "alliance" -> "🤝"
      :gossip -> "👂"
      "gossip" -> "👂"
      :warning -> "⚠️"
      "warning" -> "⚠️"
      _ -> "💬"
    end
  end

  defp chat_timestamp(idx) do
    # Simple relative timestamp based on message index
    cond do
      idx == 0 -> "now"
      idx < 3 -> "just now"
      true -> "#{idx}m ago"
    end
  end

  defp resolve_agent_names(agent_ids) when is_list(agent_ids) do
    agent_ids
    |> Enum.map(fn id ->
      try do
        state = Modus.Simulation.Agent.get_state(id)
        state.name
      catch
        :exit, _ -> String.slice(id, 0..7)
      end
    end)
    |> Enum.join(", ")
  end

  defp resolve_agent_names(_), do: "Unknown"

  # Ensure a value is a float (JSON doesn't distinguish 1 from 1.0)
  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  # Dynamic need bar colors based on value
  defp need_bar_color("hunger", val) when val > 80, do: "bg-red-500"
  defp need_bar_color("hunger", val) when val > 60, do: "bg-yellow-500"
  defp need_bar_color("hunger", _val), do: "bg-green-500"
  defp need_bar_color("rest", val) when val < 20, do: "bg-red-500"
  defp need_bar_color("rest", val) when val < 40, do: "bg-yellow-500"
  defp need_bar_color("rest", _val), do: "bg-green-500"
  defp need_bar_color("social", val) when val < 20, do: "bg-red-500"
  defp need_bar_color("social", val) when val < 40, do: "bg-yellow-500"
  defp need_bar_color("social", _val), do: "bg-pink-500"
  defp need_bar_color("shelter", _val), do: "bg-emerald-500"
  defp need_bar_color(_, _val), do: "bg-slate-500"

  defp status_color(:ready), do: "bg-green-500/20 text-green-400"
  defp status_color(:running), do: "bg-cyan-500/20 text-cyan-400"
  defp status_color(:paused), do: "bg-amber-500/20 text-amber-400"
  defp status_color(_), do: "bg-slate-500/20 text-slate-400"

  defp resolve_agent_name(agent_id) when is_binary(agent_id) do
    try do
      state = Modus.Simulation.Agent.get_state(agent_id)
      state.name
    catch
      :exit, _ -> String.slice(agent_id, 0..7)
    end
  end

  defp resolve_agent_name(_), do: "?"

  defp goal_emoji("build_home"), do: "🏠"
  defp goal_emoji("make_friends"), do: "🤝"
  defp goal_emoji("explore_map"), do: "🗺️"
  defp goal_emoji("gather_resources"), do: "📦"
  defp goal_emoji("survive_winter"), do: "❄️"
  defp goal_emoji(_), do: "🎯"

  defp goal_label("build_home", _), do: "Build a Home"
  defp goal_label("make_friends", t), do: "Make #{t || 3} Friends"
  defp goal_label("explore_map", t), do: "Explore #{t || 30}% Map"
  defp goal_label("gather_resources", t), do: "Gather #{t || 20} Resources"
  defp goal_label("survive_winter", _), do: "Survive Winter"
  defp goal_label(type, _), do: type

  defp rel_type_emoji("close_friend"), do: "💛"
  defp rel_type_emoji("friend"), do: "💚"
  defp rel_type_emoji("acquaintance"), do: "🤝"
  defp rel_type_emoji(_), do: "👤"

  defp rel_type_color("close_friend"), do: "text-yellow-400"
  defp rel_type_color("friend"), do: "text-green-400"
  defp rel_type_color("acquaintance"), do: "text-slate-400"
  defp rel_type_color(_), do: "text-slate-500"

  defp rel_bar_color(strength) when strength > 0.8, do: "bg-yellow-500"
  defp rel_bar_color(strength) when strength > 0.5, do: "bg-green-500"
  defp rel_bar_color(strength) when strength > 0.3, do: "bg-cyan-500"
  defp rel_bar_color(_), do: "bg-slate-500"

  defp conversation_events(agent) when is_map(agent) do
    (agent["recent_events"] || [])
    |> Enum.filter(fn e -> e["type"] == "conversation" end)
    |> Enum.take(3)
  end

  defp conversation_events(_), do: []

  # Terrain thumbnail colors now served by WorldTemplates.thumb_color/2

  defp event_emoji("birth"), do: "👶"
  defp event_emoji("death"), do: "💀"
  defp event_emoji("harvest"), do: "🌾"
  defp event_emoji("conversation"), do: "💬"
  defp event_emoji("trade"), do: "🤝"
  defp event_emoji("disaster"), do: "🌋"
  defp event_emoji("migration"), do: "🚶"
  defp event_emoji(_), do: "⚡"

  # ── Speculum Dashboard Data ──────────────────────────────

  defp refresh_dashboard_data do
    pop_history =
      try do
        Observatory.population_history()
      catch
        _, _ -> []
      end

    _stats =
      try do
        Observatory.world_stats()
      catch
        _, _ -> %{population: 0}
      end

    {nodes, edges} =
      try do
        Observatory.relationship_network()
      catch
        _, _ -> {[], []}
      end

    trades =
      try do
        Observatory.trade_timeline(pop_history)
      catch
        _, _ -> []
      end

    # Aggregate resources from all agents
    agents =
      try do
        Modus.Simulation.AgentSupervisor.list_agents()
        |> Enum.map(fn id ->
          try do
            Modus.Simulation.Agent.get_state(id)
          catch
            _, _ -> nil
          end
        end)
        |> Enum.filter(& &1)
      catch
        _, _ -> []
      end

    resources =
      agents
      |> Enum.reduce(%{wood: 0, stone: 0, food: 0, herbs: 0}, fn a, acc ->
        inv = a.inventory || %{}

        %{
          wood: acc.wood + Map.get(inv, :wood, Map.get(inv, "wood", 0)),
          stone: acc.stone + Map.get(inv, :stone, Map.get(inv, "stone", 0)),
          food: acc.food + Map.get(inv, :food, Map.get(inv, "food", 0)),
          herbs: acc.herbs + Map.get(inv, :herbs, Map.get(inv, "herbs", 0))
        }
      end)

    # Mood distribution from agent needs/affect
    mood_counts =
      agents
      |> Enum.map(fn a ->
        needs = a.needs || %{}

        avg =
          (Map.get(needs, :hunger, 50.0) + Map.get(needs, :social, 50.0) +
             Map.get(needs, :rest, 50.0)) / 3.0

        cond do
          avg >= 70 -> :happy
          avg >= 50 -> :calm
          avg >= 30 -> :anxious
          true -> :sad
        end
      end)
      |> Enum.frequencies()

    moods = [
      {"Happy", Map.get(mood_counts, :happy, 0), "#22c55e"},
      {"Calm", Map.get(mood_counts, :calm, 0), "#06b6d4"},
      {"Anxious", Map.get(mood_counts, :anxious, 0), "#f59e0b"},
      {"Sad", Map.get(mood_counts, :sad, 0), "#8b5cf6"}
    ]

    # Wildlife counts
    {predators, prey} =
      try do
        wildlife = :ets.tab2list(:wildlife)
        pred = wildlife |> Enum.count(fn {_id, w} -> w.type in [:wolf, :bear] end)
        pr = wildlife |> Enum.count(fn {_id, w} -> w.type in [:rabbit, :deer, :fish] end)
        {pred, pr}
      catch
        _, _ -> {0, 0}
      end

    %{
      dash_population: pop_history,
      dash_resources: resources,
      dash_nodes: nodes,
      dash_edges: edges,
      dash_moods: moods,
      dash_trades: trades,
      dash_predators: predators,
      dash_prey: prey
    }
  end
end
