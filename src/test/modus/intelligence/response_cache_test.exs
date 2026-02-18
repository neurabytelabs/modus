defmodule Modus.Intelligence.ResponseCacheTest do
  use ExUnit.Case, async: false

  alias Modus.Intelligence.ResponseCache

  setup do
    # Ensure ETS table exists
    if :ets.whereis(:llm_response_cache) != :undefined do
      :ets.delete_all_objects(:llm_response_cache)
    end

    # Ensure metrics tables exist for cache hit/miss tracking
    Modus.Intelligence.LlmMetrics.init()
    :ok
  end

  test "situation_hash produces consistent hashes" do
    agent = %{
      needs: %{hunger: 45.0, social: 60.0, rest: 80.0},
      personality: %{
        openness: 0.7,
        extraversion: 0.5,
        conscientiousness: 0.6,
        agreeableness: 0.8,
        neuroticism: 0.3
      },
      occupation: :farmer
    }

    h1 = ResponseCache.situation_hash(agent)
    h2 = ResponseCache.situation_hash(agent)
    assert h1 == h2
  end

  test "situation_hash groups similar needs" do
    agent1 = %{
      needs: %{hunger: 41.0, social: 62.0, rest: 83.0},
      personality: %{
        openness: 0.7,
        extraversion: 0.5,
        conscientiousness: 0.6,
        agreeableness: 0.8,
        neuroticism: 0.3
      },
      occupation: :farmer
    }

    agent2 = %{
      needs: %{hunger: 45.0, social: 65.0, rest: 85.0},
      personality: %{
        openness: 0.7,
        extraversion: 0.5,
        conscientiousness: 0.6,
        agreeableness: 0.8,
        neuroticism: 0.3
      },
      occupation: :farmer
    }

    # Same bucket (40, 60, 80)
    assert ResponseCache.situation_hash(agent1) == ResponseCache.situation_hash(agent2)
  end

  test "put and get work with TTL" do
    hash = 12345
    ResponseCache.put(hash, {:explore, %{reason: "test"}}, 100)
    assert ResponseCache.get(hash, 150) == {:explore, %{reason: "test"}}
    # Expired (TTL = 100 ticks)
    assert ResponseCache.get(hash, 250) == nil
  end

  test "clear removes all entries" do
    ResponseCache.put(111, {:idle, %{}}, 1)
    ResponseCache.put(222, {:explore, %{}}, 1)
    ResponseCache.clear()
    assert ResponseCache.get(111, 1) == nil
    assert ResponseCache.get(222, 1) == nil
  end
end
