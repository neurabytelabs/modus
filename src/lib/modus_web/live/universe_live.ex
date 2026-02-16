defmodule ModusWeb.UniverseLive do
  @moduledoc """
  Main LiveView — MODUS universe dashboard with 2D renderer.
  """
  use ModusWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "MODUS",
       status: :paused,
       tick: 0,
       agent_count: 0
     )}
  end

  @impl true
  def handle_event("world_state", params, socket) do
    {:noreply,
     assign(socket,
       tick: params["tick"] || 0,
       agent_count: params["agent_count"] || 0,
       status: String.to_existing_atom(params["status"] || "paused")
     )}
  end

  @impl true
  def handle_event("tick_update", params, socket) do
    {:noreply,
     assign(socket,
       tick: params["tick"] || socket.assigns.tick,
       agent_count: params["agent_count"] || socket.assigns.agent_count
     )}
  end

  @impl true
  def handle_event("status_change", params, socket) do
    status = String.to_existing_atom(params["status"] || "paused")
    {:noreply, assign(socket, status: status)}
  end

  @impl true
  def handle_event("start", _params, socket) do
    {:noreply, push_event(socket, "start_simulation", %{})}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    {:noreply, push_event(socket, "pause_simulation", %{})}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply, push_event(socket, "reset_simulation", %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-[#050508] text-slate-200 font-mono overflow-hidden">
      <%!-- Top Bar --%>
      <nav class="border-b border-white/5 bg-[#0A0A0F]/80 backdrop-blur-md px-6 h-14 flex items-center justify-between shrink-0">
        <div class="flex items-center gap-3">
          <span class="text-xl font-bold tracking-tighter">
            MODUS<span class="text-purple-400">_</span>
          </span>
          <span class="text-xs text-slate-600">v0.1.0</span>
        </div>

        <div class="flex items-center gap-6">
          <%!-- Stats --%>
          <div class="flex items-center gap-4 text-xs text-slate-500">
            <div class="flex items-center gap-1.5">
              <span class="text-slate-600">TICK</span>
              <span class="text-cyan-400 font-bold tabular-nums"><%= @tick %></span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-slate-600">POP</span>
              <span class="text-purple-400 font-bold tabular-nums"><%= @agent_count %></span>
            </div>
            <span class={"px-2 py-0.5 rounded text-[10px] uppercase tracking-wider #{status_color(@status)}"}>
              <%= @status %>
            </span>
          </div>

          <%!-- Controls --%>
          <div class="flex items-center gap-2">
            <%= if @status == :running do %>
              <button phx-click="pause" class="ctrl-btn">
                ⏸ Pause
              </button>
            <% else %>
              <button phx-click="start" class="ctrl-btn ctrl-btn-primary">
                ▶ Start
              </button>
            <% end %>
            <button phx-click="reset" class="ctrl-btn">
              ↻ Reset
            </button>
          </div>
        </div>
      </nav>

      <%!-- Canvas Container --%>
      <div id="world-canvas" phx-hook="WorldCanvas" class="flex-1 relative">
        <%!-- Pixi.js canvas is injected here by the hook --%>
        <div class="absolute bottom-4 left-4 text-[10px] text-slate-600 pointer-events-none">
          Drag to pan · Scroll to zoom
        </div>
      </div>
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
      .ctrl-btn:hover {
        background: rgba(255, 255, 255, 0.1);
        color: #e2e8f0;
      }
      .ctrl-btn-primary {
        background: rgba(168, 85, 247, 0.15);
        border-color: rgba(168, 85, 247, 0.3);
        color: #c084fc;
      }
      .ctrl-btn-primary:hover {
        background: rgba(168, 85, 247, 0.25);
        color: #e9d5ff;
      }
    </style>
    """
  end

  defp status_color(:ready), do: "bg-green-500/20 text-green-400"
  defp status_color(:running), do: "bg-cyan-500/20 text-cyan-400"
  defp status_color(:paused), do: "bg-amber-500/20 text-amber-400"
  defp status_color(_), do: "bg-slate-500/20 text-slate-400"
end
