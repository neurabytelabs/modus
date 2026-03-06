defmodule Modus.Protocol.PersonalityPromptBuilderTest do
  use ExUnit.Case, async: true

  alias Modus.Protocol.PersonalityPromptBuilder

  @base_personality %{
    openness: 0.5,
    conscientiousness: 0.5,
    extraversion: 0.5,
    agreeableness: 0.5,
    neuroticism: 0.5
  }

  describe "build/3" do
    test "returns a non-empty string for any valid input" do
      result = PersonalityPromptBuilder.build(@base_personality, :neutral, 0.5)
      assert is_binary(result)
    end

    test "includes affect directive for joy" do
      result = PersonalityPromptBuilder.build(@base_personality, :joy, 0.5)
      assert result =~ "joyful"
      assert result =~ "enthusiastic"
    end

    test "includes affect directive for sadness" do
      result = PersonalityPromptBuilder.build(@base_personality, :sadness, 0.5)
      assert result =~ "sad"
      assert result =~ "hesitant"
    end

    test "includes affect directive for desire" do
      result = PersonalityPromptBuilder.build(@base_personality, :desire, 0.5)
      assert result =~ "persuasive"
    end

    test "includes affect directive for fear" do
      result = PersonalityPromptBuilder.build(@base_personality, :fear, 0.5)
      assert result =~ "afraid"
    end

    test "low energy adds exhaustion modifier" do
      result = PersonalityPromptBuilder.build(@base_personality, :neutral, 0.1)
      assert result =~ "exhausted"
    end

    test "high energy adds vitality modifier" do
      result = PersonalityPromptBuilder.build(@base_personality, :neutral, 0.9)
      assert result =~ "vitality"
    end
  end

  describe "build_trait_directives/1" do
    test "high openness includes metaphors" do
      p = %{@base_personality | openness: 0.8}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "metaphor"
    end

    test "low openness includes plain language" do
      p = %{@base_personality | openness: 0.2}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "plain"
    end

    test "high extraversion includes talkative" do
      p = %{@base_personality | extraversion: 0.8}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "talkative"
    end

    test "low extraversion includes brief" do
      p = %{@base_personality | extraversion: 0.2}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "brief"
    end

    test "high neuroticism includes anxiety" do
      p = %{@base_personality | neuroticism: 0.8}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "anxiety"
    end

    test "low neuroticism includes calm" do
      p = %{@base_personality | neuroticism: 0.2}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "calm"
    end

    test "high agreeableness includes warm" do
      p = %{@base_personality | agreeableness: 0.8}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "warm"
    end

    test "high conscientiousness includes precise" do
      p = %{@base_personality | conscientiousness: 0.8}
      directives = PersonalityPromptBuilder.build_trait_directives(p)
      joined = Enum.join(directives, " ")
      assert joined =~ "precise"
    end

    test "middle-range traits return fewer directives" do
      directives = PersonalityPromptBuilder.build_trait_directives(@base_personality)
      # Only neuroticism > 0.5 triggers a directive at mid-range
      assert length(directives) <= 2
    end
  end

  describe "build_combined_directive/2" do
    test "high neuroticism + fear = panic" do
      p = %{@base_personality | neuroticism: 0.8}
      result = PersonalityPromptBuilder.build_combined_directive(p, :fear)
      assert result =~ "spiraling"
    end

    test "high extraversion + joy = buzzing" do
      p = %{@base_personality | extraversion: 0.8}
      result = PersonalityPromptBuilder.build_combined_directive(p, :joy)
      assert result =~ "BUZZING"
    end

    test "low extraversion + sadness = withdrawn" do
      p = %{@base_personality | extraversion: 0.2}
      result = PersonalityPromptBuilder.build_combined_directive(p, :sadness)
      assert result =~ "quiet"
    end

    test "high openness + desire = visionary" do
      p = %{@base_personality | openness: 0.8}
      result = PersonalityPromptBuilder.build_combined_directive(p, :desire)
      assert result =~ "vivid"
    end

    test "neutral combination returns nil" do
      result = PersonalityPromptBuilder.build_combined_directive(@base_personality, :neutral)
      assert is_nil(result)
    end
  end

  describe "build_affect_directive/2" do
    test "neutral affect returns nil" do
      assert is_nil(PersonalityPromptBuilder.build_affect_directive(:neutral, 0.5))
    end

    test "joy affect returns directive" do
      result = PersonalityPromptBuilder.build_affect_directive(:joy, 0.5)
      assert result =~ "joyful"
    end

    test "fear + low energy combines both" do
      result = PersonalityPromptBuilder.build_affect_directive(:fear, 0.1)
      assert result =~ "afraid"
      assert result =~ "exhausted"
    end
  end

  describe "build_conscious/4" do
    test "returns speech style when context_map is empty" do
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :joy, 0.5, %{})
      assert result =~ "joyful"
    end

    test "includes memories section" do
      ctx = %{memories: ["Met a traveler at the river", "Found berries in the forest"]}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      assert result =~ "MEMORIES:"
      assert result =~ "Met a traveler"
      assert result =~ "Found berries"
    end

    test "includes relationships section" do
      ctx = %{relationships: [%{name: "Ada", type: :friend, sentiment: 0.8}]}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      assert result =~ "RELATIONSHIPS:"
      assert result =~ "Ada"
      assert result =~ "warmly"
    end

    test "includes goals section with progress" do
      ctx = %{goals: [%{description: "Build a shelter", progress: 0.6}]}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      assert result =~ "GOALS:"
      assert result =~ "Build a shelter"
      assert result =~ "60%"
    end

    test "combines all sections" do
      ctx = %{
        memories: ["Saw a sunset"],
        relationships: [%{name: "Bob", type: :rival, sentiment: -0.7}],
        goals: [%{description: "Find water", progress: 0.3}]
      }
      result = PersonalityPromptBuilder.build_conscious(
        %{@base_personality | openness: 0.8}, :desire, 0.9, ctx
      )
      assert result =~ "MEMORIES:"
      assert result =~ "RELATIONSHIPS:"
      assert result =~ "GOALS:"
      assert result =~ "hostile"
      assert result =~ "30%"
      assert result =~ "vitality"
    end

    test "negative sentiment shows uneasy" do
      ctx = %{relationships: [%{name: "Eve", type: :stranger, sentiment: -0.3}]}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      assert result =~ "uneasy"
    end

    test "neutral sentiment shows neutral" do
      ctx = %{relationships: [%{name: "Zed", type: :acquaintance, sentiment: 0.0}]}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      assert result =~ "neutral about them"
    end

    test "empty lists produce no section headers" do
      ctx = %{memories: [], relationships: [], goals: []}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      refute result =~ "MEMORIES:"
      refute result =~ "RELATIONSHIPS:"
      refute result =~ "GOALS:"
    end

    test "limits memories to 10" do
      mems = Enum.map(1..15, &("Memory #{&1}"))
      ctx = %{memories: mems}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      assert result =~ "Memory 10"
      refute result =~ "Memory 11"
    end

    test "limits goals to 5" do
      goals = Enum.map(1..8, &(%{description: "Goal #{&1}", progress: 0.1}))
      ctx = %{goals: goals}
      result = PersonalityPromptBuilder.build_conscious(@base_personality, :neutral, 0.5, ctx)
      assert result =~ "Goal 5"
      refute result =~ "Goal 6"
    end
  end

end
