defmodule Modus.Simulation.ObservatoryETSTest do
  use ExUnit.Case, async: true

  @moduledoc "Tests for Observatory ETS-based read path (v7.2)."

  alias Modus.Simulation.Observatory

  test "init/0 creates the ETS table" do
    # Table already created by Application.start, verify it exists
    assert :ets.info(:observatory_stats) != :undefined
  end

  test "update_cache/0 populates the ETS table" do
    Observatory.update_cache()
    [{:world_stats, stats}] = :ets.lookup(:observatory_stats, :world_stats)
    assert is_map(stats)
    assert Map.has_key?(stats, :population)
    assert Map.has_key?(stats, :avg_happiness)
    assert Map.has_key?(stats, :avg_conatus)
  end

  test "world_stats/0 returns cached data after update" do
    Observatory.update_cache()
    stats = Observatory.world_stats()
    assert is_map(stats)
    assert is_number(stats.population)
    assert is_float(stats.avg_conatus)
  end

  test "world_stats/0 falls back to compute when cache empty" do
    # Clear cache
    :ets.delete(:observatory_stats, :world_stats)
    stats = Observatory.world_stats()
    assert is_map(stats)
    assert Map.has_key?(stats, :population)
  end

  test "compute_world_stats/0 returns valid stats" do
    stats = Observatory.compute_world_stats()
    assert stats.population >= 0
    assert stats.buildings >= 0
    assert is_float(stats.avg_happiness)
  end
end
