defmodule Modus.Simulation.LifecycleTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.Lifecycle

  setup do
    Lifecycle.init()
    :ok
  end

  test "init creates stats table" do
    assert %{births: 0, deaths: 0} = Lifecycle.stats()
  end

  test "record_death increments death count" do
    Lifecycle.record_death()
    Lifecycle.record_death()
    stats = Lifecycle.stats()
    assert stats.deaths >= 2
  end

  test "stats returns birth and death counts" do
    stats = Lifecycle.stats()
    assert is_integer(stats.births)
    assert is_integer(stats.deaths)
  end
end
