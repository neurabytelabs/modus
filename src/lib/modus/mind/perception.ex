defmodule Modus.Mind.Perception do
  @moduledoc "Builds a snapshot of what an agent perceives right now"

  alias Modus.Mind.Cerebro.SocialNetwork
  alias Modus.Simulation.{Agent, World}

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @doc "Build a perception map from an agent struct."
  def snapshot(agent) do
    position = agent.position
    terrain = get_terrain_at(position)
    nearby = nearby_with_context(agent.id, position)

    %{
      position: position,
      terrain: terrain,
      nearby_agents: nearby,
      nearby_resources: get_resources_at(position),
      conatus_energy: ensure_float(agent.conatus_energy),
      affect_state: agent.affect_state,
      needs: %{
        hunger: ensure_float(agent.needs.hunger),
        social: ensure_float(agent.needs.social),
        rest: ensure_float(agent.needs.rest),
        shelter: ensure_float(Map.get(agent.needs, :shelter, 70.0))
      },
      current_action: agent.current_action
    }
  end

  @doc "Get terrain type at a position from World ETS."
  def get_terrain_at(position) do
    if Process.whereis(World) do
      case World.get_cell(position) do
        {:ok, %{terrain: terrain}} -> terrain
        _ -> :grass
      end
    else
      :grass
    end
  end

  @doc "Get resources at a position from World ETS."
  def get_resources_at(position) do
    if Process.whereis(World) do
      case World.get_cell(position) do
        {:ok, %{resources: resources}} -> resources
        _ -> %{}
      end
    else
      %{}
    end
  end

  @doc "Get nearby agents with enriched context (name, affect, relationship type)."
  def nearby_with_context(agent_id, position, radius \\ 5) do
    {px, py} = position

    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.filter(fn
      {id, {ax, ay, true}} ->
        id != agent_id and abs(ax - px) <= radius and abs(ay - py) <= radius
      _ -> false
    end)
    |> Enum.map(fn {id, {ax, ay, _}} ->
      distance = abs(ax - px) + abs(ay - py)
      {id, distance}
    end)
    |> Enum.sort_by(fn {_id, d} -> d end)
    |> Enum.take(5)
    |> Enum.map(fn {id, distance} ->
      {name, affect} = try do
        state = Agent.get_state(id)
        {state.name, state.affect_state}
      catch
        :exit, _ -> {"Unknown", :neutral}
      end

      rel_type = case SocialNetwork.get_relationship(agent_id, id) do
        nil -> :stranger
        %{type: type} -> type
        _ -> :stranger
      end

      %{id: id, name: name, distance: distance, affect: affect, relationship_type: rel_type}
    end)
  end
end
