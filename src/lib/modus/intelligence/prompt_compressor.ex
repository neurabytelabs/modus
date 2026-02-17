defmodule Modus.Intelligence.PromptCompressor do
  @moduledoc """
  PromptCompressor — Minimizes token usage in LLM prompts.

  Strategies:
  - Abbreviate agent descriptions
  - Remove redundant context
  - Use compact JSON format instructions
  - Limit memory context
  """

  @doc "Build a compressed batch prompt for multiple agents."
  def compress_batch(agents, tick) do
    descs = agents
    |> Enum.map(&compress_agent/1)
    |> Enum.join("\n")

    """
    Decision engine for village sim. Choose actions for agents.
    T:#{tick}
    #{descs}
    Actions:idle,explore,gather,find_food,sleep,socialize,help,flee,talk
    JSON:{"decisions":[{"id":"<id>","action":"<act>","reason":"<why>"}]}
    Match personality+needs.
    """
  end

  @doc "Compress a single agent description to minimal tokens."
  def compress_agent(agent) do
    {x, y} = agent.position
    p = agent.personality
    n = agent.needs
    "#{agent.id}|#{agent.name}|#{x},#{y}|#{agent.occupation}|h#{ri(n.hunger)}s#{ri(n.social)}r#{ri(n.rest)}|O#{rf(p.openness)}C#{rf(p.conscientiousness)}E#{rf(p.extraversion)}A#{rf(p.agreeableness)}N#{rf(p.neuroticism)}|#{agent.current_action}"
  end

  @doc "Compress conversation prompt."
  def compress_conversation(agent_a, agent_b) do
    """
    Village sim. 3-turn chat between #{agent_a.name}(#{agent_a.occupation}) and #{agent_b.name}(#{agent_b.occupation}).
    #{agent_a.name}:h#{ri(agent_a.needs.hunger)}s#{ri(agent_a.needs.social)}
    #{agent_b.name}:h#{ri(agent_b.needs.hunger)}s#{ri(agent_b.needs.social)}
    JSON:{"dialogue":[{"speaker":"<name>","line":"<text>"}]}
    Short lines (<30 words).
    """
  end

  defp ri(val) when is_number(val), do: round(val) |> Integer.to_string()
  defp ri(_), do: "0"

  defp rf(val) when is_number(val), do: Float.round(val * 1.0, 1) |> Float.to_string()
  defp rf(_), do: "0.0"
end
