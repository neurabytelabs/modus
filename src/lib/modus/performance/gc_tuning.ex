defmodule Modus.Performance.GcTuning do
  @moduledoc """
  GcTuning — Erlang VM garbage collection tuning for MODUS.

  Configures fullsweep_after and other GC parameters to reduce
  GC pressure from many short-lived agent processes.
  """

  @default_fullsweep 50

  @doc "Apply GC tuning for the entire VM."
  @spec apply_defaults() :: :ok
  def apply_defaults do
    # Reduce fullsweep frequency — agents accumulate small state
    :erlang.system_flag(:fullsweep_after, @default_fullsweep)
    :ok
  end

  @doc "Apply GC tuning to a specific process."
  @spec tune_process(pid(), keyword()) :: :ok
  def tune_process(pid, opts \\ []) do
    fullsweep = Keyword.get(opts, :fullsweep_after, @default_fullsweep)
    Process.flag(pid, :fullsweep_after, fullsweep)
    :ok
  rescue
    _ -> :ok
  end

  @doc "Force GC on all agent processes (use sparingly)."
  @spec gc_all_agents() :: non_neg_integer()
  def gc_all_agents do
    Modus.AgentRegistry
    |> Registry.select([{{:_, :"$2", :_}, [], [:"$2"]}])
    |> Enum.each(&:erlang.garbage_collect/1)
    |> then(fn _ ->
      try do
        Registry.count(Modus.AgentRegistry)
      catch
        _, _ -> 0
      end
    end)
  end

  @doc "Get current GC stats."
  @spec stats() :: map()
  def stats do
    %{
      fullsweep_after: :erlang.system_flag(:fullsweep_after, @default_fullsweep),
      gc_count: :erlang.statistics(:garbage_collection) |> elem(0),
      gc_words_reclaimed: :erlang.statistics(:garbage_collection) |> elem(1)
    }
  end
end
