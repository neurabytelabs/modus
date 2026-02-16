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
    :age
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
          age: integer()
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
      age: 0
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

    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.filter(fn agent_id ->
      try do
        state = GenServer.call(via(agent_id), :get_state)
        state.alive? && in_radius?(state.position, {px, py}, radius)
      catch
        :exit, _ -> false
      end
    end)
  end

  # --- GenServer ---

  def start_link(agent) do
    GenServer.start_link(__MODULE__, agent, name: via(agent.id))
  end

  @impl true
  def init(agent) do
    {:ok, agent}
  end

  @impl true
  def handle_call(:get_state, _from, agent) do
    {:reply, agent, agent}
  end

  @impl true
  def handle_cast({:tick, tick_number, _context}, %{alive?: false} = agent) do
    # Dead agents don't tick
    _ = tick_number
    {:noreply, agent}
  end

  def handle_cast({:tick, tick_number, _context}, agent) do
    agent =
      agent
      |> decay_needs()
      |> increment_age()
      |> check_death()
      |> record_memory(tick_number, :tick)

    {:noreply, agent}
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

  # --- Need Decay ---

  defp decay_needs(agent) do
    needs = agent.needs

    new_needs = %{
      needs
      | hunger: needs.hunger + 0.1,
        social: needs.social - 0.05,
        rest: needs.rest - 0.08
    }

    %{agent | needs: new_needs}
  end

  # --- Death Check ---

  defp check_death(agent) do
    cond do
      agent.needs.hunger > 100.0 -> %{agent | alive?: false, current_action: :dead}
      agent.needs.rest < 0.0 -> %{agent | alive?: false, current_action: :dead}
      true -> agent
    end
  end

  # --- Helpers ---

  defp increment_age(agent), do: %{agent | age: agent.age + 1}

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

  defp via(id), do: {:via, Registry, {Modus.AgentRegistry, id}}

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
