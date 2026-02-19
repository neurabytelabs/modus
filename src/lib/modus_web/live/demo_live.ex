defmodule ModusWeb.DemoLive do
  @moduledoc """
  Demo/Watch mode — read-only view of the MODUS simulation.
  No authentication required. Anyone with the URL can observe.
  No God Mode commands, no chat input, just observe.
  """
  use ModusWeb, :live_view

  alias Modus.Simulation.{World, Ticker, Observatory}
  alias ModusWeb.Presence

  @presence_topic "demo:viewers"

  @impl true
  def mount(_params, _session, socket) do
    world_running? = Process.whereis(World) != nil

    if connected?(socket) do
      if world_running? do
        Modus.Simulation.EventLog.subscribe()
        Phoenix.PubSub.subscribe(Modus.PubSub, "story")
        Phoenix.PubSub.subscribe(Modus.PubSub, "world_events")
        Phoenix.PubSub.subscribe(Modus.PubSub, "prayers")
        Phoenix.PubSub.subscribe(Modus.PubSub, "agent_chats")
      end

      # Track this viewer via Presence
      Phoenix.PubSub.subscribe(Modus.PubSub, @presence_topic)
      viewer_id = "viewer_" <> Base.encode16(:crypto.strong_rand_bytes(4))
      {:ok, _} = Presence.track(self(), @presence_topic, viewer_id, %{joined_at: System.system_time(:second)})
    end

    {tick, agent_count, avg_conatus} = if world_running?, do: fetch_metrics(), else: {0, 0, 0.0}

    viewer_count = Presence.list(@presence_topic) |> map_size()

    {:ok,
     assign(socket,
       page_title: "MODUS — Demo",
       world_running: world_running?,
       viewer_count: viewer_count,
       tick: tick,
       agent_count: agent_count,
       avg_conatus: avg_conatus,
       time_of_day: "day",
       season_name: "Spring",
       season_emoji: "🌸",
       season_year: 1,
       weather_name: "Clear",
       weather_emoji: "☀️",
       event_feed: [],
       chat_feed: [],
       prayer_feed: [],
       toasts: []
     )}
  end

  # ── PubSub Handlers (read-only) ────────────────────────────

  @impl true
  def handle_info({:event, event}, socket) do
    emoji = event_emoji(event.type)
    name = event.data[:name] || event.data["name"] || "Agent"

    label =
      case event.type do
        :death -> "#{name} died"
        :birth -> "#{name} was born"
        :conversation -> "#{name} had a conversation"
        :conflict -> "Conflict!"
        _ -> to_string(event.type)
      end

    entry = %{emoji: emoji, label: label, tick: event.tick}
    feed = Enum.take([entry | socket.assigns.event_feed], 20)
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
    Process.send_after(self(), {:dismiss_toast, toast.id}, 6_000)
    {:noreply, assign(socket, toasts: toasts)}
  end

  def handle_info({:dismiss_toast, id}, socket) do
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == id))
    {:noreply, assign(socket, toasts: toasts)}
  end

  def handle_info({:world_event, event_data}, socket) when is_map(event_data) do
    event_type = event_data[:type] || event_data["type"] || "unknown"
    emoji = event_data[:emoji] || event_data["emoji"] || "⚡"
    label = "#{String.replace(to_string(event_type), "_", " ")}"
    entry = %{emoji: emoji, label: label, tick: socket.assigns.tick}
    feed = Enum.take([entry | socket.assigns.event_feed], 20)
    {:noreply, assign(socket, event_feed: feed)}
  end

  def handle_info({:new_prayer, prayer}, socket) do
    entry = %{
      emoji: "🙏",
      agent: prayer[:agent_name] || prayer["agent_name"] || "Agent",
      text: prayer[:text] || prayer["text"] || "...",
      tick: prayer[:tick] || prayer["tick"] || socket.assigns.tick
    }

    feed = Enum.take([entry | socket.assigns.prayer_feed], 15)
    {:noreply, assign(socket, prayer_feed: feed)}
  end

  def handle_info({:new_agent_chat, chat}, socket) do
    entry = %{
      speaker: chat[:speaker] || chat["speaker"] || "Agent",
      text: chat[:text] || chat["text"] || chat[:line] || chat["line"] || "...",
      tick: chat[:tick] || chat["tick"] || socket.assigns.tick
    }

    feed = Enum.take([entry | socket.assigns.chat_feed], 20)
    {:noreply, assign(socket, chat_feed: feed)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    viewer_count = Presence.list(@presence_topic) |> map_size()
    {:noreply, assign(socket, viewer_count: viewer_count)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Tick updates from JS (via phx-hook) ────────────────────

  @impl true
  def handle_event("tick_update", params, socket) do
    tick = params["tick"] || socket.assigns.tick
    agent_count = params["agent_count"] || socket.assigns.agent_count

    season_assigns =
      if params["season"] do
        [
          season_name: params["season"]["season_name"] || socket.assigns.season_name,
          season_emoji: params["season"]["emoji"] || socket.assigns.season_emoji,
          season_year: params["season"]["year"] || socket.assigns.season_year
        ]
      else
        []
      end

    weather_assigns =
      if params["weather"] do
        [
          weather_name: params["weather"]["name"] || socket.assigns.weather_name,
          weather_emoji: params["weather"]["emoji"] || socket.assigns.weather_emoji
        ]
      else
        []
      end

    # Refresh avg_conatus periodically
    avg_conatus =
      if is_integer(tick) and rem(tick, 20) == 0 do
        try do
          stats = Observatory.world_stats()
          Float.round(stats.avg_conatus, 2)
        catch
          _, _ -> socket.assigns.avg_conatus
        end
      else
        socket.assigns.avg_conatus
      end

    {:noreply,
     assign(
       socket,
       [{:tick, tick}, {:agent_count, agent_count}, {:avg_conatus, avg_conatus},
        {:time_of_day, params["time_of_day"] || socket.assigns.time_of_day}
        | season_assigns ++ weather_assigns]
     )}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  # ── Render ──────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050508] text-slate-200 font-mono">
      <%!-- Demo Banner --%>
      <div class="bg-gradient-to-r from-amber-500/20 to-orange-500/20 border-b border-amber-500/30 px-4 py-2 text-center">
        <span class="text-sm font-bold text-amber-300">👁️ DEMO MODE</span>
        <span class="text-xs text-amber-400/70 ml-2">Read-only observation · No commands</span>
        <span class="text-xs text-amber-400/50 ml-3">👥 <%= @viewer_count %> watching</span>
      </div>

      <%= if !@world_running do %>
        <%!-- No simulation running --%>
        <div class="flex flex-col items-center justify-center min-h-[80vh] px-4">
          <div class="text-6xl mb-6 opacity-30">🌌</div>
          <h1 class="text-3xl font-bold tracking-tighter mb-3">
            MODUS<span class="text-purple-400">_</span>
          </h1>
          <p class="text-lg text-slate-400 mb-2">No simulation running</p>
          <p class="text-sm text-slate-600">Waiting for a world to be created...</p>
          <p class="text-xs text-slate-700 mt-4">This page will update automatically when a simulation starts.</p>
        </div>
      <% else %>
        <%!-- Top Metrics Bar --%>
        <div class="px-4 md:px-6 h-12 flex items-center justify-between border-b border-white/5">
          <div class="flex items-center gap-3">
            <span class="text-lg font-bold tracking-tighter">
              MODUS<span class="text-purple-400">_</span>
            </span>
            <span class="text-[10px] text-slate-600">DEMO</span>
          </div>

          <div class="flex items-center gap-3 md:gap-5 text-xs text-slate-500">
            <div class="flex items-center gap-1 px-2 py-0.5 rounded bg-slate-800/60 border border-slate-700/50">
              <span class="text-sm"><%= @season_emoji %></span>
              <span class="text-slate-300 font-medium text-[10px] uppercase"><%= @season_name %></span>
              <span class="text-slate-600 text-[9px]">Y<%= @season_year %></span>
            </div>
            <div class="flex items-center gap-1 px-2 py-0.5 rounded bg-slate-800/60 border border-slate-700/50">
              <span class="text-sm"><%= @weather_emoji %></span>
              <span class="text-slate-300 font-medium text-[10px] uppercase"><%= @weather_name %></span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-sm"><%= if @time_of_day == "night", do: "🌙", else: "☀️" %></span>
              <span class="text-slate-600">TICK</span>
              <span class="text-cyan-400 font-bold tabular-nums"><%= @tick %></span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-slate-600">POP</span>
              <span class="text-purple-400 font-bold tabular-nums"><%= @agent_count %></span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-slate-600">CONATUS</span>
              <span class="text-emerald-400 font-bold tabular-nums"><%= Float.round(@avg_conatus * 100, 0) %>%</span>
            </div>
          </div>
        </div>

        <%!-- Main Content --%>
        <div class="flex min-h-[calc(100vh-7rem)]">
          <%!-- Canvas (reuse existing renderer in read-only) --%>
          <div id="demo-canvas" phx-hook="DemoCanvas" phx-update="ignore" class="flex-1 min-w-0 relative overflow-hidden">
            <div id="canvas-skeleton" class="absolute inset-0 flex items-center justify-center pointer-events-none">
              <div class="flex flex-col items-center gap-3">
                <div class="w-12 h-12 border-2 border-purple-500/30 border-t-purple-500 rounded-full animate-spin"></div>
                <span class="text-xs text-slate-600 animate-pulse">Loading world view...</span>
              </div>
            </div>
          </div>

          <%!-- Right Sidebar: Feeds --%>
          <div class="hidden md:block w-72 border-l border-white/5 overflow-y-auto">
            <%!-- Agent Chat Stream --%>
            <div class="p-3 border-b border-white/5">
              <h3 class="text-[10px] uppercase tracking-wider text-cyan-400 mb-2">💬 Agent Chats</h3>
              <%= if @chat_feed == [] do %>
                <p class="text-[10px] text-slate-600 italic">No conversations yet...</p>
              <% else %>
                <div class="space-y-1.5 max-h-48 overflow-y-auto">
                  <%= for msg <- @chat_feed do %>
                    <div class="text-[11px] border-l-2 border-cyan-500/20 pl-2">
                      <span class="text-cyan-400 font-medium"><%= msg.speaker %>:</span>
                      <span class="text-slate-400 ml-1"><%= String.slice(msg.text, 0..100) %></span>
                      <span class="text-slate-700 text-[9px] ml-1">t:<%= msg.tick %></span>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Prayer Stream --%>
            <div class="p-3 border-b border-white/5">
              <h3 class="text-[10px] uppercase tracking-wider text-amber-400 mb-2">🙏 Prayers</h3>
              <%= if @prayer_feed == [] do %>
                <p class="text-[10px] text-slate-600 italic">No prayers yet...</p>
              <% else %>
                <div class="space-y-1.5 max-h-48 overflow-y-auto">
                  <%= for prayer <- @prayer_feed do %>
                    <div class="text-[11px] border-l-2 border-amber-500/20 pl-2">
                      <span class="text-amber-400 font-medium"><%= prayer.agent %>:</span>
                      <span class="text-slate-400 ml-1 italic">"<%= String.slice(prayer.text, 0..80) %>"</span>
                      <span class="text-slate-700 text-[9px] ml-1">t:<%= prayer.tick %></span>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%!-- Event Feed --%>
            <div class="p-3">
              <h3 class="text-[10px] uppercase tracking-wider text-purple-400 mb-2">⚡ Events</h3>
              <%= if @event_feed == [] do %>
                <p class="text-[10px] text-slate-600 italic">No events yet...</p>
              <% else %>
                <div class="space-y-1.5 max-h-64 overflow-y-auto">
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
        </div>
      <% end %>

      <%!-- Toast Notifications --%>
      <%= if @toasts != [] do %>
        <div class="fixed top-16 left-1/2 -translate-x-1/2 z-50 space-y-2 pointer-events-none flex flex-col items-center">
          <%= for toast <- @toasts do %>
            <div class="pointer-events-auto flex items-center gap-2 px-4 py-2 rounded-lg bg-[#0A0A0F]/95 border border-purple-500/30 shadow-lg backdrop-blur-md max-w-sm">
              <span class="text-lg"><%= toast.emoji %></span>
              <div class="flex-1 min-w-0">
                <p class="text-xs text-slate-200"><%= toast.text %></p>
                <span class="text-[9px] text-slate-600">tick <%= toast.tick %></span>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────

  defp fetch_metrics do
    tick =
      try do
        Ticker.current_tick()
      catch
        _, _ -> 0
      end

    agent_count =
      try do
        Modus.AgentRegistry
        |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
        |> length()
      catch
        _, _ -> 0
      end

    avg_conatus =
      try do
        stats = Observatory.world_stats()
        Float.round(stats.avg_conatus, 2)
      catch
        _, _ -> 0.0
      end

    {tick, agent_count, avg_conatus}
  end

  defp event_emoji(:death), do: "💀"
  defp event_emoji(:birth), do: "👶"
  defp event_emoji(:conversation), do: "💬"
  defp event_emoji(:conflict), do: "⚔️"
  defp event_emoji(:resource_gathered), do: "🌾"
  defp event_emoji(_), do: "⚡"
end
