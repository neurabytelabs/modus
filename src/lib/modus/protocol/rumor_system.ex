defmodule Modus.Protocol.RumorSystem do
  @moduledoc """
  Rumor system — information spreads through the agent network but degrades.
  Like the telephone game: each retelling may alter the original info.
  Rumors have accuracy that decreases with each hop.
  """

  @table :rumors
  @max_rumors_per_agent 15
  @degradation_per_hop 0.15
  @min_accuracy 0.1

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  @doc "Create a new rumor from a direct observation."
  @spec create_rumor(String.t(), String.t(), String.t(), integer()) :: map()
  def create_rumor(originator_id, originator_name, content, tick) do
    init()
    rumor = %{
      id: "rum_#{:erlang.unique_integer([:positive])}",
      original_content: content,
      current_content: content,
      originator_id: originator_id,
      originator_name: originator_name,
      accuracy: 1.0,
      hops: 0,
      spread_chain: [originator_id],
      created_tick: tick,
      last_spread_tick: tick
    }
    store_rumor(originator_id, rumor)
    rumor
  end

  @doc "Spread a rumor from one agent to another. Content may degrade."
  @spec spread_rumor(String.t(), String.t(), String.t(), integer()) :: {:ok, map()} | {:skipped, :already_known | :too_degraded}
  def spread_rumor(from_id, to_id, rumor_id, tick) do
    init()
    from_rumors = get_rumors(from_id)
    to_rumors = get_rumors(to_id)

    case Enum.find(from_rumors, &(&1.id == rumor_id)) do
      nil ->
        {:skipped, :not_found}

      rumor ->
        # Skip if target already knows this rumor
        if Enum.any?(to_rumors, &(&1.id == rumor_id)) do
          {:skipped, :already_known}
        else
          new_accuracy = max(@min_accuracy, ensure_float(rumor.accuracy) - @degradation_per_hop)

          if new_accuracy <= @min_accuracy do
            {:skipped, :too_degraded}
          else
            # Possibly alter the content (telephone game effect)
            new_content = maybe_alter_content(rumor.current_content, new_accuracy)

            spread_rumor = %{rumor |
              current_content: new_content,
              accuracy: new_accuracy,
              hops: rumor.hops + 1,
              spread_chain: rumor.spread_chain ++ [to_id],
              last_spread_tick: tick
            }

            store_rumor(to_id, spread_rumor)
            {:ok, spread_rumor}
          end
        end
    end
  end

  @doc "Get all rumors an agent knows."
  @spec get_rumors(String.t()) :: [map()]
  def get_rumors(agent_id) do
    init()
    case :ets.lookup(@table, agent_id) do
      [{_, rumors}] -> rumors
      [] -> []
    end
  end

  @doc "Get spreadable rumors (accuracy above threshold)."
  @spec get_spreadable(String.t()) :: [map()]
  def get_spreadable(agent_id) do
    get_rumors(agent_id)
    |> Enum.filter(&(ensure_float(&1.accuracy) > 0.3))
  end

  @doc "Format rumors for LLM context."
  @spec format_for_context(String.t()) :: String.t()
  def format_for_context(agent_id) do
    rumors = get_rumors(agent_id) |> Enum.take(5)
    case rumors do
      [] -> ""
      items ->
        items
        |> Enum.map(fn r ->
          certainty = round(ensure_float(r.accuracy) * 100)
          "- Heard: \"#{r.current_content}\" [#{certainty}% reliable, #{r.hops} hops]"
        end)
        |> Enum.join("\n")
    end
  end

  # ── Content Alteration ─────────────────────────────────

  defp maybe_alter_content(content, accuracy) when accuracy > 0.7, do: content
  defp maybe_alter_content(content, accuracy) when accuracy > 0.4 do
    # Minor alterations — swap some words, add uncertainty
    alterations = [
      fn c -> String.replace(c, "saw", "might have seen", global: false) end,
      fn c -> String.replace(c, "is", "might be", global: false) end,
      fn c -> "I heard that " <> c end,
      fn c -> c <> " ...or something like that" end
    ]
    if :rand.uniform() < 0.4 do
      Enum.random(alterations).(content)
    else
      content
    end
  end
  defp maybe_alter_content(content, _accuracy) do
    # Major alterations at low accuracy
    alterations = [
      fn c -> "Someone said something about " <> String.slice(c, 0, 30) <> "..." end,
      fn c -> "There's a vague rumor about " <> String.slice(c, 0, 20) <> "..." end,
      fn c -> String.replace(c, ~r/\b\w+\b/, fn w -> if :rand.uniform() < 0.3, do: "something", else: w end) end
    ]
    Enum.random(alterations).(content)
  end

  # ── Storage ────────────────────────────────────────────

  defp store_rumor(agent_id, rumor) do
    existing = get_rumors(agent_id)
    # Replace if same rumor id, otherwise prepend
    filtered = Enum.reject(existing, &(&1.id == rumor.id))
    updated = Enum.take([rumor | filtered], @max_rumors_per_agent)
    :ets.insert(@table, {agent_id, updated})
  end
end
