defmodule Modus.Protocol.Persuasion do
  @moduledoc """
  Persuasion mechanic — skill-based influence system.
  Agents can persuade each other based on personality traits,
  relationship strength, and conversation context.
  """

  alias Modus.Mind.Cerebro.SocialNetwork
  require Logger

  @table :persuasion_log
  @max_log 50

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end
    :ok
  end

  @doc """
  Attempt persuasion. Returns {:ok, :persuaded} or {:ok, :resisted}.
  
  Persuasion score is based on:
  - Persuader's extraversion + agreeableness (charisma)
  - Target's neuroticism (susceptibility) vs conscientiousness (resistance)
  - Relationship trust level
  - Topic relevance to target's needs
  """
  @spec attempt(map(), map(), atom()) :: {:ok, :persuaded | :resisted, float()}
  def attempt(persuader, target, topic \\ :general) do
    init()

    # Persuader's charisma score
    p_personality = persuader.personality || %{}
    charisma = (
      ensure_float(Map.get(p_personality, :extraversion, 0.5)) * 0.4 +
      ensure_float(Map.get(p_personality, :agreeableness, 0.5)) * 0.3 +
      ensure_float(Map.get(p_personality, :openness, 0.5)) * 0.3
    )

    # Target's resistance score
    t_personality = target.personality || %{}
    resistance = (
      ensure_float(Map.get(t_personality, :conscientiousness, 0.5)) * 0.5 +
      (1.0 - ensure_float(Map.get(t_personality, :neuroticism, 0.5))) * 0.3 +
      (1.0 - ensure_float(Map.get(t_personality, :agreeableness, 0.5))) * 0.2
    )

    # Trust bonus from relationship
    relationship = SocialNetwork.get_relationship(persuader.id, target.id)
    trust_bonus = if relationship do
      ensure_float(relationship.strength) * 0.3
    else
      0.0
    end

    # Topic relevance bonus
    topic_bonus = topic_relevance(target, topic)

    # Final persuasion score (0.0 - 1.0)
    persuasion_score = min(1.0, charisma + trust_bonus + topic_bonus)
    resistance_score = resistance

    # Random factor (±0.15)
    random_factor = (:rand.uniform() - 0.5) * 0.3

    success? = persuasion_score + random_factor > resistance_score
    result = if success?, do: :persuaded, else: :resisted

    # Log the attempt
    log_entry = %{
      persuader_id: persuader.id,
      persuader_name: persuader.name,
      target_id: target.id,
      target_name: target.name,
      topic: topic,
      score: Float.round(persuasion_score, 3),
      resistance: Float.round(resistance_score, 3),
      result: result,
      timestamp: System.system_time(:second)
    }
    store_log(persuader.id, log_entry)

    Logger.debug("[Persuasion] #{persuader.name} -> #{target.name} (#{topic}): #{result} (#{Float.round(persuasion_score, 2)} vs #{Float.round(resistance_score, 2)})")

    {:ok, result, persuasion_score}
  end

  @doc "Get persuasion history for an agent."
  @spec get_log(String.t()) :: [map()]
  def get_log(agent_id) do
    init()
    case :ets.lookup(@table, agent_id) do
      [{_, log}] -> log
      [] -> []
    end
  end

  # ── Helpers ────────────────────────────────────────────

  defp topic_relevance(target, topic) do
    needs = target.needs || %{}
    case topic do
      :trade -> if ensure_float(Map.get(needs, :hunger, 50)) > 60, do: 0.2, else: 0.05
      :alliance -> if ensure_float(Map.get(needs, :social, 50)) > 60, do: 0.2, else: 0.05
      :warning -> 0.15  # warnings are always somewhat relevant
      :gossip -> 0.05
      _ -> 0.0
    end
  end

  defp store_log(agent_id, entry) do
    existing = get_log(agent_id)
    updated = Enum.take([entry | existing], @max_log)
    :ets.insert(@table, {agent_id, updated})
  end
end
