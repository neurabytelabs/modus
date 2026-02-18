defmodule Modus.Simulation.DivineInterventionTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.DivineIntervention

  setup do
    # Ensure DivineIntervention is started
    case GenServer.whereis(DivineIntervention) do
      nil ->
        {:ok, _pid} = DivineIntervention.start_link([])
        :ok
      _pid ->
        DivineIntervention.clear_history()
        :ok
    end
  end

  describe "available_commands/0" do
    test "returns list of commands with required fields" do
      commands = DivineIntervention.available_commands()
      assert is_list(commands)
      assert length(commands) > 0

      for cmd <- commands do
        assert Map.has_key?(cmd, :id)
        assert Map.has_key?(cmd, :category)
        assert Map.has_key?(cmd, :emoji)
        assert Map.has_key?(cmd, :label)
        assert Map.has_key?(cmd, :desc)
      end
    end

    test "has all four categories" do
      commands = DivineIntervention.available_commands()
      categories = commands |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()
      assert :event in categories
      assert :agent in categories
      assert :world in categories
      assert :chain in categories
    end

    test "has event commands" do
      commands = DivineIntervention.available_commands()
      event_cmds = Enum.filter(commands, &(&1.category == :event))
      assert length(event_cmds) >= 12
    end
  end

  describe "history/1" do
    test "starts with empty history" do
      assert DivineIntervention.history() == []
    end

    test "total_commands is a non-negative integer" do
      assert DivineIntervention.total_commands() >= 0
    end
  end

  describe "execute/2" do
    test "logs commands to history" do
      # Execute a command (may fail if WorldEvents not running, but still logs)
      DivineIntervention.execute(:earthquake, %{severity: 1})
      history = DivineIntervention.history()
      assert length(history) == 1
      assert hd(history).command == :earthquake
    end

    test "increments total_commands" do
      DivineIntervention.execute(:earthquake, %{})
      DivineIntervention.execute(:flood, %{})
      assert DivineIntervention.total_commands() >= 2
    end

    test "history entries have required fields" do
      DivineIntervention.execute(:golden_age, %{})
      [entry | _] = DivineIntervention.history()
      assert Map.has_key?(entry, :id)
      assert Map.has_key?(entry, :command)
      assert Map.has_key?(entry, :params)
      assert Map.has_key?(entry, :result)
      assert Map.has_key?(entry, :tick)
      assert Map.has_key?(entry, :timestamp)
    end

    test "history respects limit" do
      for _ <- 1..5 do
        DivineIntervention.execute(:storm, %{})
      end
      limited = DivineIntervention.history(limit: 3)
      assert length(limited) == 3
    end

    test "unknown command returns error" do
      result = DivineIntervention.execute(:nonexistent_command, %{})
      assert {:error, _} = result
    end

    test "agent commands require agent_id" do
      assert {:error, "agent_id required"} = DivineIntervention.execute(:heal_agent, %{})
      assert {:error, "agent_id required"} = DivineIntervention.execute(:boost_mood, %{})
      assert {:error, "agent_id required"} = DivineIntervention.execute(:drain_mood, %{})
      assert {:error, "agent_id required"} = DivineIntervention.execute(:max_conatus, %{})
      assert {:error, "agent_id required"} = DivineIntervention.execute(:remove_agent, %{})
    end
  end

  describe "clear_history/0" do
    test "clears all history entries" do
      DivineIntervention.execute(:storm, %{})
      assert length(DivineIntervention.history()) > 0
      DivineIntervention.clear_history()
      assert DivineIntervention.history() == []
    end
  end
end
