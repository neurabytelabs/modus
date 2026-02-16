defmodule Modus.Simulation.EconomyTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.Economy

  setup do
    Economy.init()
    :ok
  end

  test "init creates stats table" do
    stats = Economy.stats()
    assert stats.trades == 0
    assert stats.total_transferred == +0.0
  end

  test "stats returns trade count" do
    stats = Economy.stats()
    assert is_integer(stats.trades)
    assert is_float(stats.total_transferred)
  end

  test "transfer_resource returns error when too far" do
    assert {:error, :too_far} = Economy.transfer_resource({0, 0}, {50, 50}, :food, 1.0)
  end
end
