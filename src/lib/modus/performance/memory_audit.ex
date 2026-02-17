defmodule Modus.Performance.MemoryAudit do
  @moduledoc """
  MemoryAudit — Measures per-agent and system-wide memory usage.
  Provides tools for identifying memory-heavy agents and ETS tables.
  """

  @doc "Measure memory usage of a single agent process by id."
  @spec agent_memory(String.t()) :: {:ok, map()} | {:error, :not_found}
  def agent_memory(agent_id) do
    case Registry.lookup(Modus.AgentRegistry, agent_id) do
      [{pid, _}] ->
        info = Process.info(pid, [:memory, :heap_size, :stack_size, :message_queue_len])
        if info do
          {:ok, %{
            agent_id: agent_id,
            memory_bytes: Keyword.get(info, :memory, 0),
            heap_words: Keyword.get(info, :heap_size, 0),
            stack_words: Keyword.get(info, :stack_size, 0),
            message_queue: Keyword.get(info, :message_queue_len, 0)
          }}
        else
          {:error, :not_found}
        end
      _ ->
        {:error, :not_found}
    end
  end

  @doc "Measure memory for all living agents. Returns sorted list (heaviest first)."
  @spec all_agents() :: [map()]
  def all_agents do
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {id, pid} ->
      info = Process.info(pid, [:memory, :heap_size])
      %{
        agent_id: id,
        memory_bytes: (info && Keyword.get(info, :memory, 0)) || 0,
        heap_words: (info && Keyword.get(info, :heap_size, 0)) || 0
      }
    end)
    |> Enum.sort_by(& &1.memory_bytes, :desc)
  end

  @doc "Summary statistics for all agents."
  @spec summary() :: map()
  def summary do
    agents = all_agents()
    count = length(agents)

    if count == 0 do
      %{count: 0, total_bytes: 0, avg_bytes: 0, max_bytes: 0, min_bytes: 0, over_limit: 0}
    else
      memories = Enum.map(agents, & &1.memory_bytes)
      total = Enum.sum(memories)
      %{
        count: count,
        total_bytes: total,
        avg_bytes: div(total, count),
        max_bytes: Enum.max(memories),
        min_bytes: Enum.min(memories),
        over_limit: Enum.count(memories, &(&1 > 10_240))
      }
    end
  end

  @doc "List all named ETS tables with their memory usage."
  @spec ets_tables() :: [map()]
  def ets_tables do
    :ets.all()
    |> Enum.map(fn table ->
      try do
        info = :ets.info(table)
        %{
          name: info[:name] || table,
          size: info[:size] || 0,
          memory_words: info[:memory] || 0,
          memory_bytes: (info[:memory] || 0) * :erlang.system_info(:wordsize),
          type: info[:type] || :unknown
        }
      catch
        _, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.memory_bytes, :desc)
  end

  @doc "Total system memory report."
  @spec system_report() :: map()
  def system_report do
    mem = :erlang.memory()
    %{
      total_bytes: mem[:total],
      processes_bytes: mem[:processes],
      ets_bytes: mem[:ets],
      atom_bytes: mem[:atom],
      binary_bytes: mem[:binary],
      agent_summary: summary(),
      ets_tables: Enum.take(ets_tables(), 10)
    }
  end
end
