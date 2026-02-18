defmodule Modus.Mind.Cerebro.SocialNetwork do
  @moduledoc "Agent relationship graph stored in ETS"

  @table :social_network

  @type_thresholds [
    {:close_friend, 0.8},
    {:friend, 0.5},
    {:acquaintance, 0.2},
    {:stranger, 0.0}
  ]

  @event_deltas %{
    conversation_joy: 0.08,
    conversation_neutral: 0.04,
    conversation_sad: 0.06,
    shared_danger: 0.10
  }

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  def get_relationship(id1, id2) do
    key = canonical_key(id1, id2)

    case :ets.lookup(@table, key) do
      [{^key, rel}] -> rel
      [] -> nil
    end
  end

  def update_relationship(id1, id2, event_type) do
    key = canonical_key(id1, id2)
    delta = Map.get(@event_deltas, event_type, 0.04)

    rel =
      case :ets.lookup(@table, key) do
        [{^key, existing}] -> existing
        [] -> %{strength: 0.0, type: :stranger, last_interaction: 0, convo_count: 0}
      end

    new_strength = min(rel.strength + delta, 1.0)
    new_type = classify_type(new_strength)

    updated = %{
      rel
      | strength: new_strength,
        type: new_type,
        last_interaction: System.monotonic_time(:millisecond),
        convo_count: rel.convo_count + 1
    }

    :ets.insert(@table, {key, updated})
    :ok
  end

  def get_friends(agent_id, min_strength \\ 0.3) do
    # Match all entries where agent_id is part of the key
    :ets.tab2list(@table)
    |> Enum.filter(fn {{a, b}, rel} ->
      (a == agent_id or b == agent_id) and rel.strength >= min_strength
    end)
    |> Enum.map(fn {{a, b}, rel} ->
      other = if a == agent_id, do: b, else: a
      %{id: other, strength: rel.strength, type: rel.type}
    end)
    |> Enum.sort_by(& &1.strength, :desc)
  end

  def decay_all(amount \\ 0.002) do
    :ets.tab2list(@table)
    |> Enum.each(fn {key, rel} ->
      new_strength = max(rel.strength - amount, 0.0)

      if new_strength < 0.01 do
        :ets.delete(@table, key)
      else
        new_type = classify_type(new_strength)
        :ets.insert(@table, {key, %{rel | strength: new_strength, type: new_type}})
      end
    end)

    :ok
  end

  defp canonical_key(id1, id2) when id1 <= id2, do: {id1, id2}
  defp canonical_key(id1, id2), do: {id2, id1}

  defp classify_type(strength) do
    Enum.find_value(@type_thresholds, :stranger, fn {type, threshold} ->
      if strength >= threshold, do: type
    end)
  end
end
