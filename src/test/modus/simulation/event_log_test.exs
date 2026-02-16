defmodule Modus.Simulation.EventLogTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.EventLog

  setup do
    # EventLog is started by application, but reset state
    :ok
  end

  test "logs and retrieves events" do
    EventLog.log(:birth, 1, ["agent_1"], %{name: "Ada"})
    EventLog.log(:conversation, 2, ["agent_1", "agent_2"], %{topic: "weather"})

    # Small delay for cast processing
    Process.sleep(50)

    events = EventLog.recent()
    assert length(events) >= 2

    latest = hd(events)
    assert latest.type == :conversation
    assert "agent_1" in latest.agents
  end

  test "filters by agent_id" do
    EventLog.log(:death, 10, ["agent_99"], %{cause: "hunger"})
    Process.sleep(50)

    events = EventLog.recent(agent_id: "agent_99")
    assert Enum.all?(events, fn e -> "agent_99" in e.agents end)
  end

  test "respects max 100 events" do
    for i <- 1..110 do
      EventLog.log(:resource_gathered, i, ["agent_x"], %{})
    end

    Process.sleep(100)

    events = EventLog.recent(limit: 200)
    assert length(events) <= 100
  end
end
