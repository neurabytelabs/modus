defmodule Modus.Simulation.ResourceTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.Resource

  # ── Creation ────────────────────────────────────────────────

  test "new/3 creates a resource with ecosystem fields" do
    r = Resource.new(:food, {10, 20}, 15.0)
    assert r.type == :food
    assert r.position == {10, 20}
    assert r.amount == 15.0
    assert r.max_amount == 15.0
    assert r.fertility == 1.0
    assert r.harvest_count == 0
    assert r.barren_until == nil
    assert r.density == :dense
    assert is_binary(r.id)
  end

  test "new/3 defaults amount to 10.0" do
    r = Resource.new(:wood, {0, 0})
    assert r.amount == 10.0
  end

  # ── Gathering ───────────────────────────────────────────────

  test "gather/2 takes requested amount" do
    r = Resource.new(:wood, {0, 0}, 10.0)
    {taken, updated} = Resource.gather(r, 3.0)
    assert taken == 3.0
    assert updated.amount == 7.0
    assert updated.harvest_count == 1
  end

  test "gather/2 caps at available amount" do
    r = Resource.new(:stone, {0, 0}, 2.0)
    {taken, updated} = Resource.gather(r, 5.0)
    assert taken == 2.0
    assert updated.amount == 0.0
  end

  test "gather/2 sets depleted_at when amount reaches 0" do
    r = Resource.new(:food, {0, 0}, 1.0)
    {_taken, updated} = Resource.gather(r, 1.0)
    assert updated.depleted_at != nil
  end

  test "gather/2 returns 0 for barren resources" do
    r = %{Resource.new(:food, {0, 0}, 5.0) | barren_until: 999_999_999}
    {taken, _updated} = Resource.gather(r, 3.0)
    assert taken == 0.0
  end

  test "gather/2 drains fertility for crops" do
    r = Resource.new(:crops, {0, 0}, 20.0)
    {_taken, updated} = Resource.gather(r, 1.0)
    assert updated.fertility < 1.0
    assert_in_delta updated.fertility, 0.92, 0.01
  end

  test "gather/2 does not drain fertility for non-crops" do
    r = Resource.new(:wood, {0, 0}, 20.0)
    {_taken, updated} = Resource.gather(r, 1.0)
    assert updated.fertility == 1.0
  end

  # ── Depletion ───────────────────────────────────────────────

  test "depleted?/1" do
    r = Resource.new(:water, {0, 0}, 0.0)
    assert Resource.depleted?(r)

    r2 = Resource.new(:water, {0, 0}, 1.0)
    refute Resource.depleted?(r2)
  end

  test "barren?/1 returns false when barren_until is nil" do
    r = Resource.new(:food, {0, 0}, 5.0)
    refute Resource.barren?(r)
  end

  # ── Density ─────────────────────────────────────────────────

  test "density_level/2 classifies correctly" do
    assert Resource.density_level(10.0, 10.0) == :dense
    assert Resource.density_level(5.0, 10.0) == :moderate
    assert Resource.density_level(1.5, 10.0) == :sparse
    assert Resource.density_level(0.0, 10.0) == :depleted
  end

  test "density_emoji/1 returns emoji for each level" do
    assert Resource.density_emoji(:dense) == "🟢"
    assert Resource.density_emoji(:moderate) == "🟡"
    assert Resource.density_emoji(:sparse) == "🟠"
    assert Resource.density_emoji(:depleted) == "🔴"
  end

  # ── Respawn rates ───────────────────────────────────────────

  test "respawn_rate/2 returns biome-specific rate" do
    assert Resource.respawn_rate(:forest, :wood) == 80
    assert Resource.respawn_rate(:ocean, :fish) == 70
    assert Resource.respawn_rate(:mountain, :gold) == 600
  end

  test "respawn_rate/2 falls back to default for unknown biome" do
    assert Resource.respawn_rate(:unknown, :food) == 200
  end

  # ── Carrying capacity ──────────────────────────────────────

  test "carrying_capacity/1 returns biome capacity" do
    assert Resource.carrying_capacity(:forest) == 30.0
    assert Resource.carrying_capacity(:desert) == 5.0
  end

  # ── Season modifier ────────────────────────────────────────

  test "season_modifier/1 returns correct values" do
    assert Resource.season_modifier(:spring) == 1.5
    assert Resource.season_modifier(:winter) == 0.5
    assert Resource.season_modifier(:summer) == 1.0
  end

  # ── Respawn ─────────────────────────────────────────────────

  test "respawn/2 restores resource scaled by fertility and season" do
    r = %{Resource.new(:food, {0, 0}, 10.0) | amount: 0.0, fertility: 0.5}
    restored = Resource.respawn(r, :winter)
    # 10.0 * 0.5 fertility * 0.5 winter = 2.5
    assert_in_delta restored.amount, 2.5, 0.01
    assert restored.depleted_at == nil
    assert restored.harvest_count == 0
  end

  test "respawn/2 with full fertility in spring" do
    r = %{Resource.new(:wood, {0, 0}, 20.0) | amount: 0.0}
    restored = Resource.respawn(r, :spring)
    # 20.0 * 1.0 * 1.5 = 30.0, capped at max 20.0
    assert restored.amount == 20.0
  end

  # ── Fertility ───────────────────────────────────────────────

  test "restore_fertility/1 increases fertility" do
    r = %{Resource.new(:crops, {0, 0}, 10.0) | fertility: 0.5}
    updated = Resource.restore_fertility(r)
    assert updated.fertility > 0.5
    assert_in_delta updated.fertility, 0.51, 0.01
  end

  test "restore_fertility/1 caps at 1.0" do
    r = %{Resource.new(:crops, {0, 0}, 10.0) | fertility: 0.999}
    updated = Resource.restore_fertility(r)
    assert updated.fertility == 1.0
  end

  # ── Rare resources ──────────────────────────────────────────

  test "discover_rare/2 returns :nothing for non-special biomes" do
    assert Resource.discover_rare({5, 5}, :plains) == :nothing
    assert Resource.discover_rare({5, 5}, :forest) == :nothing
  end

  # ── Terrain resources ───────────────────────────────────────

  test "terrain_resources/1 returns types per terrain" do
    assert :wood in Resource.terrain_resources(:forest)
    assert :fish in Resource.terrain_resources(:water)
    assert Resource.terrain_resources(:desert) == []
  end

  # ── Legacy compat ───────────────────────────────────────────

  test "respawn_ticks/0 returns default" do
    assert Resource.respawn_ticks() == 200
  end
end
