defmodule Modus.Simulation.EnvironmentTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.Environment

  setup do
    # Start PubSub if not already started
    start_supervised!({Phoenix.PubSub, name: Modus.PubSub})
    start_supervised!(Environment)
    :ok
  end

  test "starts in day mode at tick 0" do
    state = Environment.get_state()
    assert state.time_of_day == :day
    assert state.cycle_tick == 0
    assert state.cycle_progress == 0.0
  end

  test "time_of_day returns :day initially" do
    assert Environment.time_of_day() == :day
  end

  test "is_night? returns false during day" do
    refute Environment.is_night?()
  end

  test "transitions to night after 250 ticks" do
    # Send 250 ticks
    for i <- 1..250 do
      send(Process.whereis(Environment), {:tick, i})
    end
    # Give it time to process
    :timer.sleep(50)

    assert Environment.time_of_day() == :night
    assert Environment.is_night?()
  end

  test "cycle wraps at 500 ticks back to day" do
    # Send 500 ticks
    for i <- 1..500 do
      send(Process.whereis(Environment), {:tick, i})
    end
    :timer.sleep(50)

    assert Environment.time_of_day() == :day
    state = Environment.get_state()
    assert state.cycle_tick == 0
  end

  test "cycle_progress advances correctly" do
    # Send 125 ticks (should be at 25% = 0.25)
    for i <- 1..125 do
      send(Process.whereis(Environment), {:tick, i})
    end
    :timer.sleep(50)

    progress = Environment.cycle_progress()
    assert progress == 0.25
  end
end
