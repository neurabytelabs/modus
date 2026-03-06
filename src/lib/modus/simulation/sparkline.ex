defmodule Modus.Simulation.Sparkline do
  @moduledoc """
  Sparkline — SVG sparkline generator from Observatory stats_history.

  Renders compact inline SVG sparkline charts for population, happiness,
  conatus, and other metrics. Used in dashboard components.

  ## v7.5 — Initial implementation
  """

  @default_width 120
  @default_height 30
  @default_stroke "#7C3AED"
  @default_fill "rgba(124, 58, 237, 0.1)"

  @type sparkline_opts :: [
          width: pos_integer(),
          height: pos_integer(),
          stroke: String.t(),
          fill: String.t(),
          show_dots: boolean(),
          show_area: boolean()
        ]

  @doc """
  Generate an SVG sparkline string from a list of numeric values.

  ## Options
  - `:width` — SVG width in px (default #{@default_width})
  - `:height` — SVG height in px (default #{@default_height})
  - `:stroke` — Line color (default "#{@default_stroke}")
  - `:fill` — Area fill color (default with opacity)
  - `:show_dots` — Show dots at data points (default false)
  - `:show_area` — Fill area under curve (default true)
  """
  @spec render([number()], sparkline_opts()) :: String.t()
  def render(data, opts \\ [])
  def render([], _opts), do: ""

  def render([_single], opts) do
    w = Keyword.get(opts, :width, @default_width)
    h = Keyword.get(opts, :height, @default_height)
    stroke = Keyword.get(opts, :stroke, @default_stroke)

    ~s(<svg width="#{w}" height="#{h}" xmlns="http://www.w3.org/2000/svg"><line x1="0" y1="#{div(h, 2)}" x2="#{w}" y2="#{div(h, 2)}" stroke="#{stroke}" stroke-width="1.5"/></svg>)
  end

  def render(values, opts) when is_list(values) do
    w = Keyword.get(opts, :width, @default_width)
    h = Keyword.get(opts, :height, @default_height)
    stroke = Keyword.get(opts, :stroke, @default_stroke)
    fill = Keyword.get(opts, :fill, @default_fill)
    show_dots = Keyword.get(opts, :show_dots, false)
    show_area = Keyword.get(opts, :show_area, true)

    padding = 2
    draw_w = w - padding * 2
    draw_h = h - padding * 2

    min_val = Enum.min(values)
    max_val = Enum.max(values)
    range = if max_val == min_val, do: 1.0, else: max_val - min_val

    count = length(values)
    step = if count > 1, do: draw_w / (count - 1), else: draw_w

    points =
      values
      |> Enum.with_index()
      |> Enum.map(fn {val, i} ->
        x = padding + i * step
        y = padding + draw_h - (val - min_val) / range * draw_h
        {Float.round(x * 1.0, 1), Float.round(y * 1.0, 1)}
      end)

    path_d =
      points
      |> Enum.with_index()
      |> Enum.map(fn {{x, y}, 0} -> "M#{x},#{y}"
                     {{x, y}, _i} -> "L#{x},#{y}" end)
      |> Enum.join(" ")

    area_d =
      if show_area do
        {first_x, _} = hd(points)
        {last_x, _} = List.last(points)
        bottom = h - padding
        "#{path_d} L#{last_x},#{bottom} L#{first_x},#{bottom} Z"
      else
        ""
      end

    dots_svg =
      if show_dots do
        points
        |> Enum.map(fn {x, y} ->
          ~s(<circle cx="#{x}" cy="#{y}" r="1.5" fill="#{stroke}"/>)
        end)
        |> Enum.join()
      else
        ""
      end

    area_svg = if show_area, do: ~s(<path d="#{area_d}" fill="#{fill}" stroke="none"/>), else: ""

    ~s(<svg width="#{w}" height="#{h}" xmlns="http://www.w3.org/2000/svg">#{area_svg}<path d="#{path_d}" fill="none" stroke="#{stroke}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>#{dots_svg}</svg>)
  end

  @doc """
  Generate sparklines for all Observatory metrics from stats_history.
  Returns a map of metric_name => SVG string.
  """
  @spec from_stats_history(sparkline_opts()) :: %{String.t() => String.t()}
  def from_stats_history(opts \\ []) do
    history = Modus.Simulation.Observatory.stats_history()

    if history == [] do
      %{}
    else
      # History is newest-first, reverse for chronological sparkline
      history = Enum.reverse(history)

      metrics = [
        {"population", fn s -> Map.get(s, :population, 0) end, "#22c55e"},
        {"avg_happiness", fn s -> Map.get(s, :avg_happiness, 0.0) end, "#eab308"},
        {"avg_conatus", fn s -> Map.get(s, :avg_conatus, 0.0) end, "#7C3AED"},
        {"buildings", fn s -> Map.get(s, :buildings, 0) end, "#06B6D4"},
        {"trades", fn s -> Map.get(s, :trades, 0) end, "#f97316"}
      ]

      for {name, extractor, color} <- metrics, into: %{} do
        values = Enum.map(history, extractor)
        svg = render(values, Keyword.merge(opts, [stroke: color]))
        {name, svg}
      end
    end
  end
end
