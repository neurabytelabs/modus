defmodule Modus.Intelligence.LlmScheduler do
  @moduledoc """
  LlmScheduler — Subscribes to tick events and triggers LLM batch decisions.

  Rate limited: max 1 concurrent LLM request, conversations every 500 ticks.
  """
  use GenServer
  require Logger

  alias Modus.Simulation.Agent
  alias Modus.Intelligence.{LlmProvider, DecisionCache}

  @batch_interval 100

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Modus.Simulation.Ticker.subscribe()
    {:ok, %{last_conversation_tick: 0, busy: false}}
  end

  @impl true
  def handle_info({:tick, _tick}, %{busy: true} = state) do
    # Skip — previous LLM request still running
    {:noreply, state}
  end

  def handle_info({:tick, tick}, state) do
    cond do
      # Conversations disabled: Agent.get_state causes GenServer deadlocks
      # rem(tick, @conversation_interval) == 0 and tick > 0 ->
      #   {:noreply, %{state | busy: true} |> spawn_conversations(tick)}

      rem(tick, @batch_interval) == 0 and tick > 0 ->
        {:noreply, %{state | busy: true} |> spawn_batch(tick)}

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
          context = %{tick: tick, world_size: {50, 50}}
          case LlmProvider.decide(agents, context) do
            :fallback -> :ok
            decisions when is_list(decisions) ->
              for {agent_id, action, params} <- decisions do
                DecisionCache.put(agent_id, {action, params})
              end
              Logger.info("LLM batch decided for #{length(decisions)} agents at tick #{tick}")
            _ -> :ok
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
        if state.alive?, do: [state | acc], else: acc
      catch
        :exit, _ -> acc
      end
    end)
    |> Enum.take(10)
  end
end
