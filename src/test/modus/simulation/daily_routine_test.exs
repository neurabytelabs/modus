defmodule Modus.Simulation.DailyRoutineTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.DailyRoutine

  defp base_agent(overrides \\ %{}) do
    Map.merge(%{
      id: "test-agent",
      name: "TestAgent",
      position: {5, 5},
      personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5},
      needs: %{hunger: 30.0, social: 50.0, rest: 50.0, shelter: 50.0},
      conatus_energy: 0.7,
      conatus_score: 5.0,
      current_action: :idle,
      alive?: true,
      memory: [],
      affect_state: :neutral
    }, overrides)
  end

  describe "nocturnal?/1" do
    test "high openness + low conscientiousness → nocturnal" do
      personality = %{openness: 0.99, conscientiousness: 0.01}
      assert DailyRoutine.nocturnal?(personality)
    end

    test "low openness + high conscientiousness → not nocturnal" do
      personality = %{openness: 0.1, conscientiousness: 0.9}
      refute DailyRoutine.nocturnal?(personality)
    end

    test "empty personality → not nocturnal" do
      refute DailyRoutine.nocturnal?(%{})
    end
  end

  describe "drain_energy/2" do
    test "drains energy based on action type" do
      agent = base_agent(%{conatus_energy: 0.5})
      result = DailyRoutine.drain_energy(agent, :moving)
      assert result.conatus_energy < 0.5
    end

    test "sleeping does not drain energy" do
      agent = base_agent(%{conatus_energy: 0.5})
      result = DailyRoutine.drain_energy(agent, :sleeping)
      # Only weather penalty, no action drain
      assert result.conatus_energy <= 0.5
    end

    test "energy never goes below 0" do
      agent = base_agent(%{conatus_energy: 0.001})
      result = DailyRoutine.drain_energy(agent, :fleeing)
      assert result.conatus_energy >= 0.0
    end

    test "handles nil conatus_energy" do
      agent = base_agent(%{conatus_energy: nil})
      result = DailyRoutine.drain_energy(agent, :idle)
      assert result.conatus_energy >= 0.0
    end
  end

  describe "restore_from_sleep/1" do
    test "restores energy" do
      agent = base_agent(%{conatus_energy: 0.3})
      result = DailyRoutine.restore_from_sleep(agent)
      assert result.conatus_energy > 0.3
    end

    test "rest need increases" do
      agent = base_agent(%{needs: %{hunger: 30.0, social: 50.0, rest: 20.0, shelter: 50.0}})
      result = DailyRoutine.restore_from_sleep(agent)
      assert result.needs.rest > 20.0
    end

    test "energy caps at 1.0" do
      agent = base_agent(%{conatus_energy: 0.999})
      result = DailyRoutine.restore_from_sleep(agent)
      assert result.conatus_energy <= 1.0
    end
  end

  describe "apply_exhaustion_penalties/1" do
    test "applies penalties when exhausted" do
      agent = base_agent(%{conatus_energy: 0.05, conatus_score: 5.0})
      result = DailyRoutine.apply_exhaustion_penalties(agent)
      assert result.conatus_score < 5.0
    end

    test "no penalties when energy is sufficient" do
      agent = base_agent(%{conatus_energy: 0.5, conatus_score: 5.0})
      result = DailyRoutine.apply_exhaustion_penalties(agent)
      assert result.conatus_score == 5.0
    end
  end

  describe "should_dream?/1" do
    test "not dreaming when not sleeping" do
      agent = base_agent(%{current_action: :moving, conatus_energy: 0.8})
      refute DailyRoutine.should_dream?(agent)
    end

    test "not dreaming when energy too low" do
      agent = base_agent(%{current_action: :sleeping, conatus_energy: 0.2})
      refute DailyRoutine.should_dream?(agent)
    end
  end

  describe "generate_dream/1" do
    test "returns a string containing agent name" do
      agent = base_agent()
      dream = DailyRoutine.generate_dream(agent)
      assert is_binary(dream)
      assert String.contains?(dream, "TestAgent")
    end
  end

  describe "process_tick/3" do
    test "drains energy during normal action" do
      agent = base_agent(%{conatus_energy: 0.7})
      result = DailyRoutine.process_tick(agent, :moving, 100)
      assert result.conatus_energy < 0.7
    end

    test "restores during sleep" do
      agent = base_agent(%{conatus_energy: 0.3, current_action: :sleeping})
      result = DailyRoutine.process_tick(agent, :sleep, 100)
      assert result.conatus_energy > 0.3
    end
  end

  describe "recommend_action/1" do
    test "exhausted agent must sleep" do
      agent = base_agent(%{conatus_energy: 0.05, current_action: :moving})
      assert {:override, :sleep, %{reason: :exhaustion}} = DailyRoutine.recommend_action(agent)
    end

    test "already sleeping exhausted agent not overridden again" do
      agent = base_agent(%{conatus_energy: 0.05, current_action: :sleeping})
      assert :no_override = DailyRoutine.recommend_action(agent)
    end
  end
end
