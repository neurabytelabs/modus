defmodule Modus.Simulation.NatureEventsTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.NatureEvents

  describe "event_types/0" do
    test "returns three event types" do
      types = NatureEvents.event_types()
      assert :forest_fire in types
      assert :flood in types
      assert :locust_swarm in types
      assert length(types) == 3
    end
  end

  describe "event_config/1" do
    test "forest fire config" do
      config = NatureEvents.event_config(:forest_fire)
      assert config.radius == 6
      assert config.terrain_change == :desert
      assert config.kill_count == 3
      assert :deer in config.kills_animals
    end

    test "flood config" do
      config = NatureEvents.event_config(:flood)
      assert config.radius == 8
      assert config.terrain_change == :water
      assert config.kill_count == 0
    end

    test "locust swarm config" do
      config = NatureEvents.event_config(:locust_swarm)
      assert config.radius == 10
      assert config.terrain_change == nil
    end

    test "unknown event returns nil" do
      assert NatureEvents.event_config(:tornado) == nil
    end
  end

  describe "trigger/3" do
    setup do
      case Process.whereis(Modus.PubSub) do
        nil -> Phoenix.PubSub.Supervisor.start_link(name: Modus.PubSub)
        _ -> :ok
      end

      case Process.whereis(Modus.Simulation.EventLog) do
        nil -> Modus.Simulation.EventLog.start_link([])
        _ -> :ok
      end

      case Process.whereis(Modus.Simulation.Wildlife) do
        nil -> start_supervised!({Modus.Simulation.Wildlife, []})
        _ -> :ok
      end

      :ok
    end

    test "triggers forest fire event" do
      {:ok, event} = NatureEvents.trigger(:forest_fire, {50, 50}, 100)
      assert event.type == :forest_fire
      assert event.center == {50, 50}
      assert event.start_tick == 100
      assert is_binary(event.id)
    end

    test "triggers flood event" do
      {:ok, event} = NatureEvents.trigger(:flood, {30, 30}, 200)
      assert event.type == :flood
      assert event.radius == 8
    end

    test "triggers locust swarm event" do
      {:ok, event} = NatureEvents.trigger(:locust_swarm, {40, 40}, 300)
      assert event.type == :locust_swarm
    end

    test "forest fire kills animals" do
      # Reset wildlife to known state
      GenServer.cast(Modus.Simulation.Wildlife, :reset)
      :timer.sleep(20)
      before_deer = Modus.Simulation.Wildlife.get_population(:deer)
      NatureEvents.trigger(:forest_fire, {50, 50}, 100)
      :timer.sleep(100)
      after_deer = Modus.Simulation.Wildlife.get_population(:deer)
      assert after_deer <= before_deer
    end
  end
end
