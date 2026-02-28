defmodule Modus.Intelligence.LlmScheduler do
  @moduledoc """
  LlmScheduler — Subscribes to tick events and triggers LLM batch decisions.

  v3.2.0 Ratio: Uses ResponseCache, FallbackChain, BudgetTracker, and LlmMetrics.
  Rate limited: max 1 concurrent LLM request, batched every 100 ticks.
  """
  use GenServer
  require Logger

  alias Modus.Simulation.Agent

  alias Modus.Intelligence.{
    DecisionCache,
    ResponseCache,
    FallbackChain,
    BudgetTracker,
    BehaviorTree,
    LlmMetrics
  }

  @batch_interval 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get current scheduler stats for dashboard (v7.3)."
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  catch
    :exit, _ -> %{busy: false, last_batch_tick: 0, total_batches: 0, total_cache_hits: 0}
  end

  @impl true
  def init(_) do
    # Initialize metrics and budget tables
    LlmMetrics.init()
    BudgetTracker.init()
    Modus.Protocol.RunePromptEngine.init()
    Modus.Simulation.Ticker.subscribe()
    {:ok, %{last_conversation_tick: 0, busy: false, total_batches: 0, total_cache_hits: 0, last_batch_tick: 0}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       busy: state.busy,
       last_batch_tick: state.last_batch_tick,
       total_batches: state.total_batches,
       total_cache_hits: state.total_cache_hits
     }, state}
  end

  @impl true
  def handle_info({:tick, _tick}, %{busy: true} = state) do
    {:noreply, state}
  end

  def handle_info({:tick, tick}, state) do
    # Reset budget each tick and snapshot metrics
    BudgetTracker.reset()
    LlmMetrics.tick_snapshot(tick)

    cond do
      rem(tick, @batch_interval) == 0 and tick > 0 ->
        {:noreply, %{state | busy: true, last_batch_tick: tick, total_batches: state.total_batches + 1} |> spawn_batch(tick)}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:llm_done}, state) do
    {:noreply, %{state | busy: false}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp spawn_batch(state, tick) do
    scheduler = self()

    Task.start(fn ->
      try do
        agents = get_alive_agents()

        if agents != [] do
          # Split: agents with cached responses vs those needing LLM
          {cached_agents, uncached_agents} =
            Enum.split_with(agents, fn agent ->
              hash = ResponseCache.situation_hash(agent)
              ResponseCache.get(hash, tick) != nil
            end)

          # Apply cached decisions
          for agent <- cached_agents do
            hash = ResponseCache.situation_hash(agent)

            case ResponseCache.get(hash, tick) do
              {action, params} -> DecisionCache.put(agent.id, {action, params})
              _ -> :ok
            end
          end

          if length(cached_agents) > 0 do
            Logger.debug("LLM cache hit for #{length(cached_agents)} agents")
          end

          # Check budget for uncached
          if uncached_agents != [] do
            case BudgetTracker.request_slot(:normal) do
              :ok ->
                context = %{tick: tick, world_size: {50, 50}}

                case FallbackChain.batch_decide(uncached_agents, context) do
                  :fallback ->
                    # Use behavior tree
                    for agent <- uncached_agents do
                      action = BehaviorTree.evaluate(agent, tick)
                      DecisionCache.put(agent.id, {action, %{reason: "behavior_tree", target: nil}})
                    end

                  decisions when is_list(decisions) ->
                    for {agent_id, action, params} <- decisions do
                      DecisionCache.put(agent_id, {action, params})
                      # Cache the response for similar situations
                      agent = Enum.find(uncached_agents, &(&1.id == agent_id))

                      if agent do
                        hash = ResponseCache.situation_hash(agent)
                        ResponseCache.put(hash, {action, params}, tick)
                      end
                    end

                    Logger.info(
                      "LLM batch decided for #{length(decisions)} agents at tick #{tick}"
                    )

                  _ ->
                    :ok
                end

              :over_budget ->
                # Over budget — use behavior tree
                for agent <- uncached_agents do
                  action = BehaviorTree.evaluate(agent, tick)
                  DecisionCache.put(agent.id, {action, %{reason: "budget_limited"}})
                end

                Logger.debug(
                  "LLM over budget at tick #{tick}, using behavior tree for #{length(uncached_agents)} agents"
                )
            end
          end
        end
      rescue
        e -> Logger.warning("LLM batch error: #{inspect(e)}")
      after
        send(scheduler, {:llm_done})
      end
    end)

    state
  end

  defp get_alive_agents do
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.reduce([], fn agent_id, acc ->
      try do
        state = Agent.get_state(agent_id)
        if state && state.alive?, do: [state | acc], else: acc
      catch
        :exit, _ -> acc
      end
    end)
    |> Enum.take(10)
  end
end
