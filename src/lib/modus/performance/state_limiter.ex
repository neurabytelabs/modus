defmodule Modus.Performance.StateLimiter do
  @moduledoc """
  StateLimiter — Enforces max 10KB state per agent.

  Trims memory, history, and inventory to keep agent state compact.
  """

  @max_state_bytes 10_240
  @max_memory_entries 15
  @max_affect_history 10
  @max_conatus_history 10
  @max_inventory_types 8

  @doc "Trim agent state to fit within memory limits."
  @spec trim(map()) :: map()
  def trim(agent) do
    agent
    |> trim_memory()
    |> trim_affect_history()
    |> trim_conatus_history()
    |> trim_inventory()
  end

  @doc "Check if an agent's estimated state size exceeds the limit."
  @spec over_limit?(map()) :: boolean()
  def over_limit?(agent) do
    estimate_size(agent) > @max_state_bytes
  end

  @doc "Estimate the byte size of an agent's state."
  @spec estimate_size(map()) :: non_neg_integer()
  def estimate_size(agent) do
    :erlang.external_size(agent)
  rescue
    _ -> 0
  end

  defp trim_memory(agent) do
    case agent do
      %{memory: memory} when is_list(memory) and length(memory) > @max_memory_entries ->
        %{agent | memory: Enum.take(memory, @max_memory_entries)}
      _ -> agent
    end
  end

  defp trim_affect_history(agent) do
    case agent do
      %{affect_history: history} when is_list(history) and length(history) > @max_affect_history ->
        %{agent | affect_history: Enum.take(history, @max_affect_history)}
      _ -> agent
    end
  end

  defp trim_conatus_history(agent) do
    case agent do
      %{conatus_history: history} when is_list(history) and length(history) > @max_conatus_history ->
        %{agent | conatus_history: Enum.take(history, @max_conatus_history)}
      _ -> agent
    end
  end

  defp trim_inventory(agent) do
    case agent do
      %{inventory: inv} when is_map(inv) and map_size(inv) > @max_inventory_types ->
        # Keep the most valuable items
        trimmed = inv
        |> Enum.sort_by(fn {_k, v} -> v end, :desc)
        |> Enum.take(@max_inventory_types)
        |> Map.new()
        %{agent | inventory: trimmed}
      _ -> agent
    end
  end
end
