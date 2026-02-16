defmodule Modus.Mind.ReasoningEngine do
  @moduledoc "LLM-driven reasoning cycle — triggered when agents experience persistent sadness."

  alias Modus.Mind.AffectMemory
  require Logger

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @persistent_ticks 50

  def should_reason?(agent) do
    agent.affect_state == :sadness and persistent_affect?(agent, @persistent_ticks)
  end

  defp persistent_affect?(agent, ticks) do
    case agent.affect_history do
      [] -> false
      [latest | _] ->
        # No affect change in the last N ticks
        latest.to == :sadness and
          Enum.all?(Enum.take(agent.affect_history, 5), fn h -> h.to == :sadness end)
    end
  end

  def reason(agent) do
    memories = AffectMemory.memories_for_llm_context(agent.id, 5)
    prompt = build_reasoning_prompt(agent, memories)

    # Try LLM non-blocking, fallback if unavailable
    try do
      case GenServer.call(Modus.Intelligence.LlmProvider, {:chat, agent, prompt}, 10_000) do
        {:ok, text} -> {:ok, text}
        _ -> {:ok, fallback_reasoning()}
      end
    catch
      :exit, _ -> {:ok, fallback_reasoning()}
    end
  end

  def build_reasoning_prompt(agent, memories) do
    personality_desc = "Openness: #{Float.round(ensure_float(agent.personality.openness), 2)}, " <>
      "Extraversion: #{Float.round(ensure_float(agent.personality.extraversion), 2)}, " <>
      "Neuroticism: #{Float.round(ensure_float(agent.personality.neuroticism), 2)}"

    memory_lines = case memories do
      [] -> "No significant memories."
      lines -> Enum.join(lines, "\n")
    end

    """
    You are #{agent.name}, a #{agent.occupation} in a simulated world.
    Personality: #{personality_desc}
    Current state: feeling #{agent.affect_state}, conatus energy #{Float.round(ensure_float(agent.conatus_energy), 2)}.
    Position: #{inspect(agent.position)}

    Recent emotional memories:
    #{memory_lines}

    You have been sad for a while. What should you do to feel better?
    Respond in one short sentence describing your next action.
    """
  end

  defp fallback_reasoning do
    Enum.random([
      "I should seek social contact.",
      "Perhaps exploring a new area would lift my spirits.",
      "I need to find food and take care of myself.",
      "Maybe resting would help me recover.",
      "I should find a friend to talk to."
    ])
  end
end
