defmodule Modus.Mind.Trust do
  @moduledoc """
  Trust — ETS-based trust tracker for agent-player relationships.

  Trust levels:
    :stranger  (0-25)
    :known     (25-50)
    :trusted   (50-75)
    :bonded    (75-100)
  """

  @table :modus_agent_trust
  @max_trust 100
  @min_trust 0

  @doc "Initialize the ETS table. Call from Application.start/2."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Get trust value for an agent (default 0)."
  @spec get_trust(String.t()) :: integer()
  def get_trust(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, trust}] -> trust
      [] -> 0
    end
  end

  @doc "Update trust by delta (clamped 0-100)."
  @spec update_trust(String.t(), integer()) :: integer()
  def update_trust(agent_id, delta) do
    current = get_trust(agent_id)
    new_trust = current |> Kernel.+(delta) |> max(@min_trust) |> min(@max_trust)
    :ets.insert(@table, {agent_id, new_trust})
    new_trust
  end

  @doc "Get trust level atom for an agent."
  @spec trust_level(String.t()) :: :stranger | :known | :trusted | :bonded
  def trust_level(agent_id) do
    trust_value_to_level(get_trust(agent_id))
  end

  @doc "Convert a trust value to a level atom."
  @spec trust_value_to_level(integer()) :: :stranger | :known | :trusted | :bonded
  def trust_value_to_level(value) when value >= 75, do: :bonded
  def trust_value_to_level(value) when value >= 50, do: :trusted
  def trust_value_to_level(value) when value >= 25, do: :known
  def trust_value_to_level(_), do: :stranger

  @doc "Get all trust entries."
  @spec all_trusts() :: [{String.t(), integer()}]
  def all_trusts do
    :ets.tab2list(@table)
  end

  @doc "Reset all trust data."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Build trust context string for LLM prompt injection."
  @spec context_for_prompt(String.t()) :: String.t()
  def context_for_prompt(agent_id) do
    level = trust_level(agent_id)
    trust = get_trust(agent_id)

    base = "The player is at #{level} trust level (#{trust}/100) with you."

    extra =
      case level do
        :bonded -> " You are deeply bonded. You would mourn their absence and initiate conversations."
        :trusted -> " You trust them. You can share secrets and ask for help."
        :known -> " You know them by name. You're warming up to them."
        :stranger -> " They are a stranger. Be polite but guarded."
      end

    base <> extra
  end
end
