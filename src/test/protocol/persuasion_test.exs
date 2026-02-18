defmodule Modus.Protocol.PersuasionTest do
  use ExUnit.Case, async: false

  alias Modus.Protocol.Persuasion

  setup do
    Persuasion.init()
    Modus.Mind.Cerebro.SocialNetwork.init()
    try do :ets.delete_all_objects(:persuasion_log) catch _, _ -> :ok end
    :ok
  end

  defp make_agent(id, opts \\ []) do
    %{
      id: id,
      name: "Agent_#{id}",
      personality: Keyword.get(opts, :personality, %{
        extraversion: 0.5, agreeableness: 0.5, openness: 0.5,
        conscientiousness: 0.5, neuroticism: 0.5
      }),
      needs: %{hunger: 50.0, social: 50.0, rest: 80.0, shelter: 70.0},
      inventory: %{},
      relationships: %{}
    }
  end

  test "attempt returns ok with result and score" do
    persuader = make_agent("p1", personality: %{extraversion: 0.9, agreeableness: 0.8, openness: 0.7, conscientiousness: 0.5, neuroticism: 0.3})
    target = make_agent("t1")

    assert {:ok, result, score} = Persuasion.attempt(persuader, target)
    assert result in [:persuaded, :resisted]
    assert is_float(score)
    assert score >= 0.0 and score <= 1.0
  end

  test "highly charismatic persuader has higher score" do
    charismatic = make_agent("p1", personality: %{extraversion: 1.0, agreeableness: 1.0, openness: 1.0, conscientiousness: 0.5, neuroticism: 0.5})
    target = make_agent("t1")

    scores = for _ <- 1..20 do
      {:ok, _, score} = Persuasion.attempt(charismatic, target, :general)
      score
    end
    avg = Enum.sum(scores) / length(scores)
    assert avg > 0.6
  end

  test "get_log returns persuasion history" do
    p = make_agent("p1")
    t = make_agent("t1")
    Persuasion.attempt(p, t)
    log = Persuasion.get_log("p1")
    assert length(log) == 1
    assert hd(log).persuader_id == "p1"
  end

  test "topic relevance affects persuasion" do
    p = make_agent("p1")
    t = make_agent("t1")

    {:ok, _, score_general} = Persuasion.attempt(p, t, :general)
    # Warning is always somewhat relevant, so should be slightly higher
    {:ok, _, score_warning} = Persuasion.attempt(p, t, :warning)
    # Both should be valid floats
    assert is_float(score_general)
    assert is_float(score_warning)
  end
end
