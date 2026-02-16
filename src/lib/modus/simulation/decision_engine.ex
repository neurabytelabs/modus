defmodule Modus.Simulation.DecisionEngine do
  @moduledoc """
  DecisionEngine — Translates behavior tree outputs into concrete actions.

  The decision pipeline:
  1. BehaviorTree.evaluate/2 → abstract action
  2. DecisionEngine.decide/2  → contextualized {action, params}

  Future: LLM layer for creative/social decisions.

  ## Actions

  - `{:idle, %{}}`
  - `{:move_to, %{target: {x, y}}}`
  - `{:gather, %{resource_type: atom, target: {x, y}}}`
  - `{:talk, %{target_agent: id}}`
  - `{:sleep, %{}}`
  - `{:explore, %{target: {x, y}}}`
  - `{:flee, %{from: {x, y}}}`
  """

  alias Modus.Intelligence.BehaviorTree
  alias Modus.Simulation.Agent

  @type decision :: {atom(), map()}

  @doc """
  Decide an agent's next action given context.

  Context map may contain:
  - `:tick` — current tick number
  - `:nearby_agents` — list of agent ids within perception radius
  - `:nearby_resources` — list of {type, position, amount} tuples
  - `:world_size` — {max_x, max_y}
  """
  @spec decide(Agent.t(), map()) :: decision()
  def decide(%Agent{} = agent, context \\ %{}) do
    tick = Map.get(context, :tick, 0)

    agent
    |> BehaviorTree.evaluate(tick)
    |> resolve(agent, context)
  end

  # ── Action Resolution ───────────────────────────────────────

  @spec resolve(atom(), Agent.t(), map()) :: decision()

  defp resolve(:find_food, agent, context) do
    case find_nearest_resource(:food, agent.position, context) do
      nil -> {:explore, %{target: random_nearby(agent.position, context)}}
      pos -> {:move_to, %{target: pos, intent: :gather_food}}
    end
  end

  defp resolve(:go_home_sleep, _agent, _context) do
    {:sleep, %{}}
  end

  defp resolve(:find_friend, agent, context) do
    case Map.get(context, :nearby_agents, []) do
      [] -> {:explore, %{target: random_nearby(agent.position, context)}}
      agents -> {:talk, %{target_agent: Enum.random(agents)}}
    end
  end

  defp resolve(:explore, agent, context) do
    {:explore, %{target: random_nearby(agent.position, context)}}
  end

  defp resolve(:help_nearby, agent, context) do
    case Map.get(context, :nearby_agents, []) do
      [] -> {:idle, %{}}
      agents -> {:move_to, %{target: agent.position, intent: :help, target_agent: Enum.random(agents)}}
    end
  end

  defp resolve(:gather, agent, context) do
    case find_nearest_resource(:any, agent.position, context) do
      nil -> {:idle, %{}}
      pos -> {:gather, %{target: pos}}
    end
  end

  defp resolve(:idle, _agent, _context) do
    {:idle, %{}}
  end

  defp resolve(:flee, agent, context) do
    threat = Map.get(context, :threat_position, agent.position)
    {ax, ay} = agent.position
    {tx, ty} = threat
    flee_target = {ax + (ax - tx), ay + (ay - ty)}
    {:flee, %{from: threat, target: flee_target}}
  end

  defp resolve(_unknown, _agent, _context), do: {:idle, %{}}

  # ── Helpers ─────────────────────────────────────────────────

  defp find_nearest_resource(type, {ax, ay}, context) do
    resources = Map.get(context, :nearby_resources, [])

    resources
    |> Enum.filter(fn {rtype, _pos, amount} ->
      amount > 0 and (type == :any or rtype == type)
    end)
    |> Enum.min_by(fn {_type, {rx, ry}, _amount} ->
      abs(rx - ax) + abs(ry - ay)
    end, fn -> nil end)
    |> case do
      nil -> nil
      {_type, pos, _amount} -> pos
    end
  end

  defp random_nearby({ax, ay}, context) do
    {max_x, max_y} = Map.get(context, :world_size, {50, 50})
    dx = Enum.random(-5..5)
    dy = Enum.random(-5..5)
    {max(0, min(ax + dx, max_x - 1)), max(0, min(ay + dy, max_y - 1))}
  end
end
