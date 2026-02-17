defmodule Modus.Performance.SpatialIndex do
  @moduledoc """
  SpatialIndex — Grid-based spatial indexing for O(1) neighbor lookups.

  Replaces O(n²) full-scan nearby_agents with O(1) cell-based lookups.
  Divides the world into cells of `@cell_size` and maintains an ETS table
  mapping cell coords to agent ids.
  """

  @table :modus_spatial_index
  @cell_size 5

  @doc "Initialize the spatial index ETS table."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  @doc "Clear and rebuild the index from the agent registry."
  @spec rebuild() :: :ok
  def rebuild do
    init()
    :ets.delete_all_objects(@table)

    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.each(fn
      {id, {x, y, true}} ->
        cell = cell_key(x, y)
        :ets.insert(@table, {cell, id})
      _ -> :ok
    end)

    :ok
  end

  @doc "Update an agent's position in the index."
  @spec update(String.t(), {integer(), integer()}, {integer(), integer()}) :: :ok
  def update(agent_id, {old_x, old_y}, {new_x, new_y}) do
    init()
    old_cell = cell_key(old_x, old_y)
    new_cell = cell_key(new_x, new_y)

    if old_cell != new_cell do
      :ets.delete_object(@table, {old_cell, agent_id})
      :ets.insert(@table, {new_cell, agent_id})
    end

    :ok
  end

  @doc "Insert an agent into the index."
  @spec insert(String.t(), {integer(), integer()}) :: :ok
  def insert(agent_id, {x, y}) do
    init()
    :ets.insert(@table, {cell_key(x, y), agent_id})
    :ok
  end

  @doc "Remove an agent from the index."
  @spec remove(String.t(), {integer(), integer()}) :: :ok
  def remove(agent_id, {x, y}) do
    init()
    :ets.delete_object(@table, {cell_key(x, y), agent_id})
    :ok
  end

  @doc """
  Find all agents within `radius` of `{x, y}`.
  O(1) per cell — checks only the relevant cells instead of all agents.
  """
  @spec nearby({integer(), integer()}, integer()) :: [String.t()]
  def nearby({x, y}, radius \\ 5) do
    init()
    min_cx = div(x - radius, @cell_size)
    max_cx = div(x + radius, @cell_size)
    min_cy = div(y - radius, @cell_size)
    max_cy = div(y + radius, @cell_size)

    for cx <- min_cx..max_cx,
        cy <- min_cy..max_cy,
        {_cell, agent_id} <- :ets.lookup(@table, {cx, cy}),
        do: agent_id
  end

  @doc "Cell key for a world position."
  @spec cell_key(integer(), integer()) :: {integer(), integer()}
  def cell_key(x, y), do: {div(x, @cell_size), div(y, @cell_size)}

  @doc "Number of agents in the index."
  @spec count() :: non_neg_integer()
  def count do
    init()
    :ets.info(@table, :size)
  end
end
