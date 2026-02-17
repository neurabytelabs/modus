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

  alias Modus.Intelligence.{BehaviorTree, DecisionCache, OllamaClient}
  alias Modus.Simulation.Agent

  require Logger

  @type decision :: {atom(), map()}

  @llm_interval 100
  @llm_batch_size 3

  @doc """
  Decide an agent's next action given context.

  Decision pipeline:
  1. Check LLM cache for a recent decision
  2. Every #{@llm_interval} ticks, batch LLM decisions for up to #{@llm_batch_size} agents
  3. Fall back to BehaviorTree + resolve

  Context map may contain:
  - `:tick` — current tick number
  - `:nearby_agents` — list of agent ids within perception radius
  - `:nearby_resources` — list of {type, position, amount} tuples
  - `:world_size` — {max_x, max_y}
  """
  @spec decide(Agent.t(), map()) :: decision()
  def decide(%Agent{} = agent, context \\ %{}) do
    tick = Map.get(context, :tick, 0)

    # Check cache first
    case DecisionCache.get(agent.id) do
      {action, params} ->
        {action, params}

      nil ->
        # Behavior tree is the reliable fallback
        bt_action = BehaviorTree.evaluate(agent, tick)
        resolve(bt_action, agent, context)
    end
  end

  @doc """
  Run LLM batch decisions for a list of agents. Call this from the Ticker
  every #{@llm_interval} ticks. Caches results for individual decide/2 lookups.
  """
  @spec llm_batch([Agent.t()], map()) :: :ok
  def llm_batch(agents, context) do
    batch = Enum.take(agents, @llm_batch_size)

    case OllamaClient.batch_decide(batch, context) do
      :fallback ->
        :ok

      decisions when is_list(decisions) ->
        for {agent_id, action, params} <- decisions do
          resolved = resolve(action, find_agent(agent_id, batch), context, params)
          DecisionCache.put(agent_id, resolved)
        end
        :ok
    end
  end

  @doc "Check if this tick should trigger an LLM batch."
  @spec llm_tick?(non_neg_integer()) :: boolean()
  def llm_tick?(tick), do: rem(tick, @llm_interval) == 0 and tick > 0

  defp find_agent(id, agents) do
    Enum.find(agents, %Agent{id: id, position: {0, 0}, personality: %{}, needs: %{hunger: 50, social: 50, rest: 50}, current_action: :idle}, fn a -> a.id == id end)
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

  defp resolve(:build, agent, _context) do
    # Build at current position
    {:build, %{position: agent.position}}
  end

  defp resolve(:go_home, agent, _context) do
    alias Modus.Simulation.Building
    case Building.get_home(agent.id) do
      nil -> {:idle, %{}}
      home -> {:move_to, %{target: home.position, intent: :go_home}}
    end
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

  # Resolve with extra LLM params merged in
  defp resolve(action, agent, context, extra_params) do
    {resolved_action, params} = resolve(action, agent, context)
    {resolved_action, Map.merge(params, extra_params)}
  end

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
