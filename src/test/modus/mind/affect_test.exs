defmodule Modus.Mind.AffectTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.Affect

  @default_personality %{
    openness: 0.5,
    conscientiousness: 0.5,
    extraversion: 0.5,
    agreeableness: 0.5,
    neuroticism: 0.5
  }

  describe "transition/4" do
    test "action_success with high conatus → joy" do
      {affect, _reason} = Affect.transition(:neutral, :action_success, @default_personality, 0.8)
      assert affect == :joy
    end

    test "action_failure with low conatus → fear" do
      {affect, _reason} = Affect.transition(:neutral, :action_failure, @default_personality, 0.2)
      assert affect == :fear
    end

    test "action_failure with normal conatus → sadness" do
      {affect, _reason} = Affect.transition(:neutral, :action_failure, @default_personality, 0.5)
      assert affect == :sadness
    end

    test "social_positive with high extraversion → joy" do
      personality = %{@default_personality | extraversion: 0.8}
      {affect, _reason} = Affect.transition(:neutral, :social_positive, personality, 0.5)
      assert affect == :joy
    end

    test "hunger_critical → fear" do
      {affect, _reason} = Affect.transition(:neutral, :hunger_critical, @default_personality, 0.5)
      assert affect == :fear
    end

    test "rest → neutral" do
      {affect, _reason} = Affect.transition(:joy, :rest, @default_personality, 0.5)
      assert affect == :neutral
    end

    test "social_negative → sadness" do
      {affect, _reason} = Affect.transition(:joy, :social_negative, @default_personality, 0.5)
      assert affect == :sadness
    end

    test "explore with high openness → desire" do
      personality = %{@default_personality | openness: 0.8}
      {affect, _reason} = Affect.transition(:neutral, :action_success_minor, personality, 0.5)
      assert affect == :desire
    end
  end

  describe "conatus_modifier/1" do
    test "joy is positive" do
      assert Affect.conatus_modifier(:joy) > 0
    end

    test "sadness is negative" do
      assert Affect.conatus_modifier(:sadness) < 0
    end

    test "neutral is zero" do
      assert Affect.conatus_modifier(:neutral) == 0.0
    end
  end
end
