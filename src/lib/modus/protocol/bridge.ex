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
    greeting = pick_greeting(agent.personality)
    mood = mood_expression(agent.affect_state, agent.needs)
    activity = activity_description(agent.current_action, agent.personality)
    "#{greeting} #{mood} #{activity}" |> String.trim()
  end

  defp pick_greeting(personality) do
    if ensure_float(personality.extraversion) > 0.6 do
      Enum.random(["Hey there!", "Oh, hi!", "Well hello!", "Hey hey!", "Oh! You're here!"])
    else
      Enum.random(["Oh... hello.", "Hi.", "Hey.", "Ah, hi there.", "*nods* Hello."])
    end
  end

  defp mood_expression(affect, needs) do
    hunger = ensure_float(needs.hunger)
    rest = ensure_float(needs.rest)

    cond do
      hunger > 70 ->
        Enum.random(["I'm so hungry I can barely think.", "My stomach won't shut up...", "I'd do anything for a bite to eat right now."])
      rest > 70 ->
        Enum.random(["I'm barely keeping my eyes open.", "So tired...", "I could sleep standing up right now."])
      true -> affect_expression(affect)
    end
  end

  defp affect_expression(:joy), do: Enum.random(["What a beautiful day!", "I'm feeling great, actually!", "Things are going really well.", "Life is good right now!"])
  defp affect_expression(:sadness), do: Enum.random(["Things have been tough...", "I've been better, honestly.", "Not my best day.", "*sighs* It's been a lot."])
  defp affect_expression(:fear), do: Enum.random(["Something doesn't feel right...", "I'm a bit on edge.", "I keep looking over my shoulder.", "It's... unsettling out here."])
  defp affect_expression(:desire), do: Enum.random(["I've got this restless energy!", "I feel like I need to DO something.", "There's so much I want to get done."])
  defp affect_expression(_), do: Enum.random(["Can't complain.", "Just another day.", "Things are... fine.", "All quiet here."])

  defp activity_description(action, personality) do
    extraverted = ensure_float(personality.extraversion) > 0.6

    case action do
      :exploring ->
        if extraverted,
          do: Enum.random(["Just wandering around, seeing what's out here!", "Exploring — you never know who you'll run into!"]),
          else: Enum.random(["Taking a quiet walk, just me and my thoughts.", "Exploring a bit on my own."])
      :gathering ->
        Enum.random(["Looking for something to eat — I'm starving!", "Foraging around, gotta stock up.", "Trying to find some food."])
      :sleeping ->
        Enum.random(["Just woke up, still groggy...", "Was napping — or trying to.", "Resting my eyes... or I was."])
      :talking ->
        Enum.random(["Was just chatting with someone.", "In the middle of a conversation, actually.", "Having a good talk."])
      :fleeing ->
        Enum.random(["I was running — something spooked me!", "Just got out of a scary situation.", "My heart's still pounding!"])
      _ ->
        if extraverted,
          do: Enum.random(["Not doing much — want to hang out?", "Just killing time, honestly.", "Waiting for something interesting to happen!"]),
          else: Enum.random(["Just... being here.", "Taking it easy.", "Nothing much going on."])
    end
  end
end
