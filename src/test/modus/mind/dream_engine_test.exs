defmodule Modus.Mind.DreamEngineTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.DreamEngine
  alias Modus.Mind.DreamEngine.Dream
  alias Modus.Mind.{EpisodicMemory, AffectMemory, DreamPromptBuilder}

  setup do
    EpisodicMemory.init()
    AffectMemory.init()

    # Clean up dreams table
    if :ets.whereis(:agent_dreams) != :undefined do
      :ets.delete_all_objects(:agent_dreams)
    end

    # Ensure DreamEngine is running
    case GenServer.whereis(DreamEngine) do
      nil -> start_supervised!(DreamEngine)
      _pid -> :ok
    end

    :ok
  end

  describe "classify_dream_type/1" do
    test "low conatus + sadness = nightmare" do
      agent = %{conatus_energy: 0.2, affect: :sadness, social_bonds: []}
      assert DreamEngine.classify_dream_type(agent) == :nightmare
    end

    test "high joy = pleasant" do
      agent = %{conatus_energy: 0.8, affect: :joy, social_bonds: []}
      assert DreamEngine.classify_dream_type(agent) == :pleasant
    end

    test "strong social bonds = social dream" do
      agent = %{conatus_energy: 0.5, affect: :neutral, social_bonds: ["a1", "a2"]}
      assert DreamEngine.classify_dream_type(agent) == :social
    end

    test "low conatus without sadness = nightmare" do
      agent = %{conatus_energy: 0.1, affect: :fear, social_bonds: []}
      assert DreamEngine.classify_dream_type(agent) == :nightmare
    end

    test "defaults to pleasant for neutral agents" do
      agent = %{conatus_energy: 0.5, affect: :neutral, social_bonds: []}
      assert DreamEngine.classify_dream_type(agent) == :pleasant
    end
  end

  describe "dream/1" do
    test "generates a dream struct with fallback (no LLM)" do
      agent = %{id: "dream-test-1", name: "Dreamer", conatus_energy: 0.8, affect: :joy, social_bonds: [], personality: %{openness: 0.7}}

      # Store some memories for context
      EpisodicMemory.store("dream-test-1", :event, 10, "found food near river")
      AffectMemory.form_memory("dream-test-1", 10, {5, 5}, :neutral, :joy, "found food", 0.8)

      assert {:ok, %Dream{} = dream} = DreamEngine.dream(agent)
      assert dream.agent_id == "dream-test-1"
      assert dream.dream_type == :pleasant
      assert is_binary(dream.dream_text)
      assert String.length(dream.dream_text) > 0
      assert %DateTime{} = dream.timestamp
    end

    test "nightmare dream for low conatus + sadness" do
      agent = %{id: "dream-test-2", name: "Sufferer", conatus_energy: 0.1, affect: :sadness, social_bonds: [], personality: %{}}

      assert {:ok, %Dream{} = dream} = DreamEngine.dream(agent)
      assert dream.dream_type == :nightmare
      assert dream.dream_affect == :sadness
    end

    test "social dream for bonded agent" do
      agent = %{id: "dream-test-3", name: "Social", conatus_energy: 0.6, affect: :neutral, social_bonds: ["friend1", "friend2"], personality: %{}}

      assert {:ok, %Dream{} = dream} = DreamEngine.dream(agent)
      assert dream.dream_type == :social
    end
  end

  describe "get_dreams/2" do
    test "retrieves stored dreams" do
      agent = %{id: "dream-store-1", name: "Stored", conatus_energy: 0.5, affect: :joy, social_bonds: [], personality: %{}}

      {:ok, _} = DreamEngine.dream(agent)
      {:ok, _} = DreamEngine.dream(agent)

      dreams = DreamEngine.get_dreams("dream-store-1")
      assert length(dreams) == 2
      assert Enum.all?(dreams, fn d -> d.agent_id == "dream-store-1" end)
    end

    test "returns empty list for unknown agent" do
      assert DreamEngine.get_dreams("nonexistent") == []
    end

    test "respects limit option" do
      agent = %{id: "dream-limit-1", name: "Limited", conatus_energy: 0.5, affect: :joy, social_bonds: [], personality: %{}}

      for _ <- 1..5, do: DreamEngine.dream(agent)

      dreams = DreamEngine.get_dreams("dream-limit-1", limit: 3)
      assert length(dreams) == 3
    end
  end

  describe "DreamPromptBuilder" do
    test "builds a prompt string" do
      agent = %{name: "TestAgent", personality: %{openness: 0.8, neuroticism: 0.3}}
      prompt = DreamPromptBuilder.build(agent, [], [], :pleasant)
      assert is_binary(prompt)
      assert prompt =~ "TestAgent"
      assert prompt =~ "PLEASANT"
      assert prompt =~ "surreal"
    end

    test "handles empty personality" do
      agent = %{name: "Blank", personality: %{}}
      prompt = DreamPromptBuilder.build(agent, [], [], :nightmare)
      assert prompt =~ "unknown temperament"
      assert prompt =~ "NIGHTMARE"
    end

    test "includes episodic memories in prompt" do
      memories = [%{content: "found a river"}, %{content: "met another agent"}]
      agent = %{name: "Mem", personality: %{}}
      prompt = DreamPromptBuilder.build(agent, memories, [], :social)
      assert prompt =~ "found a river"
      assert prompt =~ "met another agent"
    end

    test "includes affect transitions" do
      affects = [%{affect_from: :neutral, affect_to: :joy, reason: "found food"}]
      agent = %{name: "Aff", personality: %{}}
      prompt = DreamPromptBuilder.build(agent, [], affects, :pleasant)
      assert prompt =~ "neutral → joy"
      assert prompt =~ "found food"
    end
  end
end
