defmodule Modus.Protocol.RunePromptEngineTest do
  use ExUnit.Case, async: true

  alias Modus.Protocol.RunePromptEngine

  @test_agent %{
    name: "Elara",
    occupation: "herbalist",
    personality: %{
      openness: 0.8,
      conscientiousness: 0.6,
      extraversion: 0.4,
      agreeableness: 0.7,
      neuroticism: 0.3
    }
  }

  @test_perception %{
    affect_state: :joy,
    conatus_energy: 0.7,
    terrain: :forest,
    current_action: :gathering
  }

  setup do
    RunePromptEngine.init()
    :ok
  end

  # ── wrap/2 ─────────────────────────────────────────────

  describe "wrap/2" do
    test "returns {prompt, metadata} tuple" do
      {prompt, meta} = RunePromptEngine.wrap("Hello world")
      assert is_binary(prompt)
      assert is_map(meta)
      assert Map.has_key?(meta, :layer_count)
      assert Map.has_key?(meta, :active_layers)
    end

    test "includes raw prompt in output" do
      {prompt, _meta} = RunePromptEngine.wrap("Tell me about the forest")
      assert prompt =~ "Tell me about the forest"
    end

    test "with no context, includes minimal layers" do
      {_prompt, meta} = RunePromptEngine.wrap("Hi")
      # Only L2 intent, L3 governance, L4 cognitive(?), L6 QA, L7 output should be present
      assert meta.layer_count >= 1
    end

    test "with full context, includes all 8 layers" do
      ctx = %{
        agent: @test_agent,
        perception: @test_perception,
        social: "Elara is friends with Kai",
        intent: :chat,
        capabilities: [:explore, :gather, :talk, :rest],
        output_format: :dialogue
      }

      {prompt, meta} = RunePromptEngine.wrap("How are you?", ctx)
      assert meta.layer_count == 8
      assert prompt =~ "System Core"
      assert prompt =~ "Context"
      assert prompt =~ "Intent"
      assert prompt =~ "Governance"
      assert prompt =~ "Cognitive"
      assert prompt =~ "Capabilities"
      assert prompt =~ "Quality Assurance"
      assert prompt =~ "Output Meta"
    end

    test "L0 includes agent name and role" do
      ctx = %{agent: @test_agent}
      {prompt, _} = RunePromptEngine.wrap("Hi", ctx)
      assert prompt =~ "Elara"
      assert prompt =~ "herbalist"
    end

    test "L2 changes with intent" do
      {prompt_chat, _} = RunePromptEngine.wrap("Hi", %{intent: :chat})
      assert prompt_chat =~ "conversation"

      {prompt_decide, _} = RunePromptEngine.wrap("Hi", %{intent: :decide})
      assert prompt_decide =~ "decision"

      {prompt_pray, _} = RunePromptEngine.wrap("Hi", %{intent: :pray})
      assert prompt_pray =~ "spiritual"
    end

    test "L3 includes governance rules" do
      {prompt, _} = RunePromptEngine.wrap("Hi", %{})
      assert prompt =~ "break character"
    end

    test "L3 uses custom world rules when provided" do
      ctx = %{world_rules: ["No violence", "Always be honest"]}
      {prompt, _} = RunePromptEngine.wrap("Hi", ctx)
      assert prompt =~ "No violence"
      assert prompt =~ "Always be honest"
    end

    test "L4 cognitive adapts to personality" do
      high_open = %{agent: %{@test_agent | personality: %{openness: 0.9, conscientiousness: 0.2, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5}}}
      {prompt, _} = RunePromptEngine.wrap("Hi", high_open)
      assert prompt =~ "divergent"

      high_consc = %{agent: %{@test_agent | personality: %{openness: 0.2, conscientiousness: 0.9, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5}}}
      {prompt, _} = RunePromptEngine.wrap("Hi", high_consc)
      assert prompt =~ "methodically"
    end

    test "L5 lists capabilities" do
      ctx = %{capabilities: [:explore, :gather, :talk]}
      {prompt, _} = RunePromptEngine.wrap("Hi", ctx)
      assert prompt =~ "explore"
      assert prompt =~ "gather"
      assert prompt =~ "talk"
    end

    test "L7 output format changes" do
      {prompt_dialogue, _} = RunePromptEngine.wrap("Hi", %{output_format: :dialogue})
      assert prompt_dialogue =~ "Natural dialogue"

      {prompt_action, _} = RunePromptEngine.wrap("Hi", %{output_format: :action})
      assert prompt_action =~ "JSON"

      {prompt_thought, _} = RunePromptEngine.wrap("Hi", %{output_format: :thought})
      assert prompt_thought =~ "monologue"
    end

    test "metadata tracks intent" do
      {_, meta} = RunePromptEngine.wrap("Hi", %{intent: :decide})
      assert meta.intent == :decide
    end

    test "metadata has timestamp" do
      {_, meta} = RunePromptEngine.wrap("Hi")
      assert is_integer(meta.timestamp)
      assert meta.timestamp > 0
    end
  end

  # ── validate_spinoza/2 ─────────────────────────────────

  describe "validate_spinoza/2" do
    test "returns all four dimensions plus total" do
      scores = RunePromptEngine.validate_spinoza("I love gathering herbs in the forest!")
      assert Map.has_key?(scores, :conatus)
      assert Map.has_key?(scores, :ratio)
      assert Map.has_key?(scores, :laetitia)
      assert Map.has_key?(scores, :natura)
      assert Map.has_key?(scores, :total)
    end

    test "all scores are between 0 and 1" do
      scores = RunePromptEngine.validate_spinoza("Test response", %{agent: @test_agent})
      assert scores.conatus >= 0.0 and scores.conatus <= 1.0
      assert scores.ratio >= 0.0 and scores.ratio <= 1.0
      assert scores.laetitia >= 0.0 and scores.laetitia <= 1.0
      assert scores.natura >= 0.0 and scores.natura <= 1.0
      assert scores.total >= 0.0 and scores.total <= 1.0
    end

    test "total is average of four dimensions" do
      scores = RunePromptEngine.validate_spinoza("A decent response with some content.")
      expected = (scores.conatus + scores.ratio + scores.laetitia + scores.natura) / 4.0
      assert_in_delta scores.total, expected, 0.001
    end

    test "empty response scores low" do
      scores = RunePromptEngine.validate_spinoza("")
      assert scores.total < 0.5
    end

    test "AI-like response penalizes natura" do
      ai_response = "As an AI, I cannot experience feelings, but I can help you."
      normal_response = "I'm feeling great today! The forest smells wonderful."

      ai_scores = RunePromptEngine.validate_spinoza(ai_response)
      normal_scores = RunePromptEngine.validate_spinoza(normal_response)

      assert ai_scores.natura < normal_scores.natura
    end

    test "response with agent context scores conatus higher with self-reference" do
      ctx = %{agent: @test_agent}
      # Response mentioning agent's role
      relevant = "I need to gather more herbs today. As a herbalist, it's my duty."
      generic = "The weather is nice."

      relevant_scores = RunePromptEngine.validate_spinoza(relevant, ctx)
      generic_scores = RunePromptEngine.validate_spinoza(generic, ctx)

      assert relevant_scores.conatus > generic_scores.conatus
    end

    test "affect-aligned response scores higher laetitia" do
      ctx = %{perception: %{affect_state: :joy}}
      joyful = "I'm so happy! This is wonderful, what a great day!"
      neutral = "The rock is gray."

      joy_scores = RunePromptEngine.validate_spinoza(joyful, ctx)
      neutral_scores = RunePromptEngine.validate_spinoza(neutral, ctx)

      assert joy_scores.laetitia > neutral_scores.laetitia
    end

    test "repetitive response scores lower ratio" do
      repetitive = "yes yes yes yes yes yes yes yes yes yes"
      varied = "I think the forest is beautiful today. The herbs are growing well near the stream."

      rep_scores = RunePromptEngine.validate_spinoza(repetitive)
      var_scores = RunePromptEngine.validate_spinoza(varied)

      assert rep_scores.ratio < var_scores.ratio
    end
  end

  # ── ETS Metrics ────────────────────────────────────────

  describe "get_metrics/0" do
    test "tracks wrap count" do
      RunePromptEngine.wrap("test 1")
      RunePromptEngine.wrap("test 2")
      RunePromptEngine.wrap("test 3")

      metrics = RunePromptEngine.get_metrics()
      assert metrics.total_wraps >= 3
    end

    test "tracks validation count" do
      RunePromptEngine.validate_spinoza("response 1")
      RunePromptEngine.validate_spinoza("response 2")

      metrics = RunePromptEngine.get_metrics()
      assert metrics.total_validations >= 2
    end

    test "tracks avg spinoza total" do
      RunePromptEngine.validate_spinoza("A decent test response with good content!")
      metrics = RunePromptEngine.get_metrics()
      assert metrics.avg_spinoza_total > 0.0
    end

    test "tracks intent distribution" do
      RunePromptEngine.wrap("a", %{intent: :chat})
      RunePromptEngine.wrap("b", %{intent: :chat})
      RunePromptEngine.wrap("c", %{intent: :decide})

      metrics = RunePromptEngine.get_metrics()
      dist = metrics.intent_distribution
      assert Map.get(dist, :chat, 0) >= 2
      assert Map.get(dist, :decide, 0) >= 1
    end
  end
end
