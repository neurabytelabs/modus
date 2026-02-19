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
end
