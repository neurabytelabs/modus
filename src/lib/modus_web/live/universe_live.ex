defmodule ModusWeb.UniverseLive do
  @moduledoc """
  Main LiveView — MODUS universe dashboard.
  Will render the 2D world, agent list, and controls.
  """
  use ModusWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "MODUS",
       status: :ready,
       tick: 0,
       agent_count: 0
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#050508] text-slate-200 font-mono">
      <!-- Header -->
      <nav class="border-b border-white/5 bg-[#0A0A0F]/80 backdrop-blur-md px-6 h-16 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span class="text-xl font-bold tracking-tighter">
            MODUS<span class="text-purple-400">_</span>
          </span>
          <span class="text-xs text-slate-600">v0.1.0</span>
        </div>
        <div class="flex items-center gap-4 text-xs text-slate-500">
          <span>TICK: <%= @tick %></span>
          <span>AGENTS: <%= @agent_count %></span>
          <span class={"px-2 py-0.5 rounded #{status_color(@status)}"}>
            <%= String.upcase(to_string(@status)) %>
          </span>
        </div>
      </nav>

      <!-- Main Content -->
      <main class="flex items-center justify-center" style="height: calc(100vh - 4rem)">
        <div class="text-center space-y-6">
          <div class="text-6xl mb-4">🌌</div>
          <h1 class="text-4xl font-bold">
            MODUS <span class="text-purple-400">is running</span>
          </h1>
          <p class="text-slate-500 max-w-md mx-auto">
            Universe simulation platform. Every agent thinks.
            Every universe evolves. Your rules.
          </p>
          <div class="flex gap-4 justify-center mt-8">
            <div class="glass-panel px-6 py-4 rounded-xl text-center">
              <div class="text-2xl font-bold text-cyan-400"><%= @agent_count %></div>
              <div class="text-xs text-slate-500 mt-1">AGENTS</div>
            </div>
            <div class="glass-panel px-6 py-4 rounded-xl text-center">
              <div class="text-2xl font-bold text-purple-400"><%= @tick %></div>
              <div class="text-xs text-slate-500 mt-1">TICKS</div>
            </div>
            <div class="glass-panel px-6 py-4 rounded-xl text-center">
              <div class="text-2xl font-bold text-amber-400">M4</div>
              <div class="text-xs text-slate-500 mt-1">RUNTIME</div>
            </div>
          </div>
          <p class="text-xs text-slate-700 mt-8 italic">
            "Every universe is a modus — a mode of infinite substance."
          </p>
        </div>
      </main>
    </div>

    <style>
      .glass-panel {
        background: rgba(255, 255, 255, 0.03);
        backdrop-filter: blur(10px);
        border: 1px solid rgba(255, 255, 255, 0.05);
      }
    </style>
    """
  end

  defp status_color(:ready), do: "bg-green-500/20 text-green-400"
  defp status_color(:running), do: "bg-cyan-500/20 text-cyan-400"
  defp status_color(:paused), do: "bg-amber-500/20 text-amber-400"
  defp status_color(_), do: "bg-slate-500/20 text-slate-400"
end
