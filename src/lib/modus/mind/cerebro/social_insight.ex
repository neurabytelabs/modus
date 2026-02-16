defmodule Modus.Mind.Cerebro.SocialInsight do
  @moduledoc "Converts ETS social network data into human-readable context for LLM"

  alias Modus.Mind.Cerebro.SocialNetwork
  alias Modus.Mind.AffectMemory
  alias Modus.Simulation.Agent

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @doc "Generate a Turkish text summary of an agent's social context."
  def describe_relationships(agent_id) do
    friends = SocialNetwork.get_friends(agent_id, 0.1)

    if friends == [] do
      "Henüz kimseyi tanımıyorsun."
    else
      friends
      |> Enum.take(5)
      |> Enum.map(fn f ->
        name = get_agent_name(f.id)
        strength = Float.round(ensure_float(f.strength), 2)

        case f.type do
          :close_friend -> "#{name} senin yakın arkadaşın (güç: #{strength})."
          :friend -> "#{name} arkadaşın (güç: #{strength})."
          :acquaintance -> "#{name}'i tanıyorsun ama yakın değilsiniz (güç: #{strength})."
          _ -> "#{name} ile yeni tanışıyorsun."
        end
      end)
      |> Enum.join(" ")
    end
  end

  @doc "Describe relationship between two specific agents."
  def describe_relationship(agent_id, other_id, other_name) do
    case SocialNetwork.get_relationship(agent_id, other_id) do
      nil ->
        "#{other_name} ile daha önce tanışmadınız."

      %{type: type, strength: strength, convo_count: count} ->
        type_text = case type do
          :close_friend -> "yakın arkadaşın"
          :friend -> "arkadaşın"
          :acquaintance -> "tanıdığın"
          _ -> "yeni tanıştığın biri"
        end
        "#{other_name} senin #{type_text} (güç: #{Float.round(ensure_float(strength), 2)}). #{count} kez konuştunuz."

      %{type: type, strength: strength} ->
        type_text = case type do
          :close_friend -> "yakın arkadaşın"
          :friend -> "arkadaşın"
          :acquaintance -> "tanıdığın"
          _ -> "yeni tanıştığın biri"
        end
        "#{other_name} senin #{type_text} (güç: #{Float.round(ensure_float(strength), 2)})."
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
      "Tick #{ma.tick}: (#{x},#{y}) yakınında birlikte — #{ma.reason}"
    end)
  end

  defp get_agent_name(agent_id) do
    try do
      state = Agent.get_state(agent_id)
      state.name
    catch
      :exit, _ -> "Bilinmeyen"
    end
  end
end
