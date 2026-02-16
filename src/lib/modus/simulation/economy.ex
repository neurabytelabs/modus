defmodule Modus.Simulation.Economy do
  @moduledoc """
  Economy — Simple barter/trade system between agents.

  Proximity-based resource transfer: agents within trade_radius
  can request and accept trades. Tracks global trade statistics.
  """

  @trade_radius 3
  @trade_amount 1.0

  # ── State (ETS-based, no GenServer blocking) ────────────────

  @table :modus_economy

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ets.insert(@table, {:stats, %{trades: 0, total_transferred: 0.0}})
    :ok
  end

  @doc "Get economy stats."
  @spec stats() :: map()
  def stats do
    case :ets.lookup(@table, :stats) do
      [{:stats, s}] -> s
      _ -> %{trades: 0, total_transferred: 0.0}
    end
  end

  @doc "Transfer resource from one cell to boost an agent's need."
  @spec transfer_resource({integer(), integer()}, {integer(), integer()}, atom(), float()) ::
          {:ok, float()} | {:error, term()}
  def transfer_resource(from_pos, to_pos, resource_type, amount \\ @trade_amount) do
    if in_trade_radius?(from_pos, to_pos) do
      case Modus.Simulation.ResourceSystem.gather(from_pos, resource_type, amount) do
        {:ok, gathered} when gathered > 0 ->
          increment_stats(gathered)
          {:ok, gathered}

        _ ->
          {:error, :no_resources}
      end
    else
      {:error, :too_far}
    end
  end

  @doc "Attempt a proximity-based trade between two agents. Returns :ok or :error."
  @spec try_trade(map(), map(), non_neg_integer()) :: :ok | {:error, term()}
  def try_trade(agent_a, agent_b, tick) do
    pos_a = agent_a.position
    pos_b = agent_b.position

    if in_trade_radius?(pos_a, pos_b) do
      # Agent A shares food from their cell with agent B
      case transfer_resource(pos_a, pos_b, :food, @trade_amount) do
        {:ok, amount} ->
          Modus.Simulation.EventLog.log(:trade, tick, [agent_a.id, agent_b.id], %{
            from: agent_a.name,
            to: agent_b.name,
            resource: :food,
            amount: amount
          })
          :ok

        error ->
          error
      end
    else
      {:error, :too_far}
    end
  end

  @doc "Process economy tick — traders near hungry agents auto-trade."
  @spec tick(non_neg_integer()) :: :ok
  def tick(tick_number) do
    # Only run every 10 ticks to avoid overhead
    if rem(tick_number, 10) == 0 do
      process_auto_trades(tick_number)
    end

    :ok
  end

  # ── Internal ────────────────────────────────────────────────

  defp process_auto_trades(tick) do
    agents = get_living_agents()

    # Find hungry agents (hunger > 60) and nearby traders/farmers
    hungry = Enum.filter(agents, fn a -> a.needs.hunger > 60.0 end)
    helpers = Enum.filter(agents, fn a -> a.occupation in [:trader, :farmer] and a.needs.hunger < 50.0 end)

    Enum.each(hungry, fn hungry_agent ->
      case Enum.find(helpers, fn h ->
        h.id != hungry_agent.id and in_trade_radius?(h.position, hungry_agent.position)
      end) do
        nil -> :ok
        helper -> try_trade(helper, hungry_agent, tick)
      end
    end)
  end

  defp get_living_agents do
    Modus.Simulation.AgentSupervisor.list_agents()
    |> Enum.map(fn id ->
      try do
        Modus.Simulation.Agent.get_state(id)
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.filter(fn a -> a != nil and a.alive? end)
  end

  defp in_trade_radius?({x1, y1}, {x2, y2}) do
    abs(x1 - x2) <= @trade_radius and abs(y1 - y2) <= @trade_radius
  end

  defp increment_stats(amount) do
    case :ets.lookup(@table, :stats) do
      [{:stats, s}] ->
        :ets.insert(@table, {:stats, %{s | trades: s.trades + 1, total_transferred: s.total_transferred + amount}})

      _ ->
        :ok
    end
  end

end
