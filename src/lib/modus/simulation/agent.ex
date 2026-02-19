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
    conatus_history: [],
    last_reasoning: nil,
    explore_target: nil,
    explore_ticks: 0,
    conversing_with: nil,
    group_id: nil,
    inventory: %{},
    goals_initialized: false
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
          conatus_history: list(),
          last_reasoning: String.t() | nil,
          explore_target: {integer(), integer()} | nil,
          explore_ticks: non_neg_integer()
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
      conatus_history: [],
      inventory: %{}
    }
  end

  @doc "Create a new agent with custom personality and mood."
  @spec new_custom(String.t(), {integer(), integer()}, atom(), map(), atom()) :: t()
  def new_custom(name, position, occupation, personality, mood \\ :neutral) do
    affect =
      case mood do
        :happy -> :joy
        :calm -> :neutral
        :anxious -> :fear
        :eager -> :desire
        _ -> :neutral
      end

    %__MODULE__{
      id: generate_id(),
      name: name,
      position: position,
      personality: personality,
      needs: %{hunger: 50.0, social: 50.0, rest: 80.0, shelter: 70.0},
      occupation: occupation,
      relationships: %{},
      memory: [],
      current_action: :idle,
      conatus_score: 5.0,
      alive?: true,
      age: 0,
      conatus_energy: 0.7,
      affect_state: affect,
      affect_history: [],
      conatus_history: [],
      inventory: %{}
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

  @doc "Find agents within perception radius of a position. Uses spatial index for O(1) lookups."
  @spec nearby_agents({integer(), integer()}, integer()) :: [String.t()]
  def nearby_agents(position, radius \\ @perception_radius) do
    try do
      Modus.Performance.SpatialIndex.nearby(position, radius)
    catch
      _, _ ->
        # Fallback to registry scan
        {px, py} = position

        Modus.AgentRegistry
        |> Registry.select([{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
        |> Enum.filter(fn
          {_id, {ax, ay, true}} -> in_radius?({ax, ay}, {px, py}, radius)
          _ -> false
        end)
        |> Enum.map(fn {id, _} -> id end)
    end
  end

  # --- GenServer ---

  def start_link(agent) do
    GenServer.start_link(__MODULE__, agent, name: via(agent.id))
  end

  @impl true
  def init(agent) do
    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    # Initialize learning skills and aging
    Modus.Mind.Learning.init_skills(agent.id)
    Modus.Simulation.Aging.init()
    Modus.Simulation.Aging.init_agent(agent.id)
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
    _ = tick_number
    {:noreply, agent}
  end

  def handle_cast({:tick, tick_number, context}, agent) do
    # Lazy evaluation: distant agents get simplified processing (skip if critical needs)
    critical = agent.needs.hunger > 90.0 or agent.needs.rest < 5.0 or agent.conatus_energy < 0.1

    if not critical and
         Modus.Performance.LazyEval.distant?(agent.position, tick_number) and
         Modus.Performance.LazyEval.lazy?(agent.id, agent.position, tick_number) do
      agent = Modus.Performance.LazyEval.simplified_tick(agent)
      {:noreply, agent}
    else
      do_full_tick(agent, tick_number, context)
    end
  end

  @impl true
  def handle_cast({:update_relationships, rels}, agent) do
    {:noreply, %{agent | relationships: rels}}
  end

  @impl true
  def handle_cast({:divine_intervention, :heal}, agent) do
    {:noreply, %{agent | conatus_energy: 1.0, current_affect: :joy}}
  end

  def handle_cast({:divine_intervention, :boost_mood}, agent) do
    {:noreply, %{agent | current_affect: :joy}}
  end

  def handle_cast({:divine_intervention, :drain_mood}, agent) do
    {:noreply, %{agent | current_affect: :sadness}}
  end

  def handle_cast({:divine_intervention, :max_conatus}, agent) do
    {:noreply, %{agent | conatus_energy: 1.0}}
  end

  def handle_cast({:update_name, name}, agent) do
    {:noreply, %{agent | name: name}}
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
    terrain = get_terrain_at(new_pos)

    if terrain in [:water, :ocean] do
      # Block movement into water
      {:noreply, %{agent | current_action: :idle}}
    else
      {:noreply, %{agent | position: new_pos, current_action: :moving}}
    end
  end

  def handle_cast(:kill, agent) do
    {:noreply, %{agent | alive?: false}}
  end

  def handle_cast({:boost_need, need, amount}, agent) do
    current = Map.get(agent.needs, need, 0.0)
    new_needs = Map.put(agent.needs, need, min(current + amount, 100.0))
    {:noreply, %{agent | needs: new_needs}}
  end

  defp do_full_tick(agent, tick_number, context) do
    # Build decision context
    nearby = nearby_agents(agent.position)

    decision_context =
      Map.merge(context, %{
        tick: tick_number,
        nearby_agents: nearby,
        nearby_resources: Map.get(context, :nearby_resources, []),
        world_size: Map.get(context, :world_size, {50, 50})
      })

    # Decide action via DecisionEngine
    {action, params} = Modus.Simulation.DecisionEngine.decide(agent, decision_context)

    # Group following: non-leader members follow their leader
    {action, params} =
      case Modus.Mind.Cerebro.Group.get_group_target(agent.id) do
        nil ->
          {action, params}

        leader_pos ->
          # Override action to follow leader
          {:move_to, Map.put(params, :target, leader_pos)}
      end

    # Persist explore target for smoother movement (10-20 ticks per direction)
    {action, params, agent} =
      case action do
        :explore ->
          if agent.explore_ticks > 0 and agent.explore_target != nil do
            # Keep current explore target
            {action, Map.put(params, :target, agent.explore_target),
             %{agent | explore_ticks: agent.explore_ticks - 1}}
          else
            # Pick new target and persist it
            target = Map.get(params, :target) || random_explore_target(agent, context)
            # Bias explore target via spatial memory
            target =
              Modus.Mind.Cerebro.SpatialMemory.bias_explore_target(
                agent.id,
                agent.position,
                target
              )

            ticks = Enum.random(10..20)
            {action, params, %{agent | explore_target: target, explore_ticks: ticks}}
          end

        _ ->
          # Non-explore action clears explore state
          {action, params, %{agent | explore_target: nil, explore_ticks: 0}}
      end

    params = Map.put(params, :tick, tick_number)

    # Terrain effects
    agent = apply_terrain_effects(agent, action)

    # Daily routine: sleep cycles, energy, and schedule overrides
    {action, params} =
      case Modus.Simulation.DailyRoutine.recommend_action(agent) do
        {:override, new_action, new_params} -> {new_action, Map.merge(params, new_params)}
        :no_override -> maybe_force_sleep(agent, action, params)
      end

    agent =
      agent
      |> decay_needs()
      |> apply_building_bonuses()
      |> apply_neighborhood_bonus()
      |> apply_action(action, params)
      |> Modus.Simulation.DailyRoutine.process_tick(action, tick_number)
      |> tap(fn a ->
        # Age-based learning rate modifier
        age_mods = Modus.Simulation.Aging.modifiers(Modus.Simulation.Aging.stage(a.age))
        lr = Map.get(age_mods, :learning_rate, 1.0)

        if lr != 1.0 do
          # Temporarily boost XP via multiple awards for fast learners
          times = max(1, round(lr))
          Enum.each(1..times, fn _ -> Modus.Mind.Learning.award_for_action(a.id, action) end)
        else
          Modus.Mind.Learning.award_for_action(a.id, action)
        end
      end)
      |> Modus.Mind.MindEngine.process_tick(action, params, tick_number)
      |> tap(fn a ->
        Modus.Mind.Cerebro.AgentConversation.maybe_converse(a, nearby, tick_number)
      end)
      |> tap(fn a -> Modus.Simulation.Aging.maybe_teach(a.id, tick_number, nearby) end)
      |> increment_age(tick_number)
      |> Modus.Simulation.Aging.process_tick(tick_number)
      |> check_age_death(tick_number)
      |> check_death(tick_number)
      |> maybe_pray(tick_number)
      |> record_memory(tick_number, {action, params})

    # Update registry with current position+alive for fast lookups
    old_pos = Map.get(context, :old_position, agent.position)
    {px, py} = agent.position
    Registry.update_value(Modus.AgentRegistry, agent.id, fn _ -> {px, py, agent.alive?} end)

    # Update spatial index
    try do
      Modus.Performance.SpatialIndex.update(agent.id, old_pos, agent.position)
    catch
      _, _ -> :ok
    end

    # Trim state to enforce 10KB limit
    agent = Modus.Performance.StateLimiter.trim(agent)

    {:noreply, agent}
  end

  # --- Action Application ---

  defp apply_action(agent, :move_to, %{target: target}) do
    move_with_terrain_check(agent, target, :moving)
  end

  defp apply_action(agent, :explore, %{target: target}) do
    move_with_terrain_check(agent, target, :exploring)
  end

  defp apply_action(agent, :gather, params) do
    # Determine what to gather based on terrain
    terrain = get_terrain_at(agent.position)
    resource_types = Modus.Simulation.Resource.terrain_resources(terrain)
    resource_type = if resource_types == [], do: :food, else: List.first(resource_types)

    # Map resource_type to ResourceSystem types
    gather_type =
      case resource_type do
        :fish -> :fish
        # water tiles have fish
        :fresh_water -> :fish
        :crops -> :food
        :wild_berries -> :food
        # fallback
        :herbs -> :food
        other -> other
      end

    gathered =
      try do
        case Modus.Simulation.ResourceSystem.gather(agent.position, gather_type, 2.0) do
          {:ok, amount} -> amount
          _ -> 0.0
        end
      catch
        :exit, _ -> 0.0
      end

    # Add to inventory
    inventory = Map.update(agent.inventory, resource_type, gathered, &(&1 + gathered))

    # Food-like resources reduce hunger
    hunger_relief =
      case resource_type do
        t when t in [:food, :fish, :crops, :wild_berries] -> if gathered > 0, do: 5.0, else: 1.0
        _ -> 1.0
      end

    needs = %{agent.needs | hunger: max(agent.needs.hunger - hunger_relief, 0.0)}

    Modus.Simulation.EventLog.log(:resource_gathered, Map.get(params, :tick, 0), [agent.id], %{
      name: agent.name,
      amount: gathered,
      resource: resource_type
    })

    %{agent | needs: needs, current_action: :gathering, inventory: inventory}
  end

  defp apply_action(agent, :sleep, _params) do
    needs = %{agent.needs | rest: min(agent.needs.rest + 10.0, 100.0)}
    %{agent | needs: needs, current_action: :sleeping}
  end

  defp apply_action(agent, :talk, params) do
    needs = %{agent.needs | social: min(agent.needs.social + 8.0, 100.0)}

    Modus.Simulation.EventLog.log(
      :conversation,
      Map.get(params, :tick, 0),
      [agent.id, Map.get(params, :target_agent, "unknown")],
      %{type: :social_chat, name: agent.name}
    )

    %{agent | needs: needs, current_action: :talking}
  end

  defp apply_action(agent, :flee, %{target: target}) do
    {ax, ay} = agent.position
    {tx, ty} = target
    dx = clamp(tx - ax, -1, 1)
    dy = clamp(ty - ay, -1, 1)
    %{agent | position: {ax + dx, ay + dy}, current_action: :fleeing}
  end

  defp apply_action(agent, :build, params) do
    alias Modus.Simulation.Building

    # Determine best building type agent can afford (prefer hut for homeless)
    build_type =
      cond do
        !Building.has_home?(agent.id) and Building.can_build?(agent.inventory, :house) -> :house
        !Building.has_home?(agent.id) and Building.can_build?(agent.inventory, :hut) -> :hut
        Building.can_build?(agent.inventory, :farm) -> :farm
        Building.can_build?(agent.inventory, :well) -> :well
        Building.can_build?(agent.inventory, :market) -> :market
        Building.can_build?(agent.inventory, :watchtower) -> :watchtower
        true -> nil
      end

    if build_type do
      # Try to build near a friend's home (social proximity)
      build_pos =
        case Building.friend_build_position(agent.id) do
          nil -> agent.position
          pos -> pos
        end

      inventory = Building.deduct_costs(agent.inventory, build_type)
      building = Building.place(build_type, build_pos, agent.id, Map.get(params, :tick, 0))

      Modus.Simulation.EventLog.log(:building, Map.get(params, :tick, 0), [agent.id], %{
        name: agent.name,
        type: build_type,
        position: build_pos,
        building_id: building.id
      })

      needs = %{agent.needs | shelter: min(agent.needs.shelter + 20.0, 100.0)}
      %{agent | inventory: inventory, needs: needs, current_action: :building}
    else
      %{agent | current_action: :idle}
    end
  end

  defp apply_action(agent, :upgrade_home, params) do
    alias Modus.Simulation.Building

    home = Building.get_home(agent.id)
    tick = Map.get(params, :tick, 0)

    if home != nil and Building.can_upgrade?(home, agent.conatus_energy, tick) and
         Building.can_afford_upgrade?(agent.inventory, home) do
      inventory = Building.deduct_upgrade_costs(agent.inventory, home)

      case Building.upgrade(home.id, tick) do
        {:ok, upgraded} ->
          Modus.Simulation.EventLog.log(:building_upgrade, tick, [agent.id], %{
            name: agent.name,
            from: home.type,
            to: upgraded.type,
            level: upgraded.level,
            position: home.position
          })

          %{agent | inventory: inventory, current_action: :building}

        :error ->
          %{agent | current_action: :idle}
      end
    else
      %{agent | current_action: :idle}
    end
  end

  defp apply_action(agent, :idle, _params) do
    %{agent | current_action: :idle}
  end

  defp apply_action(agent, _action, _params) do
    %{agent | current_action: :idle}
  end

  # Shared movement with terrain walkability check
  defp move_with_terrain_check(agent, target, action_label) do
    {ax, ay} = agent.position
    {tx, ty} = target
    dx = clamp(tx - ax, -1, 1)
    dy = clamp(ty - ay, -1, 1)
    new_pos = {ax + dx, ay + dy}

    terrain = get_terrain_at(new_pos)

    if terrain in [:water, :ocean] do
      %{agent | current_action: :idle, explore_target: nil, explore_ticks: 0}
    else
      %{agent | position: new_pos, current_action: action_label}
    end
  end

  # --- Terrain & Environment Effects ---

  defp apply_terrain_effects(agent, action) when action in [:move_to, :explore] do
    # Check biome at current position for movement cost
    {x, y} = agent.position
    biome = Modus.Simulation.TerrainGenerator.biome_at(x, y) || :plains
    cost = Modus.Simulation.TerrainGenerator.movement_cost(biome)

    case cost do
      :impassable ->
        # Shouldn't be here, but drain energy if somehow on ocean
        %{agent | conatus_energy: max(agent.conatus_energy - 0.02, 0.0)}

      c when is_number(c) ->
        # Energy drain scales with movement cost (1.0 = baseline 0.003)
        drain = 0.003 * c
        %{agent | conatus_energy: max(agent.conatus_energy - drain, 0.0)}
    end
  end

  defp apply_terrain_effects(agent, _action), do: agent

  defp get_terrain_at({x, y}) do
    try do
      case Modus.Simulation.World.get_cell({x, y}) do
        {:ok, cell} -> cell.terrain
        _ -> :grass
      end
    catch
      :exit, _ -> :grass
    end
  end

  defp maybe_force_sleep(agent, action, params) do
    is_night =
      try do
        Modus.Simulation.Environment.is_night?()
      catch
        :exit, _ -> false
      end

    if is_night and agent.needs.rest < 30.0 and action not in [:sleep, :flee] do
      {:sleep, params}
    else
      {action, params}
    end
  end

  # --- Need Decay ---

  defp decay_needs(agent) do
    needs = agent.needs

    # Auto-survival: agents with critical needs take care of themselves
    # Hunger recovery kicks in earlier (>70) to prevent conatus death spiral
    hunger_delta = if needs.hunger > 60.0, do: 0.005, else: 0.02

    hunger_recovery =
      cond do
        # urgent recovery
        needs.hunger > 80.0 -> -3.0
        # moderate recovery
        needs.hunger > 70.0 -> -1.5
        true -> 0.0
      end

    rest_recovery = if needs.rest < 15.0, do: 3.0, else: 0.0

    new_needs = %{
      needs
      | hunger: max(needs.hunger + hunger_delta + hunger_recovery, 0.0),
        social: max(needs.social - 0.01, 0.0),
        rest: min(max(needs.rest - 0.015 + rest_recovery, 0.0), 100.0)
    }

    %{agent | needs: new_needs}
  end

  defp apply_building_bonuses(agent) do
    new_needs = Modus.Simulation.Building.apply_area_bonuses(agent.needs, agent.position)
    %{agent | needs: new_needs}
  end

  defp apply_neighborhood_bonus(agent) do
    bonus = Modus.Simulation.Building.neighborhood_social_bonus(agent.id)

    if bonus > 0.0 do
      new_social = min(100.0, agent.needs.social + bonus)
      %{agent | needs: %{agent.needs | social: new_social}}
    else
      agent
    end
  end

  # --- Death Check ---

  defp check_age_death(%{alive?: false} = agent, _tick), do: agent

  defp check_age_death(agent, tick) do
    if Modus.Simulation.Aging.should_die_of_age?(agent.id, agent.age) do
      Modus.Simulation.EventLog.log(:death, tick, [agent.id], %{
        cause: "old_age",
        name: agent.name,
        age: agent.age
      })

      Modus.Persistence.AgentMemory.maybe_record_from_event(agent.id, agent.name, :death, tick, %{
        cause: "old_age"
      })

      Modus.Simulation.Lifecycle.record_death()
      Modus.Simulation.Aging.on_death(agent.id, agent.age, tick)
      %{agent | alive?: false, current_action: :dead}
    else
      agent
    end
  end

  defp check_death(agent, tick) do
    cond do
      agent.conatus_energy <= 0.0 ->
        Modus.Simulation.EventLog.log(:death, tick, [agent.id], %{
          cause: "loss_of_will",
          name: agent.name
        })

        Modus.Persistence.AgentMemory.maybe_record_from_event(
          agent.id,
          agent.name,
          :death,
          tick,
          %{cause: "loss_of_will"}
        )

        Modus.Simulation.Lifecycle.record_death()
        %{agent | alive?: false, current_action: :dead}

      agent.needs.hunger > 100.0 ->
        Modus.Simulation.EventLog.log(:death, tick, [agent.id], %{
          cause: "starvation",
          name: agent.name
        })

        Modus.Persistence.AgentMemory.maybe_record_from_event(
          agent.id,
          agent.name,
          :death,
          tick,
          %{cause: "starvation"}
        )

        Modus.Simulation.Lifecycle.record_death()
        %{agent | alive?: false, current_action: :dead}

      agent.needs.rest < 0.0 ->
        Modus.Simulation.EventLog.log(:death, tick, [agent.id], %{
          cause: "exhaustion",
          name: agent.name
        })

        Modus.Persistence.AgentMemory.maybe_record_from_event(
          agent.id,
          agent.name,
          :death,
          tick,
          %{cause: "exhaustion"}
        )

        Modus.Simulation.Lifecycle.record_death()
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

  defp maybe_pray(%{alive?: false} = agent, _tick), do: agent
  defp maybe_pray(agent, tick) do
    case Modus.World.PrayerSystem.maybe_pray(agent, tick) do
      {:pray, type} ->
        try do
          Modus.World.PrayerSystem.pray(agent.id, agent.name, type, tick)
        catch
          _, _ -> :ok
        end
        agent
      :no_prayer ->
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

  defp random_explore_target(agent, context) do
    {ax, ay} = agent.position
    {max_x, max_y} = Map.get(context, :world_size, {50, 50})
    dx = Enum.random(-5..5)
    dy = Enum.random(-5..5)
    {max(0, min(ax + dx, max_x - 1)), max(0, min(ay + dy, max_y - 1))}
  end

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
