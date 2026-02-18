defmodule ModusWeb.DashboardCharts do
  @moduledoc """
  Speculum — Data Visualization Dashboard.
  6 pure SVG chart components for MODUS analytics.
  v3.6.0
  """
  use Phoenix.Component

  @doc "Population line graph — SVG polyline from last 100 ticks."
  attr :data, :list, default: []
  def population_chart(assigns) do
    points = build_polyline_points(assigns.data, 340, 140)
    assigns = assign(assigns, :points, points)

    ~H"""
    <svg viewBox="0 0 360 160" class="w-full h-full">
      <defs>
        <linearGradient id="pop-grad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#06b6d4" stop-opacity="0.3"/>
          <stop offset="100%" stop-color="#06b6d4" stop-opacity="0.0"/>
        </linearGradient>
      </defs>
      <!-- Grid lines -->
      <line :for={y <- [40, 80, 120]} x1="10" y1={y} x2="350" y2={y} stroke="#1e293b" stroke-width="0.5"/>
      <!-- Area fill -->
      <%= if @points != "" do %>
        <polygon points={"10,140 #{@points} 350,140"} fill="url(#pop-grad)"/>
        <polyline points={@points} fill="none" stroke="#06b6d4" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <% end %>
      <text x="180" y="155" text-anchor="middle" fill="#64748b" font-size="9">Population (last 100 ticks)</text>
    </svg>
    """
  end

  @doc "Resource stacked area chart — wood/stone/food/herbs."
  attr :data, :map, default: %{}
  def resource_chart(assigns) do
    resources = [
      {:wood, "#06b6d4"},
      {:stone, "#8b5cf6"},
      {:food, "#22c55e"},
      {:herbs, "#f59e0b"}
    ]
    total = resources |> Enum.map(fn {k, _} -> Map.get(assigns.data, k, 0) end) |> Enum.sum() |> max(1)
    bars = resources
      |> Enum.reduce({[], 0}, fn {k, color}, {acc, offset} ->
        val = Map.get(assigns.data, k, 0)
        width = val / total * 300
        {[{k, color, offset, width} | acc], offset + width}
      end)
      |> elem(0)
      |> Enum.reverse()
    assigns = assign(assigns, :bars, bars)

    ~H"""
    <svg viewBox="0 0 360 160" class="w-full h-full">
      <rect :for={{key, color, offset, width} <- @bars}
        x={20 + offset} y="30" width={width} height="80" fill={color} rx="2" opacity="0.8"/>
      <!-- Legend -->
      <g :for={{item, i} <- Enum.with_index([{"Wood", "#06b6d4"}, {"Stone", "#8b5cf6"}, {"Food", "#22c55e"}, {"Herbs", "#f59e0b"}])}>
        <rect x={20 + i * 85} y="125" width="10" height="10" fill={elem(item, 1)} rx="2"/>
        <text x={35 + i * 85} y="134" fill="#94a3b8" font-size="9"><%= elem(item, 0) %></text>
      </g>
      <text x="180" y="155" text-anchor="middle" fill="#64748b" font-size="9">Resource Distribution</text>
    </svg>
    """
  end

  @doc "Relationship network — force-directed SVG circles + lines."
  attr :nodes, :list, default: []
  attr :edges, :list, default: []
  def relationship_chart(assigns) do
    positioned = position_nodes(assigns.nodes, 180, 75, 55)
    assigns = assign(assigns, :positioned, positioned)

    ~H"""
    <svg viewBox="0 0 360 160" class="w-full h-full">
      <!-- Edges -->
      <line :for={edge <- @edges}
        x1={node_x(@positioned, edge.from)} y1={node_y(@positioned, edge.from)}
        x2={node_x(@positioned, edge.to)} y2={node_y(@positioned, edge.to)}
        stroke={if edge.type == :friend, do: "#06b6d4", else: "#8b5cf6"}
        stroke-width={max(0.5, edge.strength * 3)} opacity="0.5"/>
      <!-- Nodes -->
      <g :for={node <- @positioned}>
        <circle cx={node.x} cy={node.y} r="8" fill="#0f172a" stroke="#06b6d4" stroke-width="1.5"/>
        <text x={node.x} y={node.y + 3} text-anchor="middle" fill="#e2e8f0" font-size="6">
          <%= String.first(node.name || "?") %>
        </text>
      </g>
      <text x="180" y="155" text-anchor="middle" fill="#64748b" font-size="9">Relationships</text>
    </svg>
    """
  end

  @doc "Mood distribution — horizontal bar chart."
  attr :data, :list, default: []
  def mood_chart(assigns) do
    moods = if assigns.data == [], do: default_moods(), else: assigns.data
    max_val = moods |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) |> max(1)
    bars = moods |> Enum.with_index() |> Enum.map(fn {{label, val, color}, i} ->
      %{label: label, val: val, color: color, width: val / max_val * 220, y: 15 + i * 28}
    end)
    assigns = assign(assigns, :bars, bars)

    ~H"""
    <svg viewBox="0 0 360 160" class="w-full h-full">
      <g :for={bar <- @bars}>
        <text x="15" y={bar.y + 14} fill="#94a3b8" font-size="9"><%= bar.label %></text>
        <rect x="80" y={bar.y + 3} width={bar.width} height="16" fill={bar.color} rx="3" opacity="0.8"/>
        <text x={85 + bar.width} y={bar.y + 15} fill="#e2e8f0" font-size="8"><%= bar.val %></text>
      </g>
      <text x="180" y="155" text-anchor="middle" fill="#64748b" font-size="9">Mood Distribution</text>
    </svg>
    """
  end

  @doc "Trade volume — bar chart."
  attr :data, :list, default: []
  def trade_chart(assigns) do
    max_val = if assigns.data == [], do: 1,
      else: assigns.data |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) |> max(1)
    bar_width = if assigns.data == [], do: 20, else: min(30, 300 / max(length(assigns.data), 1))
    bars = assigns.data |> Enum.with_index() |> Enum.map(fn {{_tick, vol}, i} ->
      h = vol / max_val * 110
      %{x: 20 + i * bar_width, height: h, y: 130 - h, vol: vol}
    end)
    assigns = assign(assigns, :bars, bars) |> assign(:bar_width, bar_width)

    ~H"""
    <svg viewBox="0 0 360 160" class="w-full h-full">
      <line x1="20" y1="130" x2="340" y2="130" stroke="#1e293b" stroke-width="0.5"/>
      <rect :for={bar <- @bars}
        x={bar.x} y={bar.y} width={max(2, @bar_width - 3)} height={bar.height}
        fill="#8b5cf6" rx="2" opacity="0.8"/>
      <text x="180" y="155" text-anchor="middle" fill="#64748b" font-size="9">Trade Volume</text>
    </svg>
    """
  end

  @doc "Ecosystem balance — donut/gauge chart for predator/prey ratio."
  attr :predators, :integer, default: 0
  attr :prey, :integer, default: 0
  attr :agents, :integer, default: 0
  def ecosystem_chart(assigns) do
    total = max(assigns.predators + assigns.prey + assigns.agents, 1)
    # SVG arc calculations - circumference of r=50 circle
    circ = 2 * :math.pi() * 50
    pred_pct = assigns.predators / total
    prey_pct = assigns.prey / total
    agent_pct = assigns.agents / total
    assigns = assigns
      |> assign(:circ, circ)
      |> assign(:pred_dash, "#{pred_pct * circ} #{circ}")
      |> assign(:prey_offset, pred_pct * circ)
      |> assign(:prey_dash, "#{prey_pct * circ} #{circ}")
      |> assign(:agent_offset, (pred_pct + prey_pct) * circ)
      |> assign(:agent_dash, "#{agent_pct * circ} #{circ}")

    ~H"""
    <svg viewBox="0 0 360 160" class="w-full h-full">
      <g transform="translate(130, 75)">
        <circle r="50" fill="none" stroke="#1e293b" stroke-width="14"/>
        <circle r="50" fill="none" stroke="#ef4444" stroke-width="14"
          stroke-dasharray={@pred_dash} stroke-dashoffset="0" transform="rotate(-90)"/>
        <circle r="50" fill="none" stroke="#22c55e" stroke-width="14"
          stroke-dasharray={@prey_dash} stroke-dashoffset={-@prey_offset} transform="rotate(-90)"/>
        <circle r="50" fill="none" stroke="#06b6d4" stroke-width="14"
          stroke-dasharray={@agent_dash} stroke-dashoffset={-@agent_offset} transform="rotate(-90)"/>
      </g>
      <!-- Legend -->
      <rect x="230" y="35" width="10" height="10" fill="#ef4444" rx="2"/>
      <text x="245" y="44" fill="#94a3b8" font-size="9">Predators (<%= @predators %>)</text>
      <rect x="230" y="55" width="10" height="10" fill="#22c55e" rx="2"/>
      <text x="245" y="64" fill="#94a3b8" font-size="9">Prey (<%= @prey %>)</text>
      <rect x="230" y="75" width="10" height="10" fill="#06b6d4" rx="2"/>
      <text x="245" y="84" fill="#94a3b8" font-size="9">Agents (<%= @agents %>)</text>
      <text x="180" y="155" text-anchor="middle" fill="#64748b" font-size="9">Ecosystem Balance</text>
    </svg>
    """
  end

  # ── Helpers ──────────────────────────────────────────────

  defp build_polyline_points([], _w, _h), do: ""
  defp build_polyline_points(data, width, height) do
    data = Enum.take(data, -100)
    max_val = data |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) |> max(1)
    len = max(length(data) - 1, 1)
    data
    |> Enum.with_index()
    |> Enum.map(fn {{_tick, pop}, i} ->
      x = 10 + i / len * width
      y = height - (pop / max_val * (height - 20))
      "#{Float.round(x * 1.0, 1)},#{Float.round(y * 1.0, 1)}"
    end)
    |> Enum.join(" ")
  end

  defp position_nodes([], _cx, _cy, _r), do: []
  defp position_nodes(nodes, cx, cy, radius) do
    len = max(length(nodes), 1)
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, i} ->
      angle = 2 * :math.pi() * i / len
      Map.merge(node, %{
        x: Float.round(cx + radius * :math.cos(angle), 1),
        y: Float.round(cy + radius * :math.sin(angle), 1)
      })
    end)
  end

  defp node_x(positioned, id) do
    case Enum.find(positioned, fn n -> n.id == id end) do
      nil -> 180
      n -> n.x
    end
  end

  defp node_y(positioned, id) do
    case Enum.find(positioned, fn n -> n.id == id end) do
      nil -> 75
      n -> n.y
    end
  end

  defp default_moods do
    [{"Happy", 5, "#22c55e"}, {"Calm", 3, "#06b6d4"}, {"Anxious", 2, "#f59e0b"}, {"Sad", 1, "#8b5cf6"}]
  end
end
