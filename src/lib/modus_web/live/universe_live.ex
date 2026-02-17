defmodule ModusWeb.UniverseLive do
  @moduledoc """
  Main LiveView — MODUS universe dashboard with 2D renderer.
  v1.6.0 Creator — World Builder, Terrain Painter, Nature Resource System.
  """
  use ModusWeb, :live_view
  # JS alias available if needed

  @templates [
    %{id: "village", name: "Village", emoji: "🏘️", desc: "Peaceful plains with forests"},
    %{id: "island", name: "Island", emoji: "🏝️", desc: "Surrounded by water, limited land"},
    %{id: "desert", name: "Desert", emoji: "🏜️", desc: "Harsh terrain, scarce resources"},
    %{id: "space", name: "Space", emoji: "🚀", desc: "Alien world, high danger"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Modus.Simulation.EventLog.subscribe()
      Phoenix.PubSub.subscribe(Modus.PubSub, "story")
    end

    {:ok,
     assign(socket,
       page_title: "MODUS",
       # Onboarding
       phase: :onboarding,
       template: "village",
       population: 10,
       danger: "normal",
       world_seed: "",
       grid_size: 100,
       # Simulation
       status: :paused,
       tick: 0,
       agent_count: 0,
       speed: 1,
       time_of_day: "day",
       selected_agent: nil,
       chat_open: false,
       chat_messages: [],
       chat_loading: false,
       # Settings
       settings_open: false,
       settings_provider: if(System.get_env("ANTIGRAVITY_API_KEY"), do: "antigravity", else: "ollama"),
       settings_model: if(System.get_env("ANTIGRAVITY_API_KEY"), do: "gemini-3-flash", else: "llama3.2:3b-instruct-q4_K_M"),
       settings_base_url: if(System.get_env("ANTIGRAVITY_API_KEY"), do: "http://host.docker.internal:8045", else: "http://modus-llm:11434"),
       settings_api_key: System.get_env("ANTIGRAVITY_API_KEY") || "",
       settings_test_result: nil,
       settings_saved: false,
       settings_testing: false,
       # Save/Load
       save_load_open: false,
       saved_worlds: [],
       save_name: "",
       save_load_status: nil,
       # UI
       mind_view_active: false,
       # Deus — God Mode & Cinematic Camera
       god_mode: false,
       cinematic_mode: false,
       build_mode: false,
       build_brush: "grass",
       build_type: "terrain",
       mobile_panel: nil,
       event_feed: [],
       templates: @templates,
       trades_count: 0,
       births_count: 0,
       deaths_count: 0,
       # Potentia — Story & Timeline
       timeline_open: false,
       timeline_entries: [],
       toasts: [],
       chronicle_open: false,
       chronicle_md: "",
       stats_open: false,
       population_history: []
     )}
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

    require Logger
    alias Modus.Simulation.{World, Ticker, AgentSupervisor}

    Logger.info("MODUS launch_world: template=#{template} pop=#{pop} danger=#{danger} grid=#{grid_size}")

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

    opts = if seed_str != "" do
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

    try do AgentSupervisor.terminate_all() catch _, _ -> :ok end
    if Process.whereis(World) do
      try do GenServer.stop(World) catch :exit, _ -> :ok end
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
    {:noreply, assign(socket, selected_agent: agent_data, chat_messages: [], mobile_panel: :agent)}
  end

  def handle_event("deselect_agent", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_agent: nil, chat_open: false, chat_messages: [], mobile_panel: nil)
     |> push_event("deselect_agent", %{})}
  end

  def handle_event("open_chat", _params, socket), do: {:noreply, assign(socket, chat_open: true)}
  def handle_event("close_chat", _params, socket), do: {:noreply, assign(socket, chat_open: false)}

  def handle_event("send_chat", %{"message" => msg}, socket) when msg != "" do
    require Logger
    agent_id = socket.assigns.selected_agent["id"]
    Logger.info("MODUS send_chat: agent_id=#{inspect(agent_id)} msg=#{inspect(msg)}")
    messages = socket.assigns.chat_messages ++ [%{role: "user", text: msg}]
    {:noreply,
     socket
     |> assign(chat_messages: messages, chat_loading: true)
     |> push_event("chat_to_agent", %{
       agent_id: agent_id,
       message: msg
     })}
  end
  def handle_event("send_chat", _params, socket), do: {:noreply, socket}

  def handle_event("chat_response", %{"reply" => reply}, socket) do
    agent_name = if socket.assigns.selected_agent, do: socket.assigns.selected_agent["name"], else: "Agent"
    messages = socket.assigns.chat_messages ++ [%{role: "agent", text: reply, name: agent_name}]
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
    eco = try do Modus.Simulation.Economy.stats() catch _, _ -> %{trades: 0} end
    life = try do Modus.Simulation.Lifecycle.stats() catch _, _ -> %{births: 0, deaths: 0} end

    {:noreply,
     assign(socket,
       tick: params["tick"] || socket.assigns.tick,
       agent_count: params["agent_count"] || socket.assigns.agent_count,
       time_of_day: params["time_of_day"] || socket.assigns.time_of_day,
       trades_count: eco.trades,
       births_count: life.births,
       deaths_count: life.deaths
     )}
  end

  def handle_event("status_change", params, socket) do
    status = String.to_existing_atom(params["status"] || "paused")
    {:noreply, assign(socket, status: status)}
  end

  # ── Settings ─────────────────────────────────────────────────

  def handle_event("open_settings", _params, socket) do
    config = Modus.Intelligence.LlmProvider.get_config()
    {:noreply, assign(socket,
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

    {base_url, model} = if provider_changed do
      case provider do
        "antigravity" -> {"http://host.docker.internal:8045", "gemini-3-flash"}
        _ -> {"http://modus-llm:11434", "llama3.2:3b-instruct-q4_K_M"}
      end
    else
      {socket.assigns.settings_base_url, socket.assigns.settings_model}
    end

    api_key = if provider_changed and provider == "antigravity" do
      System.get_env("ANTIGRAVITY_API_KEY") || socket.assigns.settings_api_key
    else
      params["api_key"] || socket.assigns.settings_api_key
    end

    selected_model = if provider_changed do
      model
    else
      m = params["model"] || model
      if m == "__custom__", do: "", else: m
    end

    {:noreply, assign(socket,
      settings_provider: provider,
      settings_model: selected_model,
      settings_base_url: params["base_url"] || base_url,
      settings_api_key: api_key,
      settings_test_result: nil
    )}
  end

  def handle_event("save_settings", _params, socket) do
    require Logger
    Logger.info("SAVE_SETTINGS provider=#{socket.assigns.settings_provider} model=#{socket.assigns.settings_model} url=#{socket.assigns.settings_base_url}")
    provider = case socket.assigns.settings_provider do
      "antigravity" -> :antigravity
      _ -> :ollama
    end

    api_key = if provider == :antigravity and (socket.assigns.settings_api_key == nil or socket.assigns.settings_api_key == "") do
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
    provider = case socket.assigns.settings_provider do
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
      result = case Modus.Intelligence.LlmProvider.test_connection() do
        :ok -> "ok"
        {:error, reason} -> "error: #{inspect(reason)}"
      end
      send(pid, {:test_llm_result, result})
    end)

    {:noreply, assign(socket, settings_testing: true, settings_test_result: nil)}
  end

  # ── Save / Load ───────────────────────────────────────────────

  def handle_event("open_save_load", _params, socket) do
    worlds = Modus.Persistence.WorldPersistence.list()
    {:noreply, assign(socket, save_load_open: true, saved_worlds: worlds, save_load_status: nil, save_name: "")}
  end

  def handle_event("close_save_load", _params, socket) do
    {:noreply, assign(socket, save_load_open: false)}
  end

  def handle_event("set_save_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, save_name: name)}
  end

  def handle_event("do_save", _params, socket) do
    name = if socket.assigns.save_name == "", do: nil, else: socket.assigns.save_name
    case Modus.Persistence.WorldPersistence.save(name) do
      {:ok, info} ->
        worlds = Modus.Persistence.WorldPersistence.list()
        {:noreply, assign(socket, saved_worlds: worlds, save_load_status: "✅ Saved: #{info.name}", save_name: "")}
      {:error, reason} ->
        {:noreply, assign(socket, save_load_status: "❌ #{reason}")}
    end
  end

  def handle_event("do_load", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    case Modus.Persistence.WorldPersistence.load(id) do
      {:ok, info} ->
        Modus.Simulation.Ticker.run()
        {:noreply,
         socket
         |> assign(save_load_open: false, save_load_status: nil, status: :running)
         |> push_event("world_loaded", %{agents: info.agents, tick: info.tick})}
      {:error, reason} ->
        {:noreply, assign(socket, save_load_status: "❌ #{reason}")}
    end
  end

  def handle_event("do_delete_save", %{"id" => id_str}, socket) do
    {id, _} = Integer.parse(id_str)
    Modus.Persistence.WorldPersistence.delete(id)
    worlds = Modus.Persistence.WorldPersistence.list()
    {:noreply, assign(socket, saved_worlds: worlds, save_load_status: "🗑️ Deleted")}
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
    emoji = case event_type do
      "natural_disaster" -> "🌋"
      "migrant" -> "🚶"
      "resource_bonus" -> "🌾"
      _ -> "⚡"
    end
    label = case event_type do
      "natural_disaster" -> "Natural Disaster"
      "migrant" -> "Migrant Arrived"
      "resource_bonus" -> "Resource Bonus"
      _ -> event_type
    end

    feed = [%{emoji: emoji, label: label, tick: socket.assigns.tick} | Enum.take(socket.assigns.event_feed, 9)]

    {:noreply,
     socket
     |> assign(event_feed: feed)
     |> push_event("inject_event", %{event_type: event_type})}
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
    new_panel = if current == String.to_existing_atom(panel), do: nil, else: String.to_existing_atom(panel)
    {:noreply, assign(socket, mobile_panel: new_panel)}
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
    entries = if open do
      try do Modus.Simulation.StoryEngine.get_timeline(limit: 50) catch _, _ -> [] end
    else
      []
    end
    {:noreply, assign(socket, timeline_open: open, timeline_entries: entries)}
  end

  def handle_event("open_chronicle", _params, socket) do
    md = try do Modus.Simulation.StoryEngine.export_markdown() catch _, _ -> "No chronicle data yet." end
    {:noreply, assign(socket, chronicle_open: true, chronicle_md: md)}
  end

  def handle_event("close_chronicle", _params, socket) do
    {:noreply, assign(socket, chronicle_open: false)}
  end

  def handle_event("open_stats", _params, socket) do
    history = try do Modus.Simulation.StoryEngine.population_history() catch _, _ -> [] end
    {:noreply, assign(socket, stats_open: true, population_history: history)}
  end

  def handle_event("close_stats", _params, socket) do
    {:noreply, assign(socket, stats_open: false)}
  end

  def handle_event("dismiss_toast", %{"id" => id}, socket) do
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == id))
    {:noreply, assign(socket, toasts: toasts)}
  end

  # ── PubSub Events ───────────────────────────────────────────

  @impl true
  def handle_info({:event, event}, socket) do
    emoji = case event.type do
      :death -> "💀"
      :birth -> "👶"
      :conversation -> "💬"
      :conflict -> "⚔️"
      :resource_gathered -> "🌾"
      _ -> "⚡"
    end

    name = event.data[:name] || event.data["name"] || resolve_agent_names(event.agents)
    label = case event.type do
      :death -> "#{name} died (#{event.data[:cause] || "unknown"})"
      :birth -> "#{name} was born"
      :conversation -> "#{name} had a conversation"
      :conflict -> "Conflict!"
      :resource_gathered -> "#{name} gathered resources"
      _ -> to_string(event.type)
    end

    feed = [%{emoji: emoji, label: label, tick: event.tick} | Enum.take(socket.assigns.event_feed, 19)]
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
    socket = if socket.assigns.timeline_open do
      entries = try do Modus.Simulation.StoryEngine.get_timeline(limit: 50) catch _, _ -> [] end
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

  def handle_info(:clear_settings_saved, socket) do
    {:noreply, assign(socket, settings_saved: false, settings_open: false)}
  end

  def handle_info({:test_llm_result, result}, socket) do
    {:noreply, assign(socket, settings_testing: false, settings_test_result: result)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Render ──────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @phase == :onboarding do %>
      <%= render_onboarding(assigns) %>
    <% else %>
      <%= render_simulation(assigns) %>
    <% end %>
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
        </div>
        <p class="text-xs text-slate-600 mb-6">v1.6.0 Creator · 29+ modules · Elixir/BEAM · Pixi.js</p>
      </div>

      <%!-- Create World Section --%>
      <div class="flex justify-center px-4 pb-16">
      <div class="w-full max-w-lg">

        <%!-- Step 1: Template --%>
        <div class="mb-6">
          <h3 class="text-[10px] uppercase tracking-wider text-slate-500 mb-3">Choose a World Template</h3>
          <div class="grid grid-cols-2 gap-3">
            <%= for t <- @templates do %>
              <button
                phx-click="select_template"
                phx-value-id={t.id}
                class={"p-4 rounded-xl border text-left transition-all #{if @template == t.id, do: "border-purple-500 bg-purple-500/10 shadow-lg shadow-purple-500/10", else: "border-white/10 bg-white/5 hover:border-white/20"}"}
              >
                <div class="text-2xl mb-1"><%= t.emoji %></div>
                <div class="font-bold text-sm"><%= t.name %></div>
                <div class="text-[10px] text-slate-500 mt-0.5"><%= t.desc %></div>
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

        <%!-- Step 4: Grid Size --%>
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
      </div>
      </div>
    </div>
    """
  end

  # ── Simulation View ────────────────────────────────────────

  defp render_simulation(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-[#050508] text-slate-200 font-mono overflow-hidden">
      <%!-- Top Bar --%>
      <nav class="border-b border-white/5 bg-[#0A0A0F]/80 backdrop-blur-md px-4 md:px-6 h-14 flex items-center justify-between shrink-0 z-20">
        <div class="flex items-center gap-3">
          <span class="text-xl font-bold tracking-tighter">
            MODUS<span class="text-purple-400">_</span>
          </span>
          <span class="text-xs text-slate-600 hidden sm:inline">v1.6.0 · Creator</span>
        </div>

        <div class="flex items-center gap-3 md:gap-6">
          <%!-- Stats --%>
          <div class="flex items-center gap-3 md:gap-4 text-xs text-slate-500">
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

          <%!-- Build Mode --%>
          <button phx-click="toggle_build_mode" class={"ctrl-btn #{if @build_mode, do: "ctrl-btn-active"}"} title="Build Mode — World Builder">
            🔨
          </button>

          <%!-- God Mode --%>
          <button phx-click="toggle_god_mode" class={"ctrl-btn #{if @god_mode, do: "ctrl-btn-active"}"} title="God Mode — See All Agent Internals">
            👁️
          </button>

          <%!-- Cinematic Camera --%>
          <button phx-click="toggle_cinematic" class={"ctrl-btn #{if @cinematic_mode, do: "ctrl-btn-active"}"} title="Cinematic Camera — Auto-follow Events">
            🎬
          </button>

          <%!-- Screenshot --%>
          <button phx-click="take_screenshot" class="ctrl-btn" title="Screenshot Export">
            📸
          </button>

          <%!-- Mind View Toggle --%>
          <button id="mind-view-btn" phx-click="toggle_mind_view" class={"ctrl-btn #{if @mind_view_active, do: "ctrl-btn-primary"}"} title="Mind View">
            🧠
          </button>

          <%!-- Timeline --%>
          <button phx-click="toggle_timeline" class={"ctrl-btn #{if @timeline_open, do: "ctrl-btn-primary"}"} title="Timeline">
            📜
          </button>

          <%!-- Stats --%>
          <button phx-click="open_stats" class="ctrl-btn" title="Population Stats">
            📊
          </button>

          <%!-- Chronicle Export --%>
          <button phx-click="open_chronicle" class="ctrl-btn" title="Export Chronicle">
            📖
          </button>

          <%!-- Save/Load --%>
          <button phx-click="open_save_load" class="ctrl-btn" title="Save / Load World">
            💾
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
        <div class={"shrink-0 border-r border-white/5 bg-[#0A0A0F]/90 backdrop-blur-md overflow-y-auto z-10 transition-all duration-300 " <>
          "hidden md:block " <> if(@timeline_open, do: "md:w-64", else: "md:w-48")}>
          <div class="p-3">
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

              <div class="text-[9px] text-slate-600 leading-relaxed">
                Click/drag on map to paint.<br/>
                Resources respawn after 200 ticks.<br/>
                Nature is survival infrastructure.
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

          <div class="absolute bottom-4 left-4 text-[10px] text-slate-600 pointer-events-none hidden md:block">
            Click agent to inspect · Drag to pan · Scroll to zoom · <span class="text-slate-500">Space</span>=pause · <span class="text-slate-500">1/5/0</span>=speed · <span class="text-slate-500">G</span>=god · <span class="text-slate-500">C</span>=cinematic · <span class="text-slate-500">P</span>=screenshot · <span class="text-slate-500">M</span>=minimap · <span class="text-slate-500">Esc</span>=deselect
          </div>
        </div>

        <%!-- Right Panel: Agent Detail (desktop) --%>
        <%= if @selected_agent do %>
          <div class={"shrink-0 border-l border-white/5 bg-[#0A0A0F]/90 backdrop-blur-md overflow-y-auto z-10 transition-all duration-300 " <>
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

              <%!-- Chat Button --%>
              <button phx-click="open_chat" class="w-full ctrl-btn ctrl-btn-primary text-center">
                💬 Chat with <%= @selected_agent["name"] %>
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Mobile Bottom Bar --%>
        <div class="fixed bottom-0 inset-x-0 md:hidden bg-[#0A0A0F]/95 backdrop-blur-md border-t border-white/5 z-30 px-2 py-2 flex items-center justify-around">
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
        <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
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

      <%!-- Save/Load Modal --%>
      <%= if @save_load_open do %>
        <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-md max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_save_load">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <span class="font-bold text-slate-100">💾 Save / Load World</span>
              <button phx-click="close_save_load" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>
            <div class="p-4 space-y-4 overflow-y-auto">
              <%!-- Save Section --%>
              <div>
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Save Current World</h3>
                <div class="flex gap-2">
                  <input type="text" name="name" value={@save_name} placeholder="Save name (optional)"
                    phx-change="set_save_name" phx-debounce="300"
                    class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-purple-500/50" />
                  <button phx-click="do_save" class="ctrl-btn ctrl-btn-primary px-4">💾 Save</button>
                </div>
              </div>

              <%!-- Status --%>
              <%= if @save_load_status do %>
                <div class="text-sm px-3 py-2 rounded-lg bg-white/5 text-slate-300">
                  <%= @save_load_status %>
                </div>
              <% end %>

              <%!-- Load Section --%>
              <div>
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Saved Worlds</h3>
                <%= if @saved_worlds == [] do %>
                  <p class="text-xs text-slate-600 italic">No saved worlds yet</p>
                <% else %>
                  <div class="space-y-2">
                    <%= for world <- @saved_worlds do %>
                      <div class="flex items-center gap-3 p-3 rounded-lg bg-white/3 border border-white/5 hover:border-white/10 transition-all">
                        <div class="flex-1 min-w-0">
                          <div class="text-sm font-medium text-slate-200 truncate"><%= world.name %></div>
                          <div class="text-[10px] text-slate-500">
                            🗺️ <%= world.template %> · 👥 <%= world.agents %> agents · ⏱️ tick <%= world.tick %>
                          </div>
                        </div>
                        <button phx-click="do_load" phx-value-id={world.id} class="ctrl-btn ctrl-btn-primary text-[10px] px-3">▶ Load</button>
                        <button phx-click="do_delete_save" phx-value-id={world.id} class="ctrl-btn text-[10px] px-2 text-red-400 hover:text-red-300">🗑️</button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Chat Modal --%>
      <%= if @chat_open && @selected_agent do %>
        <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-md max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_chat">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <div>
                <span class="font-bold text-slate-100"><%= @selected_agent["name"] %></span>
                <span class="text-xs text-slate-500 ml-2"><%= @selected_agent["occupation"] %></span>
              </div>
              <button phx-click="close_chat" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>
            <div class="flex-1 overflow-y-auto p-4 space-y-3" id="chat-messages">
              <%= if @chat_messages == [] do %>
                <p class="text-xs text-slate-600 text-center italic">Say something to <%= @selected_agent["name"] %>...</p>
              <% end %>
              <%= for msg <- @chat_messages do %>
                <div class={"flex #{if msg.role == "user", do: "justify-end", else: "justify-start"}"}>
                  <div class={"max-w-[80%] px-3 py-2 rounded-lg text-sm #{if msg.role == "user", do: "bg-purple-500/20 text-purple-200", else: "bg-white/5 text-slate-300"}"}>
                    <%= if msg.role == "agent" do %>
                      <span class="text-[10px] text-cyan-400 block mb-0.5"><%= msg.name %></span>
                    <% end %>
                    <%= msg.text %>
                  </div>
                </div>
              <% end %>
              <%= if @chat_loading do %>
                <div class="flex justify-start">
                  <div class="bg-white/5 px-3 py-2 rounded-lg text-sm text-slate-500 animate-pulse">thinking...</div>
                </div>
              <% end %>
            </div>
            <form phx-submit="send_chat" id="chat-form" class="p-3 border-t border-white/5 shrink-0">
              <div class="flex gap-2">
                <input type="text" name="message" id="chat-input" placeholder={"Talk to #{@selected_agent["name"]}..."} autocomplete="off"
                  class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-purple-500/50" />
                <button type="submit" class="ctrl-btn ctrl-btn-primary px-4">Send</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>

      <%!-- Toast Notifications --%>
      <%= if @toasts != [] do %>
        <div class="fixed top-16 right-4 z-50 space-y-2 pointer-events-none">
          <%= for toast <- @toasts do %>
            <div class="pointer-events-auto flex items-center gap-2 px-4 py-2 rounded-lg bg-[#0A0A0F]/95 border border-purple-500/30 shadow-lg shadow-purple-500/10 backdrop-blur-md animate-slide-in max-w-xs">
              <span class="text-lg"><%= toast.emoji %></span>
              <div class="flex-1 min-w-0">
                <p class="text-xs text-slate-200 truncate"><%= toast.text %></p>
                <span class="text-[9px] text-slate-600">tick <%= toast.tick %></span>
              </div>
              <button phx-click="dismiss_toast" phx-value-id={toast.id} class="text-slate-600 hover:text-slate-400 text-xs ml-1">✕</button>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Chronicle Export Modal --%>
      <%= if @chronicle_open do %>
        <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-2xl max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_chronicle">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <span class="font-bold text-slate-100">📖 World Chronicle</span>
              <button phx-click="close_chronicle" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>
            <div class="p-4 overflow-y-auto flex-1">
              <pre class="text-xs text-slate-300 whitespace-pre-wrap font-mono leading-relaxed"><%= @chronicle_md %></pre>
            </div>
            <div class="px-4 py-3 border-t border-white/5 shrink-0">
              <p class="text-[10px] text-slate-600">Copy the text above to save your world's story as markdown.</p>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Stats Modal --%>
      <%= if @stats_open do %>
        <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-full max-w-lg max-h-[80vh] flex flex-col shadow-2xl" phx-click-away="close_stats">
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <span class="font-bold text-slate-100">📊 Population Stats</span>
              <button phx-click="close_stats" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>
            <div class="p-4 overflow-y-auto flex-1">
              <%= if @population_history == [] do %>
                <p class="text-xs text-slate-600 italic text-center">No data yet. Run the simulation for a while...</p>
              <% else %>
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-3">Population Over Time</h3>
                <%!-- ASCII-style population graph --%>
                <div class="bg-white/3 rounded-lg p-3 border border-white/5">
                  <% max_pop = @population_history |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) %>
                  <% sampled = @population_history |> Enum.take_every(max(div(length(@population_history), 40), 1)) |> Enum.take(40) %>
                  <div class="flex items-end gap-px h-32">
                    <%= for {_tick, pop} <- sampled do %>
                      <% height = if max_pop > 0, do: pop / max_pop * 100, else: 0 %>
                      <div
                        class="flex-1 bg-purple-500/60 rounded-t-sm min-w-[2px] transition-all duration-300 hover:bg-purple-400/80"
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

                <%!-- Summary Stats --%>
                <div class="grid grid-cols-2 gap-3 mt-4">
                  <div class="bg-white/3 rounded-lg p-3 border border-white/5 text-center">
                    <div class="text-2xl font-bold text-purple-400"><%= elem(List.last(@population_history), 1) %></div>
                    <div class="text-[10px] text-slate-600 uppercase">Current</div>
                  </div>
                  <div class="bg-white/3 rounded-lg p-3 border border-white/5 text-center">
                    <div class="text-2xl font-bold text-cyan-400"><%= @population_history |> Enum.map(&elem(&1, 1)) |> Enum.max() %></div>
                    <div class="text-[10px] text-slate-600 uppercase">Peak</div>
                  </div>
                  <div class="bg-white/3 rounded-lg p-3 border border-white/5 text-center">
                    <div class="text-2xl font-bold text-green-400"><%= @births_count %></div>
                    <div class="text-[10px] text-slate-600 uppercase">Births</div>
                  </div>
                  <div class="bg-white/3 rounded-lg p-3 border border-white/5 text-center">
                    <div class="text-2xl font-bold text-red-400"><%= @deaths_count %></div>
                    <div class="text-[10px] text-slate-600 uppercase">Deaths</div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

    <style>
      .ctrl-btn {
        padding: 4px 12px;
        font-size: 11px;
        font-family: monospace;
        border-radius: 6px;
        background: rgba(255, 255, 255, 0.05);
        border: 1px solid rgba(255, 255, 255, 0.08);
        color: #94a3b8;
        cursor: pointer;
        transition: all 0.15s;
      }
      .ctrl-btn:hover { background: rgba(255, 255, 255, 0.1); color: #e2e8f0; }
      .ctrl-btn-active {
        background: rgba(6, 182, 212, 0.15);
        border-color: rgba(6, 182, 212, 0.4);
        color: #22d3ee;
        box-shadow: 0 0 8px rgba(6, 182, 212, 0.15);
      }
      .ctrl-btn-active:hover { background: rgba(6, 182, 212, 0.25); color: #67e8f9; }
      .ctrl-btn-primary {
        background: rgba(168, 85, 247, 0.15);
        border-color: rgba(168, 85, 247, 0.3);
        color: #c084fc;
      }
      .ctrl-btn-primary:hover { background: rgba(168, 85, 247, 0.25); color: #e9d5ff; }
      .event-btn {
        display: flex;
        align-items: center;
        gap: 8px;
        width: 100%;
        padding: 8px 12px;
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.03);
        border: 1px solid rgba(255, 255, 255, 0.06);
        color: #94a3b8;
        cursor: pointer;
        transition: all 0.15s;
        font-family: monospace;
      }
      .event-btn:hover { background: rgba(255, 255, 255, 0.08); border-color: rgba(255, 255, 255, 0.12); color: #e2e8f0; }
      .event-btn:active { transform: scale(0.97); }
      .mobile-action-btn {
        padding: 6px 12px;
        font-size: 18px;
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.05);
        border: none;
        cursor: pointer;
        transition: all 0.1s;
      }
      .mobile-action-btn:active { transform: scale(0.9); background: rgba(168, 85, 247, 0.2); }
      @keyframes slide-in { from { opacity: 0; transform: translateX(20px); } to { opacity: 1; transform: translateX(0); } }
      .animate-slide-in { animation: slide-in 0.3s ease-out; }
    </style>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────

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

  defp event_emoji("birth"), do: "👶"
  defp event_emoji("death"), do: "💀"
  defp event_emoji("harvest"), do: "🌾"
  defp event_emoji("conversation"), do: "💬"
  defp event_emoji("trade"), do: "🤝"
  defp event_emoji("disaster"), do: "🌋"
  defp event_emoji("migration"), do: "🚶"
  defp event_emoji(_), do: "⚡"
end
