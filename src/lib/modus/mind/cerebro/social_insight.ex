defmodule Modus.Mind.Cerebro.SocialInsight do
  @moduledoc "Converts ETS social network data into human-readable context for LLM"

  alias Modus.Mind.Cerebro.SocialNetwork
  alias Modus.Mind.AffectMemory
  alias Modus.Simulation.Agent

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @doc "Generate a text summary of an agent's social context."
  def describe_relationships(agent_id) do
    friends = SocialNetwork.get_friends(agent_id, 0.1)

    if friends == [] do
      "You don't know anyone yet."
    else
      friends
      |> Enum.take(5)
      |> Enum.map(fn f ->
        name = get_agent_name(f.id)
        strength = Float.round(ensure_float(f.strength), 2)

        case f.type do
          :close_friend -> "#{name} is your close friend (strength: #{strength})."
          :friend -> "#{name} is your friend (strength: #{strength})."
          :acquaintance -> "You know #{name} but aren't close (strength: #{strength})."
          _ -> "You just met #{name}."
        end
      end)
      |> Enum.join(" ")
    end
  end

  @doc "Describe relationship between two specific agents."
  def describe_relationship(agent_id, other_id, other_name) do
    case SocialNetwork.get_relationship(agent_id, other_id) do
      nil ->
        "You haven't met #{other_name} before."

      %{type: type, strength: strength, convo_count: count} ->
        type_text = case type do
          :close_friend -> "your close friend"
          :friend -> "your friend"
          :acquaintance -> "an acquaintance"
          _ -> "someone you just met"
        end
        "#{other_name} is #{type_text} (strength: #{Float.round(ensure_float(strength), 2)}). You've talked #{count} times."

      %{type: type, strength: strength} ->
        type_text = case type do
          :close_friend -> "your close friend"
          :friend -> "your friend"
          :acquaintance -> "an acquaintance"
          _ -> "someone you just met"
        end
        "#{other_name} is #{type_text} (strength: #{Float.round(ensure_float(strength), 2)})."
    end
  end

  @doc "Get shared memories between two agents (spatial proximity)."
  def shared_context(agent_id, other_id) do
    memories_a = AffectMemory.recall(agent_id, limit: 20)
    memories_b = AffectMemory.recall(other_id, limit: 20)

    # Find memories at similar positions (within 3 tiles)
    shared = for ma <- memories_a, mb <- memories_b,
      {ax, ay} = ma.position, {bx, by} = mb.position,
      abs(ax - bx) <= 3 and abs(ay - by) <= 3,
      do: {ma, mb}

    shared
    |> Enum.take(3)
    |> Enum.map(fn {ma, _mb} ->
      {x, y} = ma.position
      "Tick #{ma.tick}: together near (#{x},#{y}) — #{ma.reason}"
    end)
  end

  defp get_agent_name(agent_id) do
    try do
      state = Agent.get_state(agent_id)
      state.name
    catch
      :exit, _ -> "Unknown"
    end
  end
end
