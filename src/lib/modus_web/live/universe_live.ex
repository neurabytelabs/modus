defmodule ModusWeb.UniverseLive do
  @moduledoc """
  Main LiveView — MODUS universe dashboard with 2D renderer.
  Includes onboarding wizard, time controls, event injection, responsive layout.
  """
  use ModusWeb, :live_view
  alias Phoenix.LiveView.JS

  @templates [
    %{id: "village", name: "Village", emoji: "🏘️", desc: "Peaceful plains with forests"},
    %{id: "island", name: "Island", emoji: "🏝️", desc: "Surrounded by water, limited land"},
    %{id: "desert", name: "Desert", emoji: "🏜️", desc: "Harsh terrain, scarce resources"},
    %{id: "space", name: "Space", emoji: "🚀", desc: "Alien world, high danger"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "MODUS",
       # Onboarding
       phase: :onboarding,
       template: "village",
       population: 10,
       danger: "normal",
       # Simulation
       status: :paused,
       tick: 0,
       agent_count: 0,
       speed: 1,
       selected_agent: nil,
       chat_open: false,
       chat_messages: [],
       chat_loading: false,
       # UI
       mobile_panel: nil,
       event_feed: [],
       templates: @templates
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

  def handle_event("launch_world", _params, socket) do
    {:noreply,
     socket
     |> assign(phase: :simulation)
     |> push_event("create_world", %{
       template: socket.assigns.template,
       population: socket.assigns.population,
       danger: socket.assigns.danger
     })}
  end

  def handle_event("skip_onboarding", _params, socket) do
    {:noreply, assign(socket, phase: :simulation)}
  end

  # ── Simulation Events ──────────────────────────────────────

  def handle_event("world_state", params, socket) do
    {:noreply,
     assign(socket,
       tick: params["tick"] || 0,
       agent_count: params["agent_count"] || 0,
       status: String.to_existing_atom(params["status"] || "paused")
     )}
  end

  def handle_event("select_agent", %{"agent" => agent_data}, socket) do
    {:noreply, assign(socket, selected_agent: agent_data, chat_messages: [], mobile_panel: :agent)}
  end

  def handle_event("deselect_agent", _params, socket) do
    {:noreply, assign(socket, selected_agent: nil, chat_open: false, chat_messages: [], mobile_panel: nil)}
  end

  def handle_event("open_chat", _params, socket), do: {:noreply, assign(socket, chat_open: true)}
  def handle_event("close_chat", _params, socket), do: {:noreply, assign(socket, chat_open: false)}

  def handle_event("send_chat", %{"message" => msg}, socket) when msg != "" do
    messages = socket.assigns.chat_messages ++ [%{role: "user", text: msg}]
    {:noreply,
     socket
     |> assign(chat_messages: messages, chat_loading: true)
     |> push_event("chat_to_agent", %{
       agent_id: socket.assigns.selected_agent["id"],
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
    {:noreply, assign(socket, selected_agent: detail)}
  end

  def handle_event("tick_update", params, socket) do
    {:noreply,
     assign(socket,
       tick: params["tick"] || socket.assigns.tick,
       agent_count: params["agent_count"] || socket.assigns.agent_count
     )}
  end

  def handle_event("status_change", params, socket) do
    status = String.to_existing_atom(params["status"] || "paused")
    {:noreply, assign(socket, status: status)}
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

  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    current = socket.assigns.mobile_panel
    new_panel = if current == String.to_existing_atom(panel), do: nil, else: String.to_existing_atom(panel)
    {:noreply, assign(socket, mobile_panel: new_panel)}
  end

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
    <div class="h-screen flex items-center justify-center bg-[#050508] text-slate-200 font-mono">
      <div class="w-full max-w-lg mx-4">
        <%!-- Logo --%>
        <div class="text-center mb-8">
          <h1 class="text-4xl font-bold tracking-tighter mb-2">
            MODUS<span class="text-purple-400">_</span>
          </h1>
          <p class="text-sm text-slate-500">Create worlds. Watch them live.</p>
        </div>

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
          <span class="text-xs text-slate-600 hidden sm:inline">v0.2.0</span>
        </div>

        <div class="flex items-center gap-3 md:gap-6">
          <%!-- Stats --%>
          <div class="flex items-center gap-3 md:gap-4 text-xs text-slate-500">
            <div class="flex items-center gap-1.5">
              <span class="text-slate-600 hidden sm:inline">TICK</span>
              <span class="text-cyan-400 font-bold tabular-nums"><%= @tick %></span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-slate-600 hidden sm:inline">POP</span>
              <span class="text-purple-400 font-bold tabular-nums"><%= @agent_count %></span>
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
        </div>
      </nav>

      <%!-- Main Area --%>
      <div class="flex-1 flex overflow-hidden relative">
        <%!-- Event Injection Panel (left sidebar on desktop, bottom drawer on mobile) --%>
        <div class={"shrink-0 border-r border-white/5 bg-[#0A0A0F]/90 backdrop-blur-md overflow-y-auto z-10 transition-all duration-300 " <>
          "hidden md:block md:w-48"}>
          <div class="p-3">
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
          </div>
        </div>

        <%!-- Canvas Container --%>
        <div id="world-canvas" phx-hook="WorldCanvas" class="flex-1 relative">
          <%!-- Loading Skeleton --%>
          <div id="canvas-skeleton" class="absolute inset-0 flex items-center justify-center pointer-events-none">
            <div class="flex flex-col items-center gap-3">
              <div class="w-12 h-12 border-2 border-purple-500/30 border-t-purple-500 rounded-full animate-spin"></div>
              <span class="text-xs text-slate-600 animate-pulse">Initializing universe...</span>
            </div>
          </div>

          <div class="absolute bottom-4 left-4 text-[10px] text-slate-600 pointer-events-none hidden md:block">
            Click agent to inspect · Drag to pan · Scroll to zoom
          </div>
        </div>

        <%!-- Right Panel: Agent Detail (desktop) --%>
        <%= if @selected_agent do %>
          <div class={"shrink-0 border-l border-white/5 bg-[#0A0A0F]/90 backdrop-blur-md overflow-y-auto z-10 transition-all duration-300 " <>
            "fixed inset-x-0 bottom-0 top-14 md:static md:w-80 " <>
            if(@mobile_panel == :agent, do: "translate-y-0", else: "translate-y-full md:translate-y-0")}>
            <div class="p-4">
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
                        <div class={"h-full rounded-full transition-all duration-500 #{need_color(need)}"} style={"width: #{min(val || 0, 100)}%"} />
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>

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
                      <span class="text-[10px] text-slate-500 tabular-nums w-6 text-right"><%= val || 0 %></span>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <%!-- Relationships --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Relationships</h3>
                <%= if @selected_agent["relationships"] && @selected_agent["relationships"] != [] do %>
                  <%= for rel <- @selected_agent["relationships"] do %>
                    <div class="text-xs text-slate-400 mb-1">
                      <span class="text-purple-400"><%= rel["type"] %></span>
                      · strength: <%= rel["strength"] %>
                    </div>
                  <% end %>
                <% else %>
                  <p class="text-xs text-slate-600 italic">No relationships yet</p>
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

      <%!-- Chat Modal --%>
      <%= if @chat_open && @selected_agent do %>
        <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4" phx-click="close_chat">
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
            <form phx-submit="send_chat" class="p-3 border-t border-white/5 shrink-0">
              <div class="flex gap-2">
                <input type="text" name="message" placeholder={"Talk to #{@selected_agent["name"]}..."} autocomplete="off"
                  class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-purple-500/50" />
                <button type="submit" class="ctrl-btn ctrl-btn-primary px-4">Send</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>

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
    </style>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp need_color("hunger"), do: "bg-orange-500"
  defp need_color("social"), do: "bg-pink-500"
  defp need_color("rest"), do: "bg-blue-500"
  defp need_color("shelter"), do: "bg-emerald-500"
  defp need_color(_), do: "bg-slate-500"

  defp status_color(:ready), do: "bg-green-500/20 text-green-400"
  defp status_color(:running), do: "bg-cyan-500/20 text-cyan-400"
  defp status_color(:paused), do: "bg-amber-500/20 text-amber-400"
  defp status_color(_), do: "bg-slate-500/20 text-slate-400"

  defp event_emoji("birth"), do: "👶"
  defp event_emoji("death"), do: "💀"
  defp event_emoji("harvest"), do: "🌾"
  defp event_emoji("conversation"), do: "💬"
  defp event_emoji("trade"), do: "🤝"
  defp event_emoji("disaster"), do: "🌋"
  defp event_emoji("migration"), do: "🚶"
  defp event_emoji(_), do: "⚡"
end
