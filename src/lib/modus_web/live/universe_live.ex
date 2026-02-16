defmodule ModusWeb.UniverseLive do
  @moduledoc """
  Main LiveView — MODUS universe dashboard with 2D renderer.
  """
  use ModusWeb, :live_view
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "MODUS",
       status: :paused,
       tick: 0,
       agent_count: 0,
       selected_agent: nil,
       chat_open: false,
       chat_messages: [],
       chat_loading: false
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
  def handle_event("select_agent", %{"agent" => agent_data}, socket) do
    {:noreply,
     assign(socket,
       selected_agent: agent_data,
       chat_messages: []
     )}
  end

  @impl true
  def handle_event("deselect_agent", _params, socket) do
    {:noreply, assign(socket, selected_agent: nil, chat_open: false, chat_messages: [])}
  end

  @impl true
  def handle_event("open_chat", _params, socket) do
    {:noreply, assign(socket, chat_open: true)}
  end

  @impl true
  def handle_event("close_chat", _params, socket) do
    {:noreply, assign(socket, chat_open: false)}
  end

  @impl true
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

  @impl true
  def handle_event("chat_response", %{"reply" => reply}, socket) do
    agent_name =
      if socket.assigns.selected_agent,
        do: socket.assigns.selected_agent["name"],
        else: "Agent"

    messages = socket.assigns.chat_messages ++ [%{role: "agent", text: reply, name: agent_name}]
    {:noreply, assign(socket, chat_messages: messages, chat_loading: false)}
  end

  @impl true
  def handle_event("agent_detail_update", %{"detail" => detail}, socket) do
    {:noreply, assign(socket, selected_agent: detail)}
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

      <%!-- Main Area --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Canvas Container --%>
        <div id="world-canvas" phx-hook="WorldCanvas" class="flex-1 relative">
          <div class="absolute bottom-4 left-4 text-[10px] text-slate-600 pointer-events-none">
            Click agent to inspect · Drag to pan · Scroll to zoom
          </div>
        </div>

        <%!-- Right Panel: Agent Detail --%>
        <%= if @selected_agent do %>
          <div class="w-80 border-l border-white/5 bg-[#0A0A0F]/90 backdrop-blur-md overflow-y-auto shrink-0">
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
                <span class={"w-2 h-2 rounded-full #{if @selected_agent["alive"], do: "bg-green-500", else: "bg-red-500"}"} />
                <%= if @selected_agent["alive"], do: "Alive", else: "Dead" %>
                · Age: <%= @selected_agent["age"] || 0 %>
                · Conatus: <%= @selected_agent["conatus"] || 0 %>
              </div>

              <%!-- Needs Bars --%>
              <div class="mb-4">
                <h3 class="text-[10px] uppercase tracking-wider text-slate-600 mb-2">Needs</h3>
                <%= if @selected_agent["needs"] do %>
                  <%= for {need, val} <- [{"hunger", @selected_agent["needs"]["hunger"]}, {"social", @selected_agent["needs"]["social"]}, {"rest", @selected_agent["needs"]["rest"]}, {"shelter", @selected_agent["needs"]["shelter"]}] do %>
                    <div class="mb-1.5">
                      <div class="flex justify-between text-[10px] mb-0.5">
                        <span class="text-slate-500 capitalize"><%= need %></span>
                        <span class="text-slate-400 tabular-nums"><%= val || 0 %></span>
                      </div>
                      <div class="h-1.5 bg-white/5 rounded-full overflow-hidden">
                        <div class={"h-full rounded-full #{need_color(need)}"} style={"width: #{min(val || 0, 100)}%"} />
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
                        <div class="h-full bg-cyan-500/60 rounded-full" style={"width: #{(val || 0) * 100}%"} />
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
                      <span class="text-cyan-400"><%= event["type"] %></span>
                      <span class="text-slate-600"> tick:<%= event["tick"] %></span>
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
      </div>

      <%!-- Chat Modal --%>
      <%= if @chat_open && @selected_agent do %>
        <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center" phx-click="close_chat">
          <div class="bg-[#0A0A0F] border border-white/10 rounded-xl w-[28rem] max-h-[32rem] flex flex-col shadow-2xl" phx-click-away="close_chat">
            <%!-- Chat Header --%>
            <div class="px-4 py-3 border-b border-white/5 flex items-center justify-between shrink-0">
              <div>
                <span class="font-bold text-slate-100"><%= @selected_agent["name"] %></span>
                <span class="text-xs text-slate-500 ml-2"><%= @selected_agent["occupation"] %></span>
              </div>
              <button phx-click="close_chat" class="text-slate-600 hover:text-slate-400">✕</button>
            </div>

            <%!-- Messages --%>
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
                  <div class="bg-white/5 px-3 py-2 rounded-lg text-sm text-slate-500 animate-pulse">
                    thinking...
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Input --%>
            <form phx-submit="send_chat" class="p-3 border-t border-white/5 shrink-0">
              <div class="flex gap-2">
                <input
                  type="text"
                  name="message"
                  placeholder={"Talk to #{@selected_agent["name"]}..."}
                  autocomplete="off"
                  class="flex-1 bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-purple-500/50"
                  phx-click={JS.dispatch("click", to: "#chat-input-stop")}
                />
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

  defp need_color("hunger"), do: "bg-orange-500"
  defp need_color("social"), do: "bg-pink-500"
  defp need_color("rest"), do: "bg-blue-500"
  defp need_color("shelter"), do: "bg-emerald-500"
  defp need_color(_), do: "bg-slate-500"

  defp status_color(:ready), do: "bg-green-500/20 text-green-400"
  defp status_color(:running), do: "bg-cyan-500/20 text-cyan-400"
  defp status_color(:paused), do: "bg-amber-500/20 text-amber-400"
  defp status_color(_), do: "bg-slate-500/20 text-slate-400"
end
