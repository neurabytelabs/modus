defmodule Modus.Simulation.ResourceTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.Resource

  test "new/3 creates a resource" do
    r = Resource.new(:food, {10, 20}, 15.0)
    assert r.type == :food
    assert r.position == {10, 20}
    assert r.amount == 15.0
    assert is_binary(r.id)
  end

  test "gather/2 takes requested amount" do
    r = Resource.new(:wood, {0, 0}, 10.0)
    {taken, updated} = Resource.gather(r, 3.0)
    assert taken == 3.0
    assert updated.amount == 7.0
  end

  test "gather/2 caps at available amount" do
    r = Resource.new(:stone, {0, 0}, 2.0)
    {taken, updated} = Resource.gather(r, 5.0)
    assert taken == 2.0
    assert updated.amount == 0.0
  end

  test "depleted?/1" do
    r = Resource.new(:water, {0, 0}, 0.0)
    assert Resource.depleted?(r)

    r2 = Resource.new(:water, {0, 0}, 1.0)
    refute Resource.depleted?(r2)
  end
end
