defmodule Modus.Intelligence.FallbackChainTest do
  use ExUnit.Case, async: false

  alias Modus.Intelligence.{FallbackChain, LlmMetrics}

  setup do
    LlmMetrics.init()
    :ok
  end

  @agent %{
    id: "agent_1",
    name: "Maya",
    position: {10, 20},
    occupation: :farmer,
    needs: %{hunger: 75.0, social: 60.0, rest: 80.0},
    personality: %{
      openness: 0.7,
      conscientiousness: 0.6,
      extraversion: 0.5,
      agreeableness: 0.8,
      neuroticism: 0.3
    },
    current_action: :idle,
    alive?: true,
    memory: [],
    conatus_energy: 0.5,
    inventory: %{}
  }

  test "batch_decide returns decisions (will use behavior tree as fallback in test)" do
    # In test env without real LLM, should fall through to behavior tree
    result = FallbackChain.batch_decide([@agent], %{tick: 100})
    # Either :fallback or a list of decisions
    assert result == :fallback or is_list(result)
  end

  test "chat returns a response" do
    result = FallbackChain.chat(@agent, "Hello!")
    assert match?({:ok, _}, result)
  end
end
