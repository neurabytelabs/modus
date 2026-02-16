defmodule Modus.Simulation.Agent do
  @moduledoc """
  Agent — A living entity in the MODUS universe.

  Each agent is a GenServer process managed by BEAM.
  In Spinoza's terms, each agent is a "modus" — an individual
  expression of the infinite substance.

  ## State

  - `personality` — Big Five model (openness, conscientiousness, extraversion, agreeableness, neuroticism)
  - `needs` — Basic drives (hunger, social, rest, shelter) from 0-100
  - `conatus_score` — Striving to persist (-10 to +10)
  - `memory` — Last 20 events [{tick, event}]
  - `relationships` — Map of agent_id => {type, strength}
  """
  use GenServer

  defstruct [
    :id,
    :name,
    :position,
    :personality,
    :needs,
    :occupation,
    :relationships,
    :memory,
    :current_action,
    :conatus_score,
    :alive?,
    :age,
    conatus_energy: 0.7,
    affect_state: :neutral,
    affect_history: [],
    conatus_history: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          position: {integer(), integer()},
          personality: map(),
          needs: map(),
          occupation: atom(),
          relationships: map(),
          memory: list(),
          current_action: term(),
          conatus_score: float(),
          alive?: boolean(),
          age: integer(),
          conatus_energy: float(),
          affect_state: atom(),
          affect_history: list(),
          conatus_history: list()
        }

  @perception_radius 5
  @max_memory 20

  @doc "Create a new agent with randomized personality."
  @spec new(String.t(), {integer(), integer()}, atom()) :: t()
  def new(name, position, occupation \\ :explorer) do
    %__MODULE__{
      id: generate_id(),
      name: name,
      position: position,
      personality: random_personality(),
      needs: %{hunger: 50.0, social: 50.0, rest: 80.0, shelter: 70.0},
      occupation: occupation,
      relationships: %{},
      memory: [],
      current_action: :idle,
      conatus_score: 5.0,
      alive?: true,
      age: 0,
      conatus_energy: 0.7,
      affect_state: :neutral,
      affect_history: [],
      conatus_history: []
    }
  end

  # --- Public API ---

  @doc "Get the agent's current state by id."
  @spec get_state(String.t()) :: t()
  def get_state(agent_id) do
    GenServer.call(via(agent_id), :get_state)
  end

  @doc "Send a tick to an agent process by id."
  @spec tick(String.t(), non_neg_integer(), map()) :: :ok
  def tick(agent_id, tick_number, context \\ %{}) do
    GenServer.cast(via(agent_id), {:tick, tick_number, context})
  end

  @doc "Command an agent to move toward a target position."
  @spec move_toward(String.t(), {integer(), integer()}) :: :ok
  def move_toward(agent_id, target) do
    GenServer.cast(via(agent_id), {:move_toward, target})
  end

  @doc "Find agents within perception radius of a position."
  @spec nearby_agents({integer(), integer()}, integer()) :: [String.t()]
  def nearby_agents(position, radius \\ @perception_radius) do
    {px, py} = position

    # Use Registry values (stored as {position, alive?}) to avoid GenServer calls
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.filter(fn
      {_id, {ax, ay, true}} ->
        in_radius?({ax, ay}, {px, py}, radius)
      _ -> false
    end)
    |> Enum.map(fn {id, _} -> id end)
  end

  # --- GenServer ---

  def start_link(agent) do
    GenServer.start_link(__MODULE__, agent, name: via(agent.id))
  end

  @impl true
  def init(agent) do
    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    {:ok, agent}
  end

  @impl true
  def handle_call(:get_state, _from, agent) do
    {:reply, agent, agent}
  end

  @impl true
  def handle_info({:tick, tick_number}, agent) do
    # Self-tick via PubSub
    GenServer.cast(self(), {:tick, tick_number, %{}})
    {:noreply, agent}
  end

  def handle_info(_msg, agent), do: {:noreply, agent}

  def handle_cast({:tick, tick_number, _context}, %{alive?: false} = agent) do
    # Dead agents don't tick
    _ = tick_number
    {:noreply, agent}
  end

  def handle_cast({:tick, tick_number, context}, agent) do
    # Build decision context
    nearby = nearby_agents(agent.position)
    decision_context = Map.merge(context, %{
      tick: tick_number,
      nearby_agents: nearby,
      nearby_resources: Map.get(context, :nearby_resources, []),
      world_size: Map.get(context, :world_size, {50, 50})
    })

    # Decide action via DecisionEngine
    {action, params} = Modus.Simulation.DecisionEngine.decide(agent, decision_context)

    params = Map.put(params, :tick, tick_number)

    agent =
      agent
      |> decay_needs()
      |> apply_action(action, params)
      |> Modus.Mind.MindEngine.process_tick(action, params, tick_number)
      |> increment_age(tick_number)
      |> check_death(tick_number)
      |> record_memory(tick_number, {action, params})

    # Update registry with current position+alive for fast lookups
    {px, py} = agent.position
    Registry.update_value(Modus.AgentRegistry, agent.id, fn _ -> {px, py, agent.alive?} end)

    {:noreply, agent}
  end

  @impl true
  def handle_cast({:update_relationships, rels}, agent) do
    {:noreply, %{agent | relationships: rels}}
  end

  @impl true
  def handle_cast({:move_toward, _target}, %{alive?: false} = agent) do
    {:noreply, agent}
  end

  def handle_cast({:move_toward, {tx, ty}}, agent) do
    {ax, ay} = agent.position

    dx = clamp(tx - ax, -1, 1)
    dy = clamp(ty - ay, -1, 1)

    new_pos = {ax + dx, ay + dy}
    {:noreply, %{agent | position: new_pos, current_action: :moving}}
  end

  def handle_cast(:kill, agent) do
    {:noreply, %{agent | alive?: false}}
  end

  def handle_cast({:boost_need, need, amount}, agent) do
    current = Map.get(agent.needs, need, 0.0)
    new_needs = Map.put(agent.needs, need, min(current + amount, 100.0))
    {:noreply, %{agent | needs: new_needs}}
  end

  # --- Action Application ---

  defp apply_action(agent, :move_to, %{target: target}) do
    {ax, ay} = agent.position
    {tx, ty} = target
    dx = clamp(tx - ax, -1, 1)
    dy = clamp(ty - ay, -1, 1)
    %{agent | position: {ax + dx, ay + dy}, current_action: :moving}
  end

  defp apply_action(agent, :explore, %{target: target}) do
    {ax, ay} = agent.position
    {tx, ty} = target
    dx = clamp(tx - ax, -1, 1)
    dy = clamp(ty - ay, -1, 1)
    %{agent | position: {ax + dx, ay + dy}, current_action: :exploring}
  end

  defp apply_action(agent, :gather, params) do
    needs = %{agent.needs | hunger: max(agent.needs.hunger - 5.0, 0.0)}
    Modus.Simulation.EventLog.log(:resource_gathered, Map.get(params, :tick, 0), [agent.id], %{name: agent.name})
    %{agent | needs: needs, current_action: :gathering}
  end

  defp apply_action(agent, :sleep, _params) do
    needs = %{agent.needs | rest: min(agent.needs.rest + 10.0, 100.0)}
    %{agent | needs: needs, current_action: :sleeping}
  end

  defp apply_action(agent, :talk, params) do
    needs = %{agent.needs | social: min(agent.needs.social + 8.0, 100.0)}
    Modus.Simulation.EventLog.log(:conversation, Map.get(params, :tick, 0), [agent.id, Map.get(params, :target_agent, "unknown")], %{type: :social_chat, name: agent.name})
    %{agent | needs: needs, current_action: :talking}
  end

  defp apply_action(agent, :flee, %{target: target}) do
    {ax, ay} = agent.position
    {tx, ty} = target
    dx = clamp(tx - ax, -1, 1)
    dy = clamp(ty - ay, -1, 1)
    %{agent | position: {ax + dx, ay + dy}, current_action: :fleeing}
  end

  defp apply_action(agent, :idle, _params) do
    %{agent | current_action: :idle}
  end

  defp apply_action(agent, _action, _params) do
    %{agent | current_action: :idle}
  end

  # --- Need Decay ---

  defp decay_needs(agent) do
    needs = agent.needs

    # Auto-survival: agents with critical needs take care of themselves
    hunger_delta = if needs.hunger > 70.0, do: 0.01, else: 0.03
    hunger_recovery = if needs.hunger > 85.0, do: -2.0, else: 0.0
    rest_recovery = if needs.rest < 15.0, do: 3.0, else: 0.0

    new_needs = %{
      needs
      | hunger: max(needs.hunger + hunger_delta + hunger_recovery, 0.0),
        social: max(needs.social - 0.015, 0.0),
        rest: min(max(needs.rest - 0.02 + rest_recovery, 0.0), 100.0)
    }

    %{agent | needs: new_needs}
  end

  # --- Death Check ---

  defp check_death(agent, tick) do
    cond do
      agent.conatus_energy <= 0.0 ->
        Modus.Simulation.EventLog.log(:death, tick, [agent.id], %{cause: "loss_of_will", name: agent.name})
        %{agent | alive?: false, current_action: :dead}

      agent.needs.hunger > 100.0 ->
        Modus.Simulation.EventLog.log(:death, tick, [agent.id], %{cause: "starvation", name: agent.name})
        %{agent | alive?: false, current_action: :dead}

      agent.needs.rest < 0.0 ->
        Modus.Simulation.EventLog.log(:death, tick, [agent.id], %{cause: "exhaustion", name: agent.name})
        %{agent | alive?: false, current_action: :dead}

      true ->
        agent
    end
  end

  # --- Helpers ---

  defp increment_age(agent, tick) do
    # Age increases by 1 every 100 ticks (~10 seconds at 1x)
    if rem(tick, 100) == 0 do
      %{agent | age: agent.age + 1}
    else
      agent
    end
  end

  defp record_memory(agent, tick, event) do
    entry = {tick, event}
    memory = Enum.take([entry | agent.memory], @max_memory)
    %{agent | memory: memory}
  end

  defp in_radius?({x1, y1}, {x2, y2}, radius) do
    abs(x1 - x2) <= radius and abs(y1 - y2) <= radius
  end

  defp clamp(val, min_val, max_val) do
    val |> max(min_val) |> min(max_val)
  end

  defp via(id), do: {:via, Registry, {Modus.AgentRegistry, id, {0, 0, true}}}

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

  defp random_personality do
    %{
      openness: :rand.uniform(),
      conscientiousness: :rand.uniform(),
      extraversion: :rand.uniform(),
      agreeableness: :rand.uniform(),
      neuroticism: :rand.uniform()
    }
  end
end
