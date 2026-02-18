defmodule ModusWeb.DashboardChartsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ModusWeb.DashboardCharts

  describe "population_chart/1" do
    test "renders with empty data" do
      html = render_component(&DashboardCharts.population_chart/1, %{data: []})
      assert html =~ "Population"
      assert html =~ "<svg"
    end

    test "renders with sample data" do
      data = Enum.map(1..10, fn i -> {i, i * 2} end)
      html = render_component(&DashboardCharts.population_chart/1, %{data: data})
      assert html =~ "polyline"
    end
  end

  describe "resource_chart/1" do
    test "renders with resource data" do
      html =
        render_component(&DashboardCharts.resource_chart/1, %{
          data: %{wood: 10, stone: 5, food: 8, herbs: 3}
        })

      assert html =~ "Resource Distribution"
      assert html =~ "<rect"
    end

    test "renders with empty data" do
      html = render_component(&DashboardCharts.resource_chart/1, %{data: %{}})
      assert html =~ "<svg"
    end
  end

  describe "relationship_chart/1" do
    test "renders with nodes and edges" do
      nodes = [%{id: "a", name: "Alice"}, %{id: "b", name: "Bob"}]
      edges = [%{from: "a", to: "b", strength: 0.5, type: :friend}]

      html =
        render_component(&DashboardCharts.relationship_chart/1, %{nodes: nodes, edges: edges})

      assert html =~ "Relationships"
      assert html =~ "circle"
    end

    test "renders empty" do
      html = render_component(&DashboardCharts.relationship_chart/1, %{nodes: [], edges: []})
      assert html =~ "<svg"
    end
  end

  describe "mood_chart/1" do
    test "renders default moods" do
      html = render_component(&DashboardCharts.mood_chart/1, %{data: []})
      assert html =~ "Happy"
      assert html =~ "Mood Distribution"
    end

    test "renders custom moods" do
      moods = [{"Joy", 10, "#22c55e"}, {"Fear", 3, "#ef4444"}]
      html = render_component(&DashboardCharts.mood_chart/1, %{data: moods})
      assert html =~ "Joy"
    end
  end

  describe "trade_chart/1" do
    test "renders with trade data" do
      data = [{1, 5}, {2, 10}, {3, 8}]
      html = render_component(&DashboardCharts.trade_chart/1, %{data: data})
      assert html =~ "Trade Volume"
    end

    test "renders empty" do
      html = render_component(&DashboardCharts.trade_chart/1, %{data: []})
      assert html =~ "<svg"
    end
  end

  describe "ecosystem_chart/1" do
    test "renders donut chart" do
      html =
        render_component(&DashboardCharts.ecosystem_chart/1, %{predators: 5, prey: 15, agents: 10})

      assert html =~ "Ecosystem Balance"
      assert html =~ "Predators"
      assert html =~ "5"
    end

    test "renders with zeros" do
      html =
        render_component(&DashboardCharts.ecosystem_chart/1, %{predators: 0, prey: 0, agents: 0})

      assert html =~ "<svg"
    end
  end
end
