defmodule Modus.Protocol.Bridge do
  @moduledoc "Orchestrates the full user→agent interaction pipeline"

  alias Modus.Protocol.IntentParser
  alias Modus.Mind.{ContextBuilder, Perception}
  alias Modus.Mind.Cerebro.SocialInsight
  alias Modus.Intelligence.LlmProvider
  alias Modus.Simulation.Agent

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @doc "Main entry point: process a user message to an agent."
  def process(agent_id, user_message) do
    agent = Agent.get_state(agent_id)
    intent = IntentParser.parse(user_message)

    case intent do
      {:chat, text} ->
        system_prompt = ContextBuilder.build_chat_prompt(agent, text)
        result = case chat_with_context(agent, text, system_prompt) do
          {:ok, reply} ->
            Modus.Mind.ConversationMemory.record(agent_id, "user", [{agent.name, reply}], 0)
            {:ok, reply}
          _ -> {:ok, fallback_reply(agent)}
        end
        result

      {:query, :location} ->
        perception = Perception.snapshot(agent)
        {x, y} = perception.position
        terrain = ContextBuilder.terrain_name(perception.terrain)
        nearby_names = perception.nearby_agents |> Enum.map(& &1.name) |> Enum.join(", ")
        reply = "I'm in the #{terrain} area, coordinates (#{x}, #{y}).#{if nearby_names != "", do: " #{nearby_names} are nearby.", else: " Nobody's around."}"
        {:ok, reply}

      {:query, :status} ->
        perception = Perception.snapshot(agent)
        energy_pct = round(ensure_float(perception.conatus_energy) * 100)
        affect = ContextBuilder.affect_name(perception.affect_state)
        reply = "My energy is #{energy_pct}%, feeling #{affect}. Hunger: #{round(ensure_float(perception.needs.hunger))}, Rest: #{round(ensure_float(perception.needs.rest))}."
        {:ok, reply}

      {:query, :relationships} ->
        social = SocialInsight.describe_relationships(agent_id)
        {:ok, social}

      {:command, :move, direction} ->
        target = calculate_move_target(agent.position, direction)
        Agent.move_toward(agent_id, target)
        {:ok, "Alright, heading #{direction_name(direction)}!"}

      {:command, :stop} ->
        {:ok, "Stopped, taking a break."}

      {:multi, steps} ->
        Modus.Protocol.CommandExecutor.execute_chain(agent_id, steps)
        |> case do
          {:ok, results} ->
            summary = results |> Enum.map(fn {:ok, r} -> r; r -> inspect(r) end) |> Enum.join(" → ")
            {:ok, summary}
          err -> {:ok, "Error in command chain: #{inspect(err)}"}
        end

      _ ->
        {:ok, fallback_reply(agent)}
    end
  end

  defp chat_with_context(_agent, user_message, system_prompt) do
    config = LlmProvider.get_config()
    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_message}
    ]

    case config.provider do
      :antigravity ->
        Modus.Intelligence.AntigravityClient.chat_completion_direct(messages, config)
      :ollama ->
        Modus.Intelligence.OllamaClient.chat_completion_direct(messages, config)
      _ -> :fallback
    end
  end

  defp calculate_move_target({x, y}, :north), do: {x, max(y - 10, 0)}
  defp calculate_move_target({x, y}, :south), do: {x, min(y + 10, 49)}
  defp calculate_move_target({x, y}, :east), do: {min(x + 10, 49), y}
  defp calculate_move_target({x, y}, :west), do: {max(x - 10, 0), y}

  defp direction_name(:north), do: "north"
  defp direction_name(:south), do: "south"
  defp direction_name(:east), do: "east"
  defp direction_name(:west), do: "west"

  defp fallback_reply(agent) do
    "Hello! I'm #{agent.name}. Currently #{agent.current_action}."
  end
end
