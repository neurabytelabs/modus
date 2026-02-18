defmodule Modus.Simulation.TradeSystem do
  @moduledoc """
  TradeSystem — Agent-to-agent barter system with personality-based value assessment.

  Agents trade resources from their inventories based on supply/demand dynamics.
  Personality traits (Big Five) influence willingness to trade and value perception.

  ## Features
  - Barter: agents exchange surplus resources for needed ones
  - Value assessment: personality-driven (agreeableness, conscientiousness)
  - Market building bonus: trades near a market get +20% value
  - Trade history: tracked in ETS
  - Supply/demand: abundant items lose value, scarce items gain value
  - Events logged to EventLog
  """

  require Logger

  @table :modus_trade_system
  @history_table :modus_trade_history
  @trade_radius 3
  @max_history 500
  @market_bonus 0.2
  @base_values %{wood: 1.0, stone: 1.5, food: 2.0, herbs: 2.5, iron: 3.0, fish: 1.8, water: 1.0}

  # ── Init ──────────────────────────────────────────────────

  @doc "Initialize ETS tables for trade system."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@history_table) == :undefined do
      :ets.new(@history_table, [:ordered_set, :public, :named_table, read_concurrency: true])
    end

    :ets.insert(@table, {:stats, %{total_trades: 0, total_value: 0.0}})
    :ets.insert(@table, {:supply, %{}})
    :ok
  end

  # ── Public API ────────────────────────────────────────────

  @doc """
  Propose a trade between two agents.

  Returns {:ok, trade_result} if both agree, {:error, reason} otherwise.
  """
  @spec propose_trade(map(), map(), atom(), float(), atom(), float(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def propose_trade(agent_a, agent_b, offer_resource, offer_amount, request_resource, request_amount, tick) do
    with :ok <- validate_proximity(agent_a.position, agent_b.position),
         :ok <- validate_inventory(agent_a, offer_resource, offer_amount),
         :ok <- validate_inventory(agent_b, request_resource, request_amount),
         true <- willing_to_trade?(agent_a, agent_b, offer_resource, offer_amount, request_resource, request_amount) do
      execute_trade(agent_a, agent_b, offer_resource, offer_amount, request_resource, request_amount, tick)
    else
      false -> {:error, :trade_rejected}
      error -> error
    end
  end

  @doc "Find best trade opportunity for an agent given nearby agents."
  @spec find_trade_opportunity(map(), [map()]) :: {:ok, map()} | :none
  def find_trade_opportunity(agent, nearby_agents) do
    surplus = find_surplus(agent)
    needs = find_needs(agent)

    case {surplus, needs} do
      {nil, _} -> :none
      {_, nil} -> :none
      {surplus_res, need_res} ->
        partner = Enum.find(nearby_agents, fn other ->
          other.id != agent.id and
          in_trade_radius?(agent.position, other.position) and
          has_resource?(other, need_res) and
          wants_resource?(other, surplus_res)
        end)

        case partner do
          nil -> :none
          p ->
            offer_amount = min(Map.get(agent.inventory, surplus_res, 0.0), 3.0)
            request_amount = calculate_fair_exchange(surplus_res, offer_amount, need_res, agent)
            {:ok, %{partner: p, offer: surplus_res, offer_amount: offer_amount,
                     request: need_res, request_amount: request_amount}}
        end
    end
  end

  @doc "Get the perceived value of a resource, adjusted by supply/demand."
  @spec resource_value(atom()) :: float()
  def resource_value(resource) do
    base = Map.get(@base_values, resource, 1.0)
    supply_modifier = get_supply_modifier(resource)
    ensure_float(base * supply_modifier)
  end

  @doc "Update supply tracking based on global resource counts."
  @spec update_supply(map()) :: :ok
  def update_supply(resource_counts) do
    :ets.insert(@table, {:supply, resource_counts})
    :ok
  end

  @doc "Get trade history, optionally filtered by agent_id."
  @spec trade_history(keyword()) :: [map()]
  def trade_history(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    limit = Keyword.get(opts, :limit, 20)

    history = :ets.tab2list(@history_table)
              |> Enum.map(fn {_key, trade} -> trade end)
              |> Enum.sort_by(& &1.tick, :desc)

    history = case agent_id do
      nil -> history
      id -> Enum.filter(history, fn t -> t.agent_a_id == id or t.agent_b_id == id end)
    end

    Enum.take(history, limit)
  end

  @doc "Get trade statistics."
  @spec stats() :: map()
  def stats do
    case :ets.lookup(@table, :stats) do
      [{:stats, s}] -> s
      _ -> %{total_trades: 0, total_value: 0.0}
    end
  end

  @doc "Check if a market building is nearby, granting trade bonus."
  @spec market_bonus?({integer(), integer()}) :: boolean()
  def market_bonus?(position) do
    case :ets.whereis(:buildings) do
      :undefined -> false
      _ ->
        :ets.tab2list(:buildings)
        |> Enum.any?(fn
          {_id, %{type: :market, position: bpos}} -> in_trade_radius?(position, bpos)
          _ -> false
        end)
    end
  end

  # ── Personality-Based Value Assessment ─────────────────────

  @doc """
  Calculate how an agent values a resource based on personality.

  - High agreeableness: accepts worse deals (modifier 0.8-1.0)
  - Low agreeableness: drives hard bargains (modifier 1.2-1.5)
  - High conscientiousness: values long-term resources more
  - High openness: more willing to trade exotic items
  """
  @spec personality_value_modifier(map()) :: float()
  def personality_value_modifier(personality) do
    agreeableness = ensure_float(Map.get(personality, :agreeableness, 0.5))
    conscientiousness = ensure_float(Map.get(personality, :conscientiousness, 0.5))

    # Agreeable agents accept worse deals, disagreeable ones demand more
    agree_mod = 1.3 - (agreeableness * 0.5)
    # Conscientious agents are more careful (slight increase)
    consc_mod = 1.0 + (conscientiousness * 0.1)

    ensure_float(agree_mod * consc_mod)
  end

  # ── Internal ──────────────────────────────────────────────

  defp validate_proximity(pos_a, pos_b) do
    if in_trade_radius?(pos_a, pos_b), do: :ok, else: {:error, :too_far}
  end

  defp validate_inventory(agent, resource, amount) do
    available = ensure_float(Map.get(agent.inventory, resource, 0.0))
    if available >= amount, do: :ok, else: {:error, :insufficient_resources}
  end

  defp willing_to_trade?(_agent_a, agent_b, offer_res, offer_amt, request_res, request_amt) do
    # Agent B evaluates: is what I'm getting worth what I'm giving?
    offer_value = resource_value(offer_res) * ensure_float(offer_amt)
    request_value = resource_value(request_res) * ensure_float(request_amt)

    b_modifier = personality_value_modifier(agent_b.personality)

    # Agent B accepts if offer value >= their perceived value of what they give
    # The 0.6 threshold allows reasonable trades to go through
    offer_value >= (request_value * b_modifier * 0.5)
  end

  defp execute_trade(agent_a, agent_b, offer_res, offer_amt, request_res, request_amt, tick) do
    # Apply market bonus
    bonus = if market_bonus?(agent_a.position) or market_bonus?(agent_b.position),
      do: @market_bonus, else: 0.0

    effective_offer = ensure_float(offer_amt * (1.0 + bonus))

    trade_record = %{
      id: System.unique_integer([:positive]),
      tick: tick,
      agent_a_id: agent_a.id,
      agent_a_name: agent_a.name,
      agent_b_id: agent_b.id,
      agent_b_name: agent_b.name,
      offered: %{resource: offer_res, amount: effective_offer},
      received: %{resource: request_res, amount: request_amt},
      market_bonus: bonus > 0.0,
      timestamp: DateTime.utc_now()
    }

    # Record to history
    record_trade(trade_record)

    # Update stats
    trade_value = resource_value(offer_res) * effective_offer
    update_stats(trade_value)

    # Log event
    log_trade_event(trade_record, tick)

    {:ok, trade_record}
  end

  defp record_trade(trade) do
    key = {trade.tick, trade.id}
    :ets.insert(@history_table, {key, trade})

    # Trim old history
    count = :ets.info(@history_table, :size)
    if count > @max_history do
      first_key = :ets.first(@history_table)
      :ets.delete(@history_table, first_key)
    end
  end

  defp update_stats(trade_value) do
    case :ets.lookup(@table, :stats) do
      [{:stats, s}] ->
        :ets.insert(@table, {:stats, %{s |
          total_trades: s.total_trades + 1,
          total_value: ensure_float(s.total_value + trade_value)
        }})
      _ -> :ok
    end
  end

  defp log_trade_event(trade, tick) do
    try do
      Modus.Simulation.EventLog.log(:trade, tick, [trade.agent_a_id, trade.agent_b_id], %{
        from: trade.agent_a_name,
        to: trade.agent_b_name,
        offered: trade.offered,
        received: trade.received,
        market_bonus: trade.market_bonus
      })
    catch
      _, _ -> :ok
    end
  end

  defp calculate_fair_exchange(offer_res, offer_amount, request_res, agent) do
    offer_val = resource_value(offer_res) * ensure_float(offer_amount)
    request_unit_val = resource_value(request_res)
    modifier = personality_value_modifier(agent.personality)

    ensure_float(offer_val / (request_unit_val * modifier))
  end

  defp find_surplus(agent) do
    agent.inventory
    |> Enum.filter(fn {_k, v} -> ensure_float(v) > 5.0 end)
    |> Enum.max_by(fn {_k, v} -> ensure_float(v) end, fn -> nil end)
    |> case do
      nil -> nil
      {k, _v} -> k
    end
  end

  defp find_needs(agent) do
    # Check what agent needs based on low needs
    cond do
      agent.needs.hunger > 60.0 -> :food
      agent.needs.rest > 70.0 -> :herbs
      true ->
        # Find resource with lowest inventory
        all_resources = [:wood, :stone, :food, :herbs]
        Enum.min_by(all_resources, fn r -> ensure_float(Map.get(agent.inventory, r, 0.0)) end)
    end
  end

  defp has_resource?(agent, resource) do
    ensure_float(Map.get(agent.inventory, resource, 0.0)) > 1.0
  end

  defp wants_resource?(agent, resource) do
    ensure_float(Map.get(agent.inventory, resource, 0.0)) < 10.0
  end

  defp get_supply_modifier(resource) do
    case :ets.lookup(@table, :supply) do
      [{:supply, supply}] ->
        count = ensure_float(Map.get(supply, resource, 50.0))
        # More supply = lower value, less supply = higher value
        # Baseline is 50 units; modifier ranges ~0.5 to 2.0
        cond do
          count <= 0.0 -> 2.0
          count < 20.0 -> 1.5
          count < 40.0 -> 1.2
          count < 60.0 -> 1.0
          count < 80.0 -> 0.8
          true -> 0.6
        end
      _ -> 1.0
    end
  end

  defp in_trade_radius?({x1, y1}, {x2, y2}) do
    abs(x1 - x2) <= @trade_radius and abs(y1 - y2) <= @trade_radius
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
