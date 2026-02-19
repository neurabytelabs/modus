defmodule Modus.Nexus.TraceEngine do
  @moduledoc """
  TraceEngine — Agent davranış izleme ve "Neden?" soruları motoru.

  ## Özellikler
  - **Decision Log:** Her tick'te ajanın kararını kaydeder (ETS, circular buffer, max 100/ajan)
  - **Position Trace:** Timeline formatında konum geçmişi
  - **Disappearance Detection:** Ajan görünür alandan çıkınca otomatik log
  - **Why Answer:** decision_log + affect_state + spatial_data birleştirip açıklama üretir

  ETS tabloları memory-efficient: ajan başına max 100 entry, circular buffer.
  """
  use GenServer

  require Logger

  alias Modus.Simulation.{Agent, AgentSupervisor}

  @max_decisions 100
  @max_positions 100
  @ets_decisions :nexus_trace_decisions
  @ets_positions :nexus_trace_positions
  @ets_disappearances :nexus_trace_disappearances

  # Default viewport bounds (50x50 world)
  @default_viewport %{min_x: 0, min_y: 0, max_x: 49, max_y: 49}

  # ── Types ───────────────────────────────────────────────

  @type decision_entry :: %{
          tick: non_neg_integer(),
          timestamp: integer(),
          action: atom() | String.t(),
          reason: String.t() | nil,
          energy: float(),
          affect: atom(),
          position: {integer(), integer()}
        }

  @type disappearance_entry :: %{
          tick: non_neg_integer(),
          timestamp: integer(),
          agent_id: String.t(),
          agent_name: String.t(),
          last_position: {integer(), integer()},
          cause: atom(),
          details: String.t()
        }

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Record an agent's decision at a tick."
  @spec log_decision(String.t(), decision_entry()) :: :ok
  def log_decision(agent_id, entry) when is_binary(agent_id) and is_map(entry) do
    current =
      case :ets.lookup(@ets_decisions, agent_id) do
        [{^agent_id, decisions}] -> decisions
        [] -> []
      end

    updated = Enum.take([entry | current], @max_decisions)
    :ets.insert(@ets_decisions, {agent_id, updated})
    :ok
  end

  @doc "Record an agent's position with timestamp."
  @spec log_position(String.t(), {integer(), integer()}, non_neg_integer()) :: :ok
  def log_position(agent_id, position, tick \\ 0) do
    current =
      case :ets.lookup(@ets_positions, agent_id) do
        [{^agent_id, positions}] -> positions
        [] -> []
      end

    entry = %{position: position, tick: tick, timestamp: System.system_time(:second)}
    updated = Enum.take([entry | current], @max_positions)
    :ets.insert(@ets_positions, {agent_id, updated})
    :ok
  end

  @doc "Get decision log for an agent (most recent first)."
  @spec get_decisions(String.t(), non_neg_integer()) :: [decision_entry()]
  def get_decisions(agent_id, limit \\ 10) do
    case :ets.lookup(@ets_decisions, agent_id) do
      [{^agent_id, decisions}] -> Enum.take(decisions, limit)
      [] -> []
    end
  end

  @doc "Get position trace for an agent (most recent first)."
  @spec get_position_trace(String.t(), non_neg_integer()) :: [map()]
  def get_position_trace(agent_id, limit \\ 20) do
    case :ets.lookup(@ets_positions, agent_id) do
      [{^agent_id, positions}] -> Enum.take(positions, limit)
      [] -> []
    end
  end

  @doc "Get all disappearance events."
  @spec get_disappearances(non_neg_integer()) :: [disappearance_entry()]
  def get_disappearances(limit \\ 20) do
    :ets.tab2list(@ets_disappearances)
    |> Enum.flat_map(fn {_key, entries} -> entries end)
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Check all agents for disappearance from viewport.
  Call periodically (e.g., every N ticks).
  """
  @spec check_disappearances(map()) :: [disappearance_entry()]
  def check_disappearances(viewport \\ @default_viewport) do
    agent_ids = AgentSupervisor.list_agents()

    disappeared =
      agent_ids
      |> Enum.map(fn id ->
        try do
          agent = Agent.get_state(id)
          {id, agent}
        catch
          :exit, _ -> {id, nil}
        end
      end)
      |> Enum.filter(fn {_id, agent} ->
        agent != nil && out_of_bounds?(agent.position, viewport)
      end)
      |> Enum.map(fn {id, agent} ->
        cause = detect_disappearance_cause(agent, viewport)

        entry = %{
          tick: 0,
          timestamp: System.system_time(:second),
          agent_id: id,
          agent_name: agent.name,
          last_position: agent.position,
          cause: cause,
          details: disappearance_reason(cause, agent, viewport)
        }

        log_disappearance(id, entry)
        entry
      end)

    disappeared
  end

  @doc """
  Answer "Why?" — combines decision log, affect state, spatial data, and optionally
  uses Ollama for natural language explanation (5s timeout, template fallback).
  """
  @spec why_answer(String.t()) :: String.t()
  def why_answer(agent_id) do
    decisions = get_decisions(agent_id, 5)
    positions = get_position_trace(agent_id, 10)

    agent_state =
      try do
        agent = Agent.get_state(agent_id)

        %{
          name: agent.name,
          position: agent.position,
          energy: agent.conatus_energy,
          affect: agent.affect_state,
          alive: agent.alive?,
          needs: agent.needs,
          last_reasoning: agent.last_reasoning
        }
      catch
        :exit, _ -> nil
      end

    disappearances =
      case :ets.lookup(@ets_disappearances, agent_id) do
        [{^agent_id, entries}] -> Enum.take(entries, 3)
        [] -> []
      end

    context = %{
      agent: agent_state,
      recent_decisions: decisions,
      position_trace: positions,
      disappearances: disappearances
    }

    case try_ollama_explain(context) do
      {:ok, text} -> text
      _ -> template_why(context)
    end
  end

  @doc """
  Answer a specific "why" question about an agent.
  """
  @spec why_query(String.t(), String.t()) :: String.t()
  def why_query(agent_id, question) do
    decisions = get_decisions(agent_id, 5)
    positions = get_position_trace(agent_id, 10)

    agent_state =
      try do
        agent = Agent.get_state(agent_id)

        %{
          name: agent.name,
          position: agent.position,
          energy: agent.conatus_energy,
          affect: agent.affect_state,
          alive: agent.alive?,
          needs: agent.needs,
          last_reasoning: agent.last_reasoning
        }
      catch
        :exit, _ -> nil
      end

    context = %{
      question: question,
      agent: agent_state,
      recent_decisions: decisions,
      position_trace: positions
    }

    case try_ollama_why(context) do
      {:ok, text} -> text
      _ -> template_why(context)
    end
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(:ok) do
    ensure_ets(@ets_decisions)
    ensure_ets(@ets_positions)
    ensure_ets(@ets_disappearances)
    {:ok, %{}}
  end

  # ── Private ─────────────────────────────────────────────

  defp log_disappearance(agent_id, entry) do
    current =
      case :ets.lookup(@ets_disappearances, agent_id) do
        [{^agent_id, entries}] -> entries
        [] -> []
      end

    updated = Enum.take([entry | current], 20)
    :ets.insert(@ets_disappearances, {agent_id, updated})
  end

  defp out_of_bounds?({x, y}, viewport) do
    x < viewport.min_x or x > viewport.max_x or
      y < viewport.min_y or y > viewport.max_y
  end

  defp detect_disappearance_cause(agent, viewport) do
    {x, y} = agent.position

    cond do
      not agent.alive? -> :death
      agent.conatus_energy < 0.05 -> :exhaustion
      x < viewport.min_x or x > viewport.max_x -> :boundary_x
      y < viewport.min_y or y > viewport.max_y -> :boundary_y
      agent.affect_state == :fear -> :fled
      true -> :unknown
    end
  end

  defp disappearance_reason(:death, agent, _viewport) do
    "#{agent.name} öldü. Son konum: #{inspect(agent.position)}"
  end

  defp disappearance_reason(:exhaustion, agent, _viewport) do
    "#{agent.name} enerjisi tükendi (#{agent.conatus_energy}). Konum: #{inspect(agent.position)}"
  end

  defp disappearance_reason(:boundary_x, agent, viewport) do
    "#{agent.name} yatay sınırı aştı. Konum: #{inspect(agent.position)}, sınır: #{viewport.min_x}-#{viewport.max_x}"
  end

  defp disappearance_reason(:boundary_y, agent, viewport) do
    "#{agent.name} dikey sınırı aştı. Konum: #{inspect(agent.position)}, sınır: #{viewport.min_y}-#{viewport.max_y}"
  end

  defp disappearance_reason(:fled, agent, _viewport) do
    "#{agent.name} korku durumunda kaçtı. Konum: #{inspect(agent.position)}"
  end

  defp disappearance_reason(:unknown, agent, _viewport) do
    "#{agent.name} bilinmeyen nedenle kayboldu. Konum: #{inspect(agent.position)}"
  end

  defp try_ollama_explain(context) do
    prompt = """
    You are explaining agent behavior in a simulation. Be brief and friendly.
    Respond in the world's language (Turkish if unclear).

    Agent data:
    #{inspect(context, pretty: true, limit: 500)}

    Summarize: What is this agent doing and why? Include recent decisions and emotional state.
    """

    ollama_call(prompt)
  end

  defp try_ollama_why(context) do
    question = Map.get(context, :question, "Neden?")

    prompt = """
    You are answering a question about an agent in a simulation. Be brief and clear.
    Respond in the same language as the question.

    Question: #{question}

    Agent data:
    #{inspect(Map.delete(context, :question), pretty: true, limit: 500)}

    Answer the question using the agent's decision log, position trace, and emotional state.
    """

    ollama_call(prompt)
  end

  defp ollama_call(prompt) do
    messages = [%{role: "user", content: prompt}]

    try do
      task =
        Task.Supervisor.async_nolink(
          Modus.Nexus.TraceEngine.TaskSupervisor,
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

  defp template_why(%{agent: nil}) do
    "🔍 Ajan bulunamadı — muhtemelen öldü veya kayboldu."
  end

  defp template_why(%{agent: agent} = context) do
    decisions = Map.get(context, :recent_decisions, [])
    positions = Map.get(context, :position_trace, [])
    disappearances = Map.get(context, :disappearances, [])

    parts = ["🔍 #{agent.name} Analizi:"]

    # Current state
    parts =
      parts ++
        ["  ⚡ Enerji: #{agent.energy}, Duygu: #{agent.affect}"]

    # Last reasoning
    parts =
      if agent.last_reasoning do
        parts ++ ["  💭 Son düşünce: #{agent.last_reasoning}"]
      else
        parts
      end

    # Needs
    parts =
      if agent.needs do
        critical =
          agent.needs
          |> Enum.filter(fn {_k, v} -> v < 30 end)
          |> Enum.map(fn {k, v} -> "#{k}=#{round(v)}" end)

        if length(critical) > 0 do
          parts ++ ["  ⚠️ Kritik ihtiyaçlar: #{Enum.join(critical, ", ")}"]
        else
          parts
        end
      else
        parts
      end

    # Recent decisions
    parts =
      if length(decisions) > 0 do
        decision_strs =
          decisions
          |> Enum.take(3)
          |> Enum.map(fn d ->
            action = Map.get(d, :action, "?")
            reason = Map.get(d, :reason, "")
            "    • #{action}" <> if(reason != "" and reason != nil, do: " — #{reason}", else: "")
          end)

        parts ++ ["  📋 Son kararlar:"] ++ decision_strs
      else
        parts ++ ["  📋 Karar kaydı yok"]
      end

    # Movement
    parts =
      if length(positions) >= 2 do
        first = List.last(positions)
        last = hd(positions)
        parts ++ ["  🗺️ Hareket: #{inspect(first.position)} → #{inspect(last.position)}"]
      else
        parts
      end

    # Disappearances
    parts =
      if length(disappearances) > 0 do
        d = hd(disappearances)
        parts ++ ["  👻 Son kaybolma: #{d.cause} — #{d.details}"]
      else
        parts
      end

    Enum.join(parts, "\n")
  end

  defp ensure_ets(name) do
    if :ets.whereis(name) == :undefined do
      :ets.new(name, [:set, :public, :named_table])
    end
  end
end
