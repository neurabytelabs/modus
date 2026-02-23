defmodule Modus.Llm.SmartCacheTest do
  use ExUnit.Case, async: false

  alias Modus.Llm.SmartCache

  setup do
    SmartCache.init()
    SmartCache.clear()
    :ok
  end

  test "put and get returns cached response" do
    agent = %{personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5}}
    SmartCache.put(agent, :joy, "greeting", "Hello there!")
    assert {:ok, "Hello there!"} = SmartCache.get(agent, :joy, "greeting")
  end

  test "get returns :miss for uncached key" do
    agent = %{personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5}}
    assert :miss = SmartCache.get(agent, :sadness, "farewell")
  end

  test "hit_rate starts at 0.0" do
    assert SmartCache.hit_rate() == 0.0
  end

  test "hit_rate tracks hits and misses" do
    agent = %{personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5}}
    SmartCache.put(agent, :joy, "greeting", "Hello!")

    # 1 hit
    SmartCache.get(agent, :joy, "greeting")
    # 1 miss
    SmartCache.get(agent, :sadness, "other")

    assert SmartCache.hit_rate() == 0.5
  end

  test "clear resets cache and stats" do
    agent = %{personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5}}
    SmartCache.put(agent, :joy, "greeting", "Hello!")
    SmartCache.clear()
    assert :miss = SmartCache.get(agent, :joy, "greeting")
    assert SmartCache.hit_rate() == 0.0
  end
end
