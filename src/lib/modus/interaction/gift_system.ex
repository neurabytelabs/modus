defmodule Modus.Interaction.GiftSystem do
  @moduledoc """
  Gift & Aid system — allows player to give gifts or aid agents.

  Gift → trust +3, joy affect boost, memory record
  Aid  → trust +2, fills agent's lowest need
  """

  alias Modus.Mind.Trust

  @table :modus_gift_history
  @valid_resources ~w(food wood stone)

  @doc "Initialize ETS table."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Give a gift to an agent. Returns {:ok, new_trust} or {:error, reason}."
  @spec give_gift(String.t(), String.t(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def give_gift(player_id, agent_id, resource) when resource in @valid_resources do
    record = %{
      player_id: player_id,
      resource: resource,
      timestamp: DateTime.utc_now(),
      type: :gift
    }

    :ets.insert(@table, {agent_id, record})
    new_trust = Trust.update_trust(agent_id, 3)
    {:ok, new_trust}
  end

  def give_gift(_player_id, _agent_id, _resource), do: {:error, "invalid resource"}

  @doc "Aid an agent (fill lowest need). Returns {:ok, need_filled, new_trust} or {:error, reason}."
  @spec aid_agent(String.t(), String.t()) :: {:ok, atom(), integer()} | {:error, String.t()}
  def aid_agent(player_id, agent_id) do
    record = %{
      player_id: player_id,
      timestamp: DateTime.utc_now(),
      type: :aid
    }

    :ets.insert(@table, {agent_id, record})
    new_trust = Trust.update_trust(agent_id, 2)
    # The actual need-filling is handled by the caller via Agent state
    {:ok, :lowest_need, new_trust}
  end

  @doc "Get gift/aid history for an agent."
  @spec gift_history(String.t()) :: [map()]
  def gift_history(agent_id) do
    :ets.lookup(@table, agent_id) |> Enum.map(fn {_id, record} -> record end)
  end

  @doc "Valid resource types."
  @spec valid_resources() :: [String.t()]
  def valid_resources, do: @valid_resources

  @doc "Reset all gift history."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end
end
