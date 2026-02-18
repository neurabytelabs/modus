defmodule Modus.Mind.Planner do
  @moduledoc """
  Consilium — Multi-step goal planning for agents.

  Decomposes high-level goals into ordered steps, maintains a priority queue
  where urgent needs (hunger, danger) override long-term plans, tracks
  execution progress, and revises plans when steps are blocked.

  All state is stored in ETS for fast concurrent reads.

  ## Plan Structure

      %Plan{
        id: "abc123",
        agent_id: "agent_01",
        goal: :build_house,
        steps: [
          %Step{action: :gather_wood, status: :completed},
          %Step{action: :gather_stone, status: :in_progress},
          %Step{action: :build, status: :pending}
        ],
        priority: 5,
        status: :active,
        revision: 0
      }
  """

  @table :agent_plans

  # --- Structs ---

  defmodule Step do
    @moduledoc "A single step in a plan."
    defstruct [
      :action,
      :params,
      # :pending | :in_progress | :completed | :failed | :blocked
      :status,
      # tick
      :started_at,
      # tick
      :completed_at,
      attempts: 0,
      max_attempts: 10
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Plan do
    @moduledoc "A multi-step plan toward a goal."
    defstruct [
      :id,
      :agent_id,
      :goal,
      :steps,
      # higher = more urgent (0-100)
      :priority,
      # :active | :completed | :failed | :blocked | :revised
      :status,
      :created_at,
      :completed_at,
      revision: 0,
      metadata: %{}
    ]

    @type t :: %__MODULE__{}
  end

  # Priority thresholds
  @urgent_priority 80
  @high_priority 60
  @normal_priority 40
  @low_priority 20

  # --- Init ---

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :bag, :public, read_concurrency: true])
    end

    :ok
  end

  # --- Public API ---

  @doc "Create a plan for a goal, decomposing it into steps."
  @spec create_plan(String.t(), atom(), keyword()) :: Plan.t()
  def create_plan(agent_id, goal, opts \\ []) do
    init()
    priority = Keyword.get(opts, :priority, default_priority(goal))
    tick = Keyword.get(opts, :tick, 0)
    metadata = Keyword.get(opts, :metadata, %{})

    steps = decompose(goal, metadata)

    plan = %Plan{
      id: generate_id(),
      agent_id: agent_id,
      goal: goal,
      steps: steps,
      priority: priority,
      status: :active,
      created_at: tick,
      completed_at: nil,
      metadata: metadata
    }

    :ets.insert(@table, {agent_id, plan})
    plan
  end

  @doc "Get all plans for an agent."
  @spec get_plans(String.t()) :: [Plan.t()]
  def get_plans(agent_id) do
    init()

    :ets.lookup(@table, agent_id)
    |> Enum.map(fn {_id, plan} -> plan end)
  end

  @doc "Get active plans sorted by priority (highest first)."
  @spec active_plans(String.t()) :: [Plan.t()]
  def active_plans(agent_id) do
    get_plans(agent_id)
    |> Enum.filter(&(&1.status == :active))
    |> Enum.sort_by(& &1.priority, :desc)
  end

  @doc """
  Get the next action for an agent from their highest-priority plan.
  Returns `{:ok, action, params, plan_id}` or `:no_plan`.
  """
  @spec next_action(String.t(), map(), non_neg_integer()) ::
          {:ok, atom(), map(), String.t()} | :no_plan
  def next_action(agent_id, agent_state, tick) do
    # Check for urgent needs that override all plans
    case check_urgent_needs(agent_state) do
      {:urgent, action, params} ->
        {:ok, action, params, :urgent}

      :none ->
        case active_plans(agent_id) do
          [] ->
            :no_plan

          [top_plan | _] ->
            case current_step(top_plan) do
              nil ->
                # All steps done — complete plan
                complete_plan(agent_id, top_plan.id, tick)
                :no_plan

              step ->
                action = step.action
                params = step.params || %{}
                # Mark step in_progress
                update_step_status(agent_id, top_plan.id, action, :in_progress, tick)
                {:ok, action, params, top_plan.id}
            end
        end
    end
  end

  @doc "Mark the current step of a plan as completed."
  @spec complete_step(String.t(), String.t(), atom(), non_neg_integer()) :: :ok
  def complete_step(agent_id, plan_id, action, tick) do
    update_step_status(agent_id, plan_id, action, :completed, tick)

    # Check if all steps are done
    case get_plan(agent_id, plan_id) do
      nil ->
        :ok

      plan ->
        if Enum.all?(plan.steps, &(&1.status == :completed)) do
          complete_plan(agent_id, plan_id, tick)
        end

        :ok
    end
  end

  @doc "Mark a step as blocked and attempt plan revision."
  @spec block_step(String.t(), String.t(), atom(), non_neg_integer()) ::
          {:revised, Plan.t()} | {:failed, Plan.t()} | :not_found
  def block_step(agent_id, plan_id, action, tick) do
    update_step_status(agent_id, plan_id, action, :blocked, tick)

    case get_plan(agent_id, plan_id) do
      nil ->
        :not_found

      plan ->
        if plan.revision < 3 do
          revised = revise_plan(plan, action, tick)
          persist_plan(agent_id, plan_id, revised)
          {:revised, revised}
        else
          failed = %{plan | status: :failed}
          persist_plan(agent_id, plan_id, failed)
          {:failed, failed}
        end
    end
  end

  @doc "Evaluate agent state and auto-generate plans for unmet needs/goals."
  @spec evaluate_and_plan(String.t(), map(), non_neg_integer()) :: [Plan.t()]
  def evaluate_and_plan(agent_id, agent_state, tick) do
    existing_goals =
      active_plans(agent_id)
      |> Enum.map(& &1.goal)
      |> MapSet.new()

    new_plans = []

    # Hunger plan
    new_plans =
      if needs_val(agent_state, :hunger) > 70 and :satisfy_hunger not in existing_goals do
        [create_plan(agent_id, :satisfy_hunger, tick: tick) | new_plans]
      else
        new_plans
      end

    # Shelter plan
    new_plans =
      if needs_val(agent_state, :shelter) < 30 and :build_house not in existing_goals do
        [create_plan(agent_id, :build_house, tick: tick) | new_plans]
      else
        new_plans
      end

    # Rest plan
    new_plans =
      if needs_val(agent_state, :rest) < 20 and :find_rest not in existing_goals do
        [create_plan(agent_id, :find_rest, tick: tick, priority: 90) | new_plans]
      else
        new_plans
      end

    # Social plan
    new_plans =
      if needs_val(agent_state, :social) < 25 and :socialize not in existing_goals do
        [create_plan(agent_id, :socialize, tick: tick) | new_plans]
      else
        new_plans
      end

    new_plans
  end

  @doc "Remove a plan by id."
  @spec remove_plan(String.t(), String.t()) :: :ok
  def remove_plan(agent_id, plan_id) do
    plans = get_plans(agent_id) |> Enum.reject(&(&1.id == plan_id))
    :ets.delete(@table, agent_id)
    Enum.each(plans, fn p -> :ets.insert(@table, {agent_id, p}) end)
    :ok
  end

  @doc "Clear all plans (for world reset)."
  @spec clear_all() :: :ok
  def clear_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc "Get plan progress as percentage (0.0 - 1.0)."
  @spec plan_progress(Plan.t()) :: float()
  def plan_progress(%Plan{steps: []}), do: 1.0

  def plan_progress(%Plan{steps: steps}) do
    completed = Enum.count(steps, &(&1.status == :completed))
    completed / length(steps)
  end

  @doc "Serialize plans for JSON transport."
  @spec serialize(String.t()) :: [map()]
  def serialize(agent_id) do
    get_plans(agent_id)
    |> Enum.map(fn plan ->
      %{
        id: plan.id,
        goal: to_string(plan.goal),
        priority: plan.priority,
        status: to_string(plan.status),
        progress: Float.round(plan_progress(plan), 2),
        revision: plan.revision,
        steps:
          Enum.map(plan.steps, fn s ->
            %{
              action: to_string(s.action),
              status: to_string(s.status),
              attempts: s.attempts
            }
          end)
      }
    end)
  end

  # --- Goal Decomposition ---

  @doc "Decompose a high-level goal into ordered steps."
  @spec decompose(atom(), map()) :: [Step.t()]
  def decompose(:build_house, _meta) do
    [
      %Step{action: :gather_wood, params: %{amount: 5}, status: :pending},
      %Step{action: :gather_stone, params: %{amount: 3}, status: :pending},
      %Step{action: :find_location, params: %{}, status: :pending},
      %Step{action: :build, params: %{type: :house}, status: :pending}
    ]
  end

  def decompose(:build_hut, _meta) do
    [
      %Step{action: :gather_wood, params: %{amount: 3}, status: :pending},
      %Step{action: :find_location, params: %{}, status: :pending},
      %Step{action: :build, params: %{type: :hut}, status: :pending}
    ]
  end

  def decompose(:satisfy_hunger, _meta) do
    [
      %Step{action: :find_food_source, params: %{}, status: :pending},
      %Step{action: :gather, params: %{resource_type: :food}, status: :pending},
      %Step{action: :eat, params: %{}, status: :pending}
    ]
  end

  def decompose(:find_rest, _meta) do
    [
      %Step{action: :find_shelter, params: %{}, status: :pending},
      %Step{action: :sleep, params: %{}, status: :pending}
    ]
  end

  def decompose(:socialize, _meta) do
    [
      %Step{action: :find_nearby_agent, params: %{}, status: :pending},
      %Step{action: :move_to_agent, params: %{}, status: :pending},
      %Step{action: :talk, params: %{}, status: :pending}
    ]
  end

  def decompose(:gather_resources, meta) do
    resource = Map.get(meta, :resource_type, :wood)
    amount = Map.get(meta, :amount, 10)

    [
      %Step{action: :find_resource, params: %{type: resource}, status: :pending},
      %Step{action: :move_to_resource, params: %{}, status: :pending},
      %Step{action: :gather, params: %{resource_type: resource, amount: amount}, status: :pending}
    ]
  end

  def decompose(:explore_area, _meta) do
    [
      %Step{action: :pick_direction, params: %{}, status: :pending},
      %Step{action: :explore, params: %{}, status: :pending},
      %Step{action: :observe, params: %{}, status: :pending}
    ]
  end

  def decompose(:flee_danger, meta) do
    threat = Map.get(meta, :threat_position, {0, 0})

    [
      %Step{action: :assess_threat, params: %{position: threat}, status: :pending},
      %Step{action: :flee, params: %{from: threat}, status: :pending},
      %Step{action: :find_shelter, params: %{}, status: :pending}
    ]
  end

  def decompose(goal, _meta) do
    # Generic single-step plan for unknown goals
    [%Step{action: goal, params: %{}, status: :pending}]
  end

  # --- Urgent Needs Check ---

  @doc "Check if agent has urgent needs that override all plans."
  @spec check_urgent_needs(map()) :: {:urgent, atom(), map()} | :none
  def check_urgent_needs(agent_state) do
    needs = get_needs(agent_state)

    cond do
      # Critical danger — flee immediately
      Map.get(agent_state, :under_threat, false) ->
        threat_pos = Map.get(agent_state, :threat_position, {0, 0})
        {:urgent, :flee, %{from: threat_pos}}

      # Critical hunger
      needs_val(needs, :hunger) > 90 ->
        {:urgent, :gather, %{resource_type: :food}}

      # Critical exhaustion
      needs_val(needs, :rest) < 10 ->
        {:urgent, :sleep, %{}}

      true ->
        :none
    end
  end

  # --- Plan Revision ---

  defp revise_plan(plan, blocked_action, tick) do
    # Find alternative steps for the blocked action
    alt_steps = alternative_steps(blocked_action, plan.goal)

    new_steps =
      Enum.flat_map(plan.steps, fn step ->
        if step.action == blocked_action and step.status == :blocked do
          alt_steps
        else
          [step]
        end
      end)

    %{
      plan
      | steps: new_steps,
        revision: plan.revision + 1,
        status: :active,
        metadata: Map.put(plan.metadata, :last_revision_at, tick)
    }
  end

  defp alternative_steps(:gather_wood, _goal) do
    [
      %Step{action: :find_resource, params: %{type: :wood}, status: :pending},
      %Step{action: :explore, params: %{}, status: :pending},
      %Step{action: :gather_wood, params: %{}, status: :pending}
    ]
  end

  defp alternative_steps(:gather_stone, _goal) do
    [
      %Step{action: :find_resource, params: %{type: :stone}, status: :pending},
      %Step{action: :explore, params: %{}, status: :pending},
      %Step{action: :gather_stone, params: %{}, status: :pending}
    ]
  end

  defp alternative_steps(:find_food_source, _goal) do
    [
      %Step{action: :explore, params: %{}, status: :pending},
      %Step{action: :gather, params: %{resource_type: :food}, status: :pending}
    ]
  end

  defp alternative_steps(:find_nearby_agent, _goal) do
    [
      %Step{action: :explore, params: %{}, status: :pending},
      %Step{action: :find_nearby_agent, params: %{}, status: :pending}
    ]
  end

  defp alternative_steps(action, _goal) do
    # Default: retry with an explore step first
    [
      %Step{action: :explore, params: %{}, status: :pending},
      %Step{action: action, params: %{}, status: :pending}
    ]
  end

  # --- Private Helpers ---

  defp get_plan(agent_id, plan_id) do
    get_plans(agent_id)
    |> Enum.find(&(&1.id == plan_id))
  end

  defp current_step(%Plan{steps: steps}) do
    Enum.find(steps, fn s -> s.status in [:pending, :in_progress] end)
  end

  defp update_step_status(agent_id, plan_id, action, new_status, tick) do
    case get_plan(agent_id, plan_id) do
      nil ->
        :ok

      plan ->
        updated_steps =
          Enum.map(plan.steps, fn step ->
            if step.action == action and step.status in [:pending, :in_progress] do
              step
              |> Map.put(:status, new_status)
              |> Map.put(:attempts, step.attempts + 1)
              |> maybe_set_timestamp(new_status, tick)
            else
              step
            end
          end)

        updated = %{plan | steps: updated_steps}
        persist_plan(agent_id, plan_id, updated)
    end
  end

  defp maybe_set_timestamp(step, :in_progress, tick) do
    if step.started_at == nil, do: %{step | started_at: tick}, else: step
  end

  defp maybe_set_timestamp(step, :completed, tick), do: %{step | completed_at: tick}
  defp maybe_set_timestamp(step, _, _tick), do: step

  defp complete_plan(agent_id, plan_id, tick) do
    case get_plan(agent_id, plan_id) do
      nil ->
        :ok

      plan ->
        updated = %{plan | status: :completed, completed_at: tick}
        persist_plan(agent_id, plan_id, updated)
    end
  end

  defp persist_plan(agent_id, plan_id, updated_plan) do
    plans = get_plans(agent_id)
    others = Enum.reject(plans, &(&1.id == plan_id))
    :ets.delete(@table, agent_id)
    Enum.each([updated_plan | others], fn p -> :ets.insert(@table, {agent_id, p}) end)
  end

  defp default_priority(:satisfy_hunger), do: @urgent_priority
  defp default_priority(:find_rest), do: @urgent_priority
  defp default_priority(:flee_danger), do: 100
  defp default_priority(:build_house), do: @normal_priority
  defp default_priority(:build_hut), do: @normal_priority
  defp default_priority(:socialize), do: @low_priority
  defp default_priority(:gather_resources), do: @high_priority
  defp default_priority(:explore_area), do: @low_priority
  defp default_priority(_), do: @normal_priority

  defp get_needs(%{needs: needs}) when is_map(needs), do: needs
  defp get_needs(_), do: %{}

  defp needs_val(%{needs: needs}, key) when is_map(needs) do
    val = Map.get(needs, key, 50.0)
    ensure_float(val)
  end

  defp needs_val(state, key) when is_map(state) do
    val = Map.get(state, key, 50.0)
    ensure_float(val)
  end

  defp needs_val(_, _), do: 50.0

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  defp generate_id, do: :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
end
