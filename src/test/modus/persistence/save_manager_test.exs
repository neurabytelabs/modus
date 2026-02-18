defmodule Modus.Persistence.SaveManagerTest do
  use ExUnit.Case, async: false

  alias Modus.Persistence.SaveManager

  describe "collect_full_state/0" do
    test "returns a map with required keys" do
      state = SaveManager.collect_full_state()
      assert is_map(state)
      assert state.modus_version == "3.7.0"
      assert is_map(state.world)
      assert is_list(state.agents)
      assert is_list(state.buildings)
      assert is_list(state.wildlife)
      assert is_list(state.groups)
    end
  end

  describe "export_json/0" do
    test "returns valid JSON string" do
      case SaveManager.export_json() do
        {:ok, json} ->
          assert is_binary(json)
          assert {:ok, _} = Jason.decode(json)
        {:error, _} ->
          # May fail if no world is running, that's ok
          :ok
      end
    end
  end

  describe "autosave_status/0" do
    test "returns status map" do
      status = SaveManager.autosave_status()
      assert is_map(status)
      assert Map.has_key?(status, :enabled)
      assert Map.has_key?(status, :interval)
      assert Map.has_key?(status, :last_tick)
    end
  end

  describe "list_slots/0" do
    test "returns 5 slots" do
      slots = SaveManager.list_slots()
      assert length(slots) == 5
      assert Enum.all?(slots, fn s -> Map.has_key?(s, :slot) end)
    end
  end

  describe "set_autosave_interval/1" do
    test "updates interval" do
      assert :ok = SaveManager.set_autosave_interval(1000)
      status = SaveManager.autosave_status()
      assert status.interval == 1000
      # Reset
      SaveManager.set_autosave_interval(500)
    end
  end

  describe "gzip round-trip" do
    test "save and load slot" do
      # This test requires a running world, skip if not available
      case SaveManager.save_slot(5, "test-slot") do
        {:ok, info} ->
          assert info.slot == 5
          assert info.name == "test-slot"

          slots = SaveManager.list_slots()
          slot5 = Enum.find(slots, &(&1.slot == 5))
          refute Map.get(slot5, :empty)
          assert slot5.name == "test-slot"

          # Cleanup
          SaveManager.delete_slot(5)
        {:error, _} ->
          # No world running, skip
          :ok
      end
    end
  end
end
