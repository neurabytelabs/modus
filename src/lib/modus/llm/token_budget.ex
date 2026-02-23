defmodule Modus.Llm.TokenBudget do
  @moduledoc """
  ETS-based token budget tracker for LLM calls.

  - Per-agent: max 500 tokens/response
  - World-level: max 1000 LLM calls/session
  - Budget exceeded → {:over_budget, cached_response}
  """

  @table :modus_token_budget
  @max_tokens_per_agent 500
  @max_calls_per_session 1000

  @doc "Initialize the ETS table."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ets.insert(@table, {:total_calls, 0})
    :ets.insert(@table, {:total_tokens, 0})
    :ok
  end

  @doc """
  Track an LLM call. Returns :ok or {:over_budget, reason}.
  """
  def track_call(agent_id, token_count, _tick) do
    total_calls = get_counter(:total_calls)

    if total_calls >= @max_calls_per_session do
      {:over_budget, :session_limit}
    else
      agent_key = {:agent_tokens, agent_id}
      agent_tokens = get_counter(agent_key)

      if agent_tokens + token_count > @max_tokens_per_agent do
        {:over_budget, :agent_limit}
      else
        :ets.update_counter(@table, :total_calls, {2, 1}, {:total_calls, 0})
        :ets.update_counter(@table, :total_tokens, {2, token_count}, {:total_tokens, 0})
        :ets.update_counter(@table, agent_key, {2, token_count}, {agent_key, 0})
        :ok
      end
    end
  end

  @doc "Remaining calls for the session."
  def remaining do
    max(@max_calls_per_session - get_counter(:total_calls), 0)
  end

  @doc "Remaining tokens for an agent."
  def remaining(agent_id) do
    agent_key = {:agent_tokens, agent_id}
    max(@max_tokens_per_agent - get_counter(agent_key), 0)
  end

  @doc "Reset all budgets."
  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
      :ets.insert(@table, {:total_calls, 0})
      :ets.insert(@table, {:total_tokens, 0})
    end

    :ok
  end

  @doc "Get budget statistics."
  def stats do
    total_calls = get_counter(:total_calls)
    total_tokens = get_counter(:total_tokens)

    agent_budgets =
      if :ets.whereis(@table) != :undefined do
        :ets.tab2list(@table)
        |> Enum.filter(fn
          {{:agent_tokens, _}, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {{:agent_tokens, id}, tokens} ->
          %{agent_id: id, tokens_used: tokens, tokens_remaining: max(@max_tokens_per_agent - tokens, 0)}
        end)
      else
        []
      end

    %{
      total_calls: total_calls,
      total_tokens: total_tokens,
      calls_remaining: max(@max_calls_per_session - total_calls, 0),
      max_calls: @max_calls_per_session,
      max_tokens_per_agent: @max_tokens_per_agent,
      agents: agent_budgets
    }
  end

  defp get_counter(key) do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, key) do
        [{_, val}] -> val
        [] -> 0
      end
    else
      0
    end
  end
end
