defmodule Modus.Nexus.InsightEngine do
  @moduledoc """
  InsightEngine — Nexus insight query processor.

  Handles agent queries, event replays, stats, and formats responses
  using Ollama with template fallback.
  """
  use GenServer

  alias Modus.Simulation.{Agent, AgentSupervisor, EventLog}

  @max_positions 50
  @ets_table :nexus_position_history

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Record an agent's position (keeps last #{@max_positions})."
  def record_position(agent_id, position) do
    current =
      case :ets.lookup(@ets_table, agent_id) do
        [{^agent_id, positions}] -> positions
        [] -> []
      end

    updated = Enum.take([position | current], @max_positions)
    :ets.insert(@ets_table, {agent_id, updated})
    :ok
  end

  @doc "Query agent info by id."
  def agent_query(agent_id) do
    try do
      agent = Agent.get_state(agent_id)

      history =
        case :ets.lookup(@ets_table, agent_id) do
          [{^agent_id, positions}] -> Enum.take(positions, 10)
          [] -> []
        end

      %{
        name: agent.name,
        position: agent.position,
        conatus_energy: agent.conatus_energy,
        affect_state: agent.affect_state,
        last_reasoning: agent.last_reasoning,
        needs: agent.needs,
        alive?: agent.alive?,
        position_history: history
      }
    catch
      :exit, _ -> {:error, :agent_not_found}
    end
  end

  @doc "Replay recent events."
  def event_replay(opts \\ []) do
    EventLog.recent(opts)
  end

  @doc "Compute stats across all agents."
  def stats_query do
    agent_ids = AgentSupervisor.list_agents()

    agents =
      agent_ids
      |> Enum.map(fn id ->
        try do
          Agent.get_state(id)
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    total = length(agents)

    if total == 0 do
      %{total_agents: 0, average_energy: 0.0, happiest: nil, saddest: nil, affect_distribution: %{}}
    else
      energies = Enum.map(agents, & &1.conatus_energy)
      avg = Float.round(Enum.sum(energies) * 1.0 / total, 3)
      happiest = Enum.max_by(agents, & &1.conatus_energy)
      saddest = Enum.min_by(agents, & &1.conatus_energy)

      affect_dist =
        agents
        |> Enum.group_by(& &1.affect_state)
        |> Enum.map(fn {k, v} -> {k, length(v)} end)
        |> Map.new()

      %{
        total_agents: total,
        average_energy: avg,
        happiest: %{name: happiest.name, energy: happiest.conatus_energy},
        saddest: %{name: saddest.name, energy: saddest.conatus_energy},
        affect_distribution: affect_dist
      }
    end
  end

  @doc "Format response — tries Ollama, falls back to templates."
  def format_response(sub_intent, data) do
    case try_ollama(data) do
      {:ok, text} -> text
      _ -> template_fallback(sub_intent, data)
    end
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(:ok) do
    table_exists? = :ets.whereis(@ets_table) != :undefined

    unless table_exists? do
      :ets.new(@ets_table, [:set, :public, :named_table])
    end

    {:ok, %{}}
  end

  # ── Private ─────────────────────────────────────────────

  defp try_ollama(data) do
    messages = [
      %{
        role: "user",
        content:
          "Format this simulation data as a brief, friendly response in the world's language: #{inspect(data)}"
      }
    ]

    try do
      task =
        Task.Supervisor.async_nolink(
          Modus.Nexus.InsightEngine.TaskSupervisor,
          fn ->
            Modus.Intelligence.OllamaClient.chat_completion_direct(messages, %{})
          end
        )

      case Task.yield(task, 5_000) || Task.shutdown(task) do
        {:ok, {:ok, text}} -> {:ok, text}
        _ -> {:error, :timeout}
      end
    rescue
      _ -> {:error, :ollama_unavailable}
    catch
      :exit, _ -> {:error, :ollama_unavailable}
    end
  end

  defp template_fallback(:agent_query, data) when is_map(data) do
    name = Map.get(data, :name, "Unknown")
    energy = Map.get(data, :conatus_energy, "?")
    affect = Map.get(data, :affect_state, "?")
    "🧬 #{name}: Energy #{energy}, Affect: #{affect}"
  end

  defp template_fallback(:stats_query, data) when is_map(data) do
    total = Map.get(data, :total_agents, 0)
    avg = Map.get(data, :average_energy, 0)
    "📊 #{total} agents, average energy: #{avg}"
  end

  defp template_fallback(:event_query, data) when is_list(data) do
    count = length(data)
    "📜 #{count} recent events found."
  end

  defp template_fallback(:why_query, data) do
    "🤔 Analysis: #{inspect(data)}"
  end

  defp template_fallback(_sub_intent, data) do
    "ℹ️ #{inspect(data)}"
  end
end
