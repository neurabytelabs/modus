defmodule Modus.Interaction.AgentOutreach do
  @moduledoc """
  Agent-Initiated Conversations — agents can reach out to the player.

  Trigger conditions (checked every 50 ticks):
    - conatus_energy < 0.3 → "Yardım eder misin?"
    - trust >= :trusted and milestone → "Bak ne yaptım!"
    - affect = :fear → "Korkuyorum..."

  Cooldown: 200 ticks per agent.
  """

  alias Modus.Mind.Trust

  @table :modus_outreach
  @cooldown 200
  @check_interval 50

  @doc "Initialize ETS table."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Check if an agent should send an outreach message. Returns nil or message map."
  @spec check_outreach(map(), integer()) :: nil | map()
  def check_outreach(_agent_state, tick) when rem(tick, @check_interval) != 0, do: nil

  def check_outreach(agent_state, tick) do
    agent_id = agent_state[:id] || agent_state[:agent_id]

    if on_cooldown?(agent_id, tick) do
      nil
    else
      message = generate_message(agent_state)

      if message do
        record = %{agent_id: agent_id, message: message.text, type: message.type, tick: tick}
        :ets.insert(@table, {agent_id, record})
        record
      end
    end
  end

  @doc "Get all pending outreach messages."
  @spec pending_messages() :: [map()]
  def pending_messages do
    :ets.tab2list(@table) |> Enum.map(fn {_id, record} -> record end)
  end

  @doc "Clear pending message for an agent."
  @spec clear_pending(String.t()) :: :ok
  def clear_pending(agent_id) do
    :ets.delete(@table, agent_id)
    :ok
  end

  @doc "Reset all outreach data."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  defp on_cooldown?(agent_id, current_tick) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, %{tick: last_tick}}] -> current_tick - last_tick < @cooldown
      _ -> false
    end
  end

  defp generate_message(agent_state) do
    name = agent_state[:name] || "Agent"
    energy = agent_state[:conatus_energy] || 1.0
    affect = agent_state[:affect_state] || :neutral
    agent_id = agent_state[:id] || agent_state[:agent_id] || ""
    trust_level = Trust.trust_level(agent_id)

    cond do
      energy < 0.3 ->
        %{text: "#{name}: Yardım eder misin? Enerjim çok düşük...", type: :help_request}

      affect == :fear ->
        %{text: "#{name}: Korkuyorum... Yanımda olur musun?", type: :fear}

      trust_level in [:trusted, :bonded] ->
        %{text: "#{name}: Hey! Sana bir şey göstermek istiyorum.", type: :milestone}

      true ->
        nil
    end
  end
end
