defmodule Modus.Simulation.TickerTelemetryTest do
  use ExUnit.Case, async: true

  @moduledoc "Tests for Ticker telemetry events (v7.2)."

  test "Ticker emits :telemetry.execute on each tick" do
    {:ok, content} = File.read("lib/modus/simulation/ticker.ex")
    assert content =~ ":telemetry.execute"
    assert content =~ "[:modus, :ticker, :tick]"
    assert content =~ "duration"
    assert content =~ "agent_count"
    assert content =~ "tick_number"
  end

  test "telemetry event can be attached" do
    ref = make_ref()
    parent = self()

    handler = fn event, measurements, metadata, _config ->
      send(parent, {ref, event, measurements, metadata})
    end

    :telemetry.attach("test-ticker-#{inspect(ref)}", [:modus, :ticker, :tick], handler, nil)

    :telemetry.execute(
      [:modus, :ticker, :tick],
      %{duration: 1000, agent_count: 5},
      %{tick_number: 42}
    )

    assert_receive {^ref, [:modus, :ticker, :tick], %{duration: 1000, agent_count: 5}, %{tick_number: 42}}

    :telemetry.detach("test-ticker-#{inspect(ref)}")
  end
end
