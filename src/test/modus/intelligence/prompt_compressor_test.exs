defmodule Modus.Intelligence.PromptCompressorTest do
  use ExUnit.Case, async: true

  alias Modus.Intelligence.PromptCompressor

  @agent %{
    id: "agent_1",
    name: "Maya",
    position: {10, 20},
    occupation: :farmer,
    needs: %{hunger: 45.5, social: 60.0, rest: 80.0},
    personality: %{openness: 0.7, conscientiousness: 0.6, extraversion: 0.5, agreeableness: 0.8, neuroticism: 0.3},
    current_action: :explore
  }

  test "compress_batch produces shorter prompt than original" do
    agents = [@agent]
    compressed = PromptCompressor.compress_batch(agents, 100)
    assert String.length(compressed) < 500
    assert compressed =~ "agent_1"
    assert compressed =~ "Maya"
  end

  test "compress_agent produces compact one-liner" do
    result = PromptCompressor.compress_agent(@agent)
    assert is_binary(result)
    assert result =~ "agent_1"
    assert result =~ "Maya"
    # Should be compact
    assert String.length(result) < 200
  end

  test "compress_conversation is compact" do
    agent_b = %{@agent | id: "agent_2", name: "Kai", occupation: :builder}
    result = PromptCompressor.compress_conversation(@agent, agent_b)
    assert result =~ "Maya"
    assert result =~ "Kai"
    assert String.length(result) < 300
  end
end
