defmodule Modus.Intelligence.LlmScheduler do
  @moduledoc """
  LlmScheduler — Subscribes to tick events and triggers LLM batch decisions.

  Every 100 ticks, collects up to 10 alive agents and sends them
  to OllamaClient for creative decision-making. Also triggers
  agent-agent conversations when conditions are met.
  """
  use GenServer

  require Logger

  alias Modus.Simulation.{Agent, DecisionEngine}
  alias Modus.Intelligence.OllamaClient

  @conversation_social_threshold 40.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Modus.Simulation.Ticker.subscribe()
    {:ok, %{last_conversation_tick: 0}}
  end

  @impl true
  def handle_info({:tick, tick}, state) do
    state =
      if DecisionEngine.llm_tick?(tick) do
        # Batch decisions
        spawn_batch(tick)

        # Conversations (every 200 ticks, offset from batch)
        state =
          if tick - state.last_conversation_tick >= 200 do
            spawn_conversations(tick)
            %{state | last_conversation_tick: tick}
          else
            state
          end

        state
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp spawn_batch(tick) do
    Task.start(fn ->
      agents = get_alive_agents()

      if agents != [] do
        context = %{tick: tick, world_size: {50, 50}}
        DecisionEngine.llm_batch(agents, context)
        Logger.info("LLM batch decided for #{length(agents)} agents at tick #{tick}")
      end
    end)
  end

  defp spawn_conversations(tick) do
    Task.start(fn ->
      agents = get_alive_agents()

      # Find pairs: same cell + both have low social need
      pairs = find_conversation_pairs(agents)

      Enum.each(Enum.take(pairs, 2), fn {a, b} ->
        context = %{tick: tick}

        case OllamaClient.conversation(a, b, context) do
          :fallback ->
            :ok

          dialogue ->
            Logger.info("Conversation at tick #{tick}: #{a.name} <-> #{b.name}")

            # Store conversation in both agents' memories
            for {speaker, line} <- dialogue do
              Logger.info("  [#{speaker}]: #{line}")
            end

            # Broadcast conversation event for LiveView
            Phoenix.PubSub.broadcast(
              Modus.PubSub,
              "modus:events",
              {:conversation, %{
                tick: tick,
                agents: {a.id, b.id},
                names: {a.name, b.name},
                dialogue: dialogue
              }}
            )
        end
      end)
    end)
  end

  defp find_conversation_pairs(agents) do
    agents
    |> Enum.filter(fn a -> a.needs.social < @conversation_social_threshold end)
    |> Enum.group_by(fn a -> a.position end)
    |> Enum.flat_map(fn {_pos, group} ->
      if length(group) >= 2 do
        [a, b | _] = Enum.shuffle(group)
        [{a, b}]
      else
        []
      end
    end)
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
