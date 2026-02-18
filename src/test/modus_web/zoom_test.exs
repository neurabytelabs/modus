defmodule ModusWeb.ZoomTest do
  @moduledoc """
  v4.8.0 Conspectus — Harita yakınlaştırma seviyeleri testleri.
  Zoom level hesaplamaları, viewport ve render culling testleri.
  """
  use ExUnit.Case, async: true

  describe "zoom level hesaplamaları" do
    test "zoom seviyeleri doğru ölçek değerlerine sahip" do
      presets = %{world: 0.35, region: 0.8, local: 1.5}
      assert presets.world < presets.region
      assert presets.region < presets.local
      assert presets.world > 0
      assert presets.local <= 5.0
    end

    test "ölçekten zoom seviyesi belirleme" do
      # world: <= 0.5, region: <= 1.0, local: > 1.0
      assert zoom_level(0.3) == "world"
      assert zoom_level(0.5) == "world"
      assert zoom_level(0.7) == "region"
      assert zoom_level(1.0) == "region"
      assert zoom_level(1.5) == "local"
      assert zoom_level(3.0) == "local"
    end

    test "viewport hesaplaması — görünür tile aralığı" do
      # cam_x=0, cam_y=0, screen 800x600, scale 1.0, tile_size 16
      {min_x, min_y, max_x, max_y} = visible_tiles(0, 0, 800, 600, 1.0, 16, 100, 100)
      assert min_x >= 0
      assert min_y >= 0
      assert max_x <= 99
      assert max_y <= 99
      assert max_x > min_x
      assert max_y > min_y
    end

    test "world zoom ile daha geniş alan görünür" do
      # scale 0.35 (world) vs scale 1.5 (local)
      {_, _, max_x_world, max_y_world} = visible_tiles(0, 0, 800, 600, 0.35, 16, 100, 100)
      {_, _, max_x_local, max_y_local} = visible_tiles(0, 0, 800, 600, 1.5, 16, 100, 100)
      # World zoom daha fazla tile gösterir
      assert (max_x_world - 0) > (max_x_local - 0)
      assert (max_y_world - 0) > (max_y_local - 0)
    end

    test "fog of war — keşfedilmemiş tile'lar karanlık" do
      explored = MapSet.new(["5,5", "5,6", "6,5", "6,6"])
      assert fog_alpha("5,5", explored) == 0.0
      assert fog_alpha("10,10", explored) == 0.85
    end

    test "fog of war — agent çevresindeki tile'lar keşfedilir" do
      agent_pos = {10, 10}
      view_range = 5
      explored = explore_around(agent_pos, view_range, 100, 100)
      # Agent konumunda keşfedilmiş olmalı
      assert MapSet.member?(explored, "10,10")
      # Menzil içinde
      assert MapSet.member?(explored, "12,12")
      # Menzil dışında
      refute MapSet.member?(explored, "20,20")
    end

    test "zoom level cycle sırası doğru" do
      assert cycle_zoom("local") == "region"
      assert cycle_zoom("region") == "world"
      assert cycle_zoom("world") == "local"
    end
  end

  # Helper fonksiyonlar (JS renderer mantığının Elixir karşılığı)

  defp zoom_level(scale) when scale <= 0.5, do: "world"
  defp zoom_level(scale) when scale <= 1.0, do: "region"
  defp zoom_level(_scale), do: "local"

  defp visible_tiles(cam_x, cam_y, screen_w, screen_h, scale, tile_size, grid_w, grid_h) do
    margin = 2
    vp_w = screen_w / scale
    vp_h = screen_h / scale
    min_x = max(0, floor(cam_x / tile_size) - margin)
    min_y = max(0, floor(cam_y / tile_size) - margin)
    max_x = min(grid_w - 1, ceil((cam_x + vp_w) / tile_size) + margin)
    max_y = min(grid_h - 1, ceil((cam_y + vp_h) / tile_size) + margin)
    {min_x, min_y, max_x, max_y}
  end

  defp fog_alpha(tile_key, explored) do
    if MapSet.member?(explored, tile_key), do: 0.0, else: 0.85
  end

  defp explore_around({ax, ay}, range, grid_w, grid_h) do
    for dx <- -range..range,
        dy <- -range..range,
        ex = ax + dx,
        ey = ay + dy,
        ex >= 0 and ex < grid_w,
        ey >= 0 and ey < grid_h,
        into: MapSet.new() do
      "#{ex},#{ey}"
    end
  end

  defp cycle_zoom("local"), do: "region"
  defp cycle_zoom("region"), do: "world"
  defp cycle_zoom("world"), do: "local"
end
