defmodule Modus.Mind.DreamPromptBuilder do
  @moduledoc """
  Builds LLM prompts for dream generation.

  Combines episodic memories, affect state, personality traits, and relationships
  into a surreal dream prompt. Dreams mix real memories with imagination,
  producing 2-3 sentence narratives.
  """

  @doc "Build a dream generation prompt from agent context."
  @spec build(map(), list(), list(), atom()) :: String.t()
  def build(agent, episodic_memories, affect_memories, dream_type) do
    agent_name = Map.get(agent, :name, "the agent")
    personality = format_personality(agent)
    memories_text = format_episodic(episodic_memories)
    affects_text = format_affects(affect_memories)
    type_instruction = type_directive(dream_type)

    """
    You are a dream narrator for a simulated agent named #{agent_name}.
    Generate a surreal dream in 2-3 sentences that mixes real memories with imagination.

    #{type_instruction}

    Personality: #{personality}

    Recent memories:
    #{memories_text}

    Emotional transitions:
    #{affects_text}

    Write the dream in third person. Be poetic and surreal. Do not explain the dream.
    """
  end

  @doc "Format personality traits from agent map."
  @spec format_personality(map()) :: String.t()
  def format_personality(agent) do
    personality = Map.get(agent, :personality, %{})

    if map_size(personality) == 0 do
      "unknown temperament"
    else
      personality
      |> Enum.map(fn {k, v} -> "#{k}: #{Float.round(v * 1.0, 2)}" end)
      |> Enum.join(", ")
    end
  end

  @spec format_episodic(list()) :: String.t()
  defp format_episodic([]), do: "- No recent memories"

  defp format_episodic(memories) do
    memories
    |> Enum.take(5)
    |> Enum.map(fn m ->
      content = if is_map(m), do: Map.get(m, :content, "..."), else: "..."
      "- #{content}"
    end)
    |> Enum.join("\n")
  end

  @spec format_affects(list()) :: String.t()
  defp format_affects([]), do: "- Emotionally calm"

  defp format_affects(memories) do
    memories
    |> Enum.take(5)
    |> Enum.map(fn m ->
      from = Map.get(m, :affect_from, :unknown)
      to = Map.get(m, :affect_to, :unknown)
      reason = Map.get(m, :reason, "")
      "- #{from} → #{to} (#{reason})"
    end)
    |> Enum.join("\n")
  end

  @spec type_directive(atom()) :: String.t()
  defp type_directive(:nightmare) do
    "This is a NIGHTMARE. The dream should feel anxious, threatening, with distorted familiar elements."
  end

  defp type_directive(:social) do
    "This is a SOCIAL dream. Focus on relationships, conversations, and faces of known agents."
  end

  defp type_directive(:pleasant) do
    "This is a PLEASANT dream. The dream should feel warm, safe, with gentle surreal imagery."
  end
end
