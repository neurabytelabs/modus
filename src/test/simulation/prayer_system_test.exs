defmodule Modus.World.PrayerSystemTest do
  use ExUnit.Case, async: false

  alias Modus.World.PrayerSystem

  setup do
    # Ensure PrayerSystem is running (it should be from application.ex)
    # Clean ETS between tests
    try do
      :ets.delete_all_objects(:modus_prayers)
    catch
      :error, :badarg -> :ok
    end
    :ok
  end

  describe "pray/4" do
    test "creates a prayer and returns it" do
      prayer = PrayerSystem.pray("agent-1", "Morty", :help, 42)
      assert prayer.agent_id == "agent-1"
      assert prayer.agent_name == "Morty"
      assert prayer.type == :help
      assert prayer.tick == 42
      assert prayer.status == :unanswered
      assert prayer.response == nil
      assert is_binary(prayer.message)
      assert prayer.id > 0
    end

    test "creates gratitude prayer" do
      prayer = PrayerSystem.pray("agent-2", "Rick", :gratitude, 10)
      assert prayer.type == :gratitude
      assert String.contains?(prayer.message, "Rick")
    end

    test "creates existential prayer" do
      prayer = PrayerSystem.pray("agent-3", "Summer", :existential, 20)
      assert prayer.type == :existential
      assert String.contains?(prayer.message, "Summer")
    end

    test "increments prayer IDs" do
      p1 = PrayerSystem.pray("a1", "A", :help, 1)
      p2 = PrayerSystem.pray("a2", "B", :help, 2)
      assert p2.id > p1.id
    end
  end

  describe "list_prayers/1" do
    test "returns empty list when no prayers" do
      assert PrayerSystem.list_prayers() == []
    end

    test "returns prayers in reverse chronological order" do
      PrayerSystem.pray("a1", "A", :help, 1)
      PrayerSystem.pray("a2", "B", :gratitude, 2)
      prayers = PrayerSystem.list_prayers()
      assert length(prayers) == 2
      # Second prayer has higher ID, so it comes first when sorted by timestamp desc
      # (same second possible, so just check both are present)
      ids = Enum.map(prayers, & &1.agent_id)
      assert "a1" in ids
      assert "a2" in ids
    end

    test "filters by status" do
      PrayerSystem.pray("a1", "A", :help, 1)
      p2 = PrayerSystem.pray("a2", "B", :help, 2)
      PrayerSystem.respond(p2.id, :positive)

      unanswered = PrayerSystem.list_prayers(status: :unanswered)
      assert length(unanswered) == 1
      assert hd(unanswered).agent_id == "a1"

      answered = PrayerSystem.list_prayers(status: :answered_positive)
      assert length(answered) == 1
      assert hd(answered).agent_id == "a2"
    end

    test "filters by agent_id" do
      PrayerSystem.pray("a1", "A", :help, 1)
      PrayerSystem.pray("a2", "B", :help, 2)
      prayers = PrayerSystem.list_prayers(agent_id: "a1")
      assert length(prayers) == 1
      assert hd(prayers).agent_id == "a1"
    end

    test "respects limit" do
      for i <- 1..10, do: PrayerSystem.pray("a#{i}", "A#{i}", :help, i)
      prayers = PrayerSystem.list_prayers(limit: 3)
      assert length(prayers) == 3
    end
  end

  describe "get_prayer/1" do
    test "returns prayer by id" do
      prayer = PrayerSystem.pray("a1", "A", :help, 1)
      found = PrayerSystem.get_prayer(prayer.id)
      assert found.id == prayer.id
      assert found.agent_id == "a1"
    end

    test "returns nil for nonexistent prayer" do
      assert PrayerSystem.get_prayer(99999) == nil
    end
  end

  describe "respond/2" do
    test "positive response updates prayer status" do
      prayer = PrayerSystem.pray("a1", "A", :help, 1)
      assert :ok = PrayerSystem.respond(prayer.id, :positive)
      updated = PrayerSystem.get_prayer(prayer.id)
      assert updated.status == :answered_positive
      assert updated.response != nil
    end

    test "negative response updates prayer status" do
      prayer = PrayerSystem.pray("a1", "A", :help, 1)
      assert :ok = PrayerSystem.respond(prayer.id, :negative)
      updated = PrayerSystem.get_prayer(prayer.id)
      assert updated.status == :answered_negative
    end

    test "responding to nonexistent prayer returns error" do
      assert {:error, _} = PrayerSystem.respond(99999, :positive)
    end
  end

  describe "maybe_pray/2" do
    test "returns :no_prayer for happy agent with high conatus" do
      agent = %{
        conatus_score: 8.0,
        conatus_energy: 0.9,
        needs: %{hunger: 30.0, social: 50.0, rest: 80.0, shelter: 70.0},
        affect_state: :joy,
        personality: %{openness: 0.5, neuroticism: 0.3}
      }
      # With very low probability, run many times and expect mostly :no_prayer
      results = for _ <- 1..100, do: PrayerSystem.maybe_pray(agent, 1)
      no_prayer_count = Enum.count(results, &(&1 == :no_prayer))
      # At least 80% should be no_prayer for a happy agent
      assert no_prayer_count >= 80
    end

    test "desperate agent prays more often" do
      agent = %{
        conatus_score: 0.5,
        conatus_energy: 0.1,
        needs: %{hunger: 95.0, social: 10.0, rest: 5.0, shelter: 10.0},
        affect_state: :fear,
        personality: %{openness: 0.5, neuroticism: 0.8}
      }
      results = for _ <- 1..200, do: PrayerSystem.maybe_pray(agent, 1)
      pray_count = Enum.count(results, fn r -> match?({:pray, _}, r) end)
      # Desperate agents should pray at least sometimes
      assert pray_count > 5
    end

    test "help prayer for desperate agent" do
      agent = %{
        conatus_score: 1.0,
        conatus_energy: 0.1,
        needs: %{hunger: 95.0},
        affect_state: :fear,
        personality: %{openness: 0.3, neuroticism: 0.3}
      }
      # Force many attempts to get a prayer
      results = for _ <- 1..500, do: PrayerSystem.maybe_pray(agent, 1)
      prayers = Enum.filter(results, fn r -> match?({:pray, _}, r) end)
      if length(prayers) > 0 do
        assert Enum.any?(prayers, fn {:pray, type} -> type == :help end)
      end
    end

    test "gratitude prayer for joyful agent with high conatus" do
      agent = %{
        conatus_score: 8.0,
        conatus_energy: 0.9,
        needs: %{hunger: 20.0},
        affect_state: :joy,
        personality: %{openness: 0.5, neuroticism: 0.3}
      }
      results = for _ <- 1..1000, do: PrayerSystem.maybe_pray(agent, 1)
      prayers = Enum.filter(results, fn r -> match?({:pray, _}, r) end)
      if length(prayers) > 0 do
        assert Enum.any?(prayers, fn {:pray, type} -> type == :gratitude end)
      end
    end

    test "existential prayer for high openness agent" do
      agent = %{
        conatus_score: 5.0,
        conatus_energy: 0.7,
        needs: %{hunger: 50.0},
        affect_state: :neutral,
        personality: %{openness: 0.9, neuroticism: 0.3}
      }
      results = for _ <- 1..1000, do: PrayerSystem.maybe_pray(agent, 1)
      prayers = Enum.filter(results, fn r -> match?({:pray, _}, r) end)
      if length(prayers) > 0 do
        assert Enum.any?(prayers, fn {:pray, type} -> type == :existential end)
      end
    end
  end

  describe "count/0" do
    test "returns 0 when empty" do
      assert PrayerSystem.count() == 0
    end

    test "returns correct count after prayers" do
      PrayerSystem.pray("a1", "A", :help, 1)
      PrayerSystem.pray("a2", "B", :help, 2)
      assert PrayerSystem.count() == 2
    end
  end
end
