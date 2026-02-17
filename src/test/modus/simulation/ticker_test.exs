defmodule Modus.Simulation.TickerTest do
  use ExUnit.Case, async: false
  alias Modus.Simulation.Ticker

  setup do
    pid = case Process.whereis(Ticker) do
      nil ->
        start_supervised!({Ticker, [interval_ms: 50]})
      existing_pid ->
        # Use existing, ensure paused for isolation
        try do Ticker.pause(existing_pid) catch _, _ -> :ok end
        existing_pid
    end
    on_exit(fn -> try do Ticker.pause(pid) catch _, _ -> :ok end end)
    %{pid: pid}
  end

  test "starts in :paused state", %{pid: pid} do
    status = Ticker.status(pid)
    assert status.state == :paused
    assert is_integer(status.tick)
  end

  test "run transitions to :running", %{pid: pid} do
    :ok = Ticker.run(pid)
    assert %{state: :running} = Ticker.status(pid)
  end

  test "pause transitions back to :paused", %{pid: pid} do
    :ok = Ticker.run(pid)
    :ok = Ticker.pause(pid)
    assert %{state: :paused} = Ticker.status(pid)
  end

  test "ticks increment after run", %{pid: pid} do
    Ticker.subscribe()
    :ok = Ticker.run(pid)

    # Wait for at least one tick broadcast
    assert_receive {:tick, n}, 200
    assert n >= 1
    :ok = Ticker.pause(pid)
  end

  test "pausing stops tick increments", %{pid: pid} do
    :ok = Ticker.run(pid)
    Process.sleep(80)
    :ok = Ticker.pause(pid)
    tick_after_pause = Ticker.current_tick(pid)
    Process.sleep(120)
    assert Ticker.current_tick(pid) == tick_after_pause
  end

  test "current_tick returns the tick number", %{pid: pid} do
    assert Ticker.current_tick(pid) in [0, 1]
  end
end
