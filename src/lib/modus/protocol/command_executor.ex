defmodule Modus.Protocol.CommandExecutor do
  @moduledoc "Multi-step command chain executor"

  alias Modus.Protocol.Bridge
  alias Modus.Simulation.Agent

  @doc "Execute a chain of commands sequentially for an agent"
  def execute_chain(agent_id, commands) when is_list(commands) do
    results =
      Enum.reduce(commands, [], fn cmd, acc ->
        result = execute_step(agent_id, cmd)
        [result | acc]
      end)

    {:ok, Enum.reverse(results)}
  end

  def execute_step(agent_id, {:command, :move, direction}) do
    Bridge.process(agent_id, direction_to_text(direction))
  end

  def execute_step(agent_id, {:command, :talk_nearby}) do
    agent = Agent.get_state(agent_id)
    # Find nearest agent and initiate conversation
    nearby = get_nearby_agents(agent)

    case nearby do
      [target | _] ->
        Bridge.process(agent_id, "Hello #{Map.get(target, :name)}!")

      [] ->
        {:ok, "Nobody around to talk to."}
    end
  end

  def execute_step(agent_id, {:command, :stop}), do: Bridge.process(agent_id, "dur")
  def execute_step(agent_id, {:chat, text}), do: Bridge.process(agent_id, text)
  def execute_step(_agent_id, _), do: {:ok, "I don't understand that command."}

  defp get_nearby_agents(agent) do
    try do
      Modus.Mind.Perception.snapshot(agent).nearby_agents
    catch
      _, _ -> []
    end
  end

  defp direction_to_text(:north), do: "go north"
  defp direction_to_text(:south), do: "go south"
  defp direction_to_text(:east), do: "go east"
  defp direction_to_text(:west), do: "go west"
end
