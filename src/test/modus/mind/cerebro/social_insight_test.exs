defmodule Modus.Mind.Cerebro.SocialInsightTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Cerebro.{SocialInsight, SocialNetwork}

  setup do
    SocialNetwork.init()
    :ok
  end

  describe "describe_relationships/1" do
    test "returns no-friends text when no relationships" do
      result = SocialInsight.describe_relationships("nonexistent-agent")
      assert result == "Henüz kimseyi tanımıyorsun."
    end
  end

  describe "describe_relationship/3" do
    test "returns not-met text for unknown pair" do
      result = SocialInsight.describe_relationship("a1", "a2", "Deniz")
      assert result == "Deniz ile daha önce tanışmadınız."
    end

    test "returns relationship info after interaction" do
      SocialNetwork.update_relationship("a1", "a2", :conversation_neutral)
      result = SocialInsight.describe_relationship("a1", "a2", "Deniz")
      assert result =~ "Deniz"
      assert result =~ "güç:"
    end
  end
end
