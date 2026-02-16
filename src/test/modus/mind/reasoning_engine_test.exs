defmodule Modus.Mind.ReasoningEngineTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.ReasoningEngine

  defp make_agent(affect_state, affect_history) do
    %{
      id: "test-agent",
      name: "Tester",
      occupation: :explorer,
      position: {10, 10},
      personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5},
      conatus_energy: 0.4,
      affect_state: affect_state,
      affect_history: affect_history,
      last_reasoning: nil
    }
  end

  test "should_reason? true for persistent sadness" do
    history = for i <- 1..5, do: %{tick: 100 - i * 10, from: :neutral, to: :sadness, reason: "test"}
    agent = make_agent(:sadness, history)
    assert ReasoningEngine.should_reason?(agent)
  end

  test "should_reason? false for joy" do
    agent = make_agent(:joy, [%{tick: 90, from: :neutral, to: :joy, reason: "happy"}])
    refute ReasoningEngine.should_reason?(agent)
  end

  test "should_reason? false for empty history" do
    agent = make_agent(:sadness, [])
    refute ReasoningEngine.should_reason?(agent)
  end

  test "build_reasoning_prompt includes agent info" do
    agent = make_agent(:sadness, [])
    prompt = ReasoningEngine.build_reasoning_prompt(agent, ["Tick 50: felt sadness after failure at (10,10)"])
    assert prompt =~ "Tester"
    assert prompt =~ "sadness"
    assert prompt =~ "Tick 50"
  end
end
