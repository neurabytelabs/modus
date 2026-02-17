defmodule Modus.Simulation.Resource do
  @moduledoc """
  Resource — Gatherable items in the MODUS world.
  v1.6.0 Creator: Nature is survival infrastructure.

  Resources exist at positions on the grid and can be depleted
  by agents through gathering actions. Resources are FINITE but RENEWABLE.

  ## Types
  - `:food`        — sustenance, reduces hunger
  - `:wood`        — building material (from forest)
  - `:stone`       — building material (from mountain)
  - `:water`       — hydration (from water tiles)
  - `:fish`        — food from water
  - `:fresh_water` — drinking from water
  - `:crops`       — food from farms
  - `:herbs`       — trade goods from flowers
  - `:wild_berries` — emergency food from grass

  ## Resource Nodes
  Placed via World Builder: food_source, water_well, wood_pile, stone_quarry
  """

  defstruct [:id, :type, :position, :amount, :max_amount, :depleted_at]

  @type resource_type :: :food | :wood | :stone | :water | :fish | :fresh_water |
                         :crops | :herbs | :wild_berries
  @type node_type :: :food_source | :water_well | :wood_pile | :stone_quarry
  @type t :: %__MODULE__{
          id: String.t(),
          type: resource_type() | node_type(),
          position: {integer(), integer()},
          amount: float(),
          max_amount: float(),
          depleted_at: integer() | nil
        }

  @respawn_ticks 200

  @doc "Terrain → harvestable resource types."
  def terrain_resources(:forest),   do: [:wood]
  def terrain_resources(:water),    do: [:fish, :fresh_water]
  def terrain_resources(:farm),     do: [:crops]
  def terrain_resources(:mountain), do: [:stone]
  def terrain_resources(:flowers),  do: [:herbs]
  def terrain_resources(:grass),    do: [:wild_berries]
  def terrain_resources(:desert),   do: []
  def terrain_resources(:sand),     do: []
  def terrain_resources(_),         do: []

  @doc "Resource node types and what they provide."
  def node_resources(:food_source),  do: %{food: 20.0}
  def node_resources(:water_well),   do: %{fresh_water: 15.0}
  def node_resources(:wood_pile),    do: %{wood: 25.0}
  def node_resources(:stone_quarry), do: %{stone: 20.0}
  def node_resources(_),             do: %{}

  @doc "Create a new resource."
  @spec new(resource_type(), {integer(), integer()}, number()) :: t()
  def new(type, position, amount \\ 10.0) do
    amt = amount / 1
    %__MODULE__{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      type: type,
      position: position,
      amount: amt,
      max_amount: amt,
      depleted_at: nil
    }
  end

  @doc "Gather from a resource, returning {gathered_amount, updated_resource}."
  @spec gather(t(), float()) :: {float(), t()}
  def gather(%__MODULE__{amount: amount} = resource, requested) do
    taken = min(requested, amount)
    new_amount = amount - taken
    depleted_at = if new_amount <= 0.0, do: resource.depleted_at, else: nil
    {taken, %{resource | amount: new_amount, depleted_at: depleted_at}}
  end

  @doc "Check if resource is depleted."
  @spec depleted?(t()) :: boolean()
  def depleted?(%__MODULE__{amount: amount}), do: amount <= 0.0

  @doc "Check if resource should respawn (depleted for @respawn_ticks)."
  def should_respawn?(%__MODULE__{depleted_at: nil}), do: false
  def should_respawn?(%__MODULE__{depleted_at: tick}), do: tick + @respawn_ticks <= current_tick()

  @doc "Respawn a depleted resource to full."
  def respawn(%__MODULE__{} = resource) do
    %{resource | amount: resource.max_amount, depleted_at: nil}
  end

  defp current_tick do
    if Process.whereis(Modus.Simulation.Ticker) do
      try do Modus.Simulation.Ticker.current_tick() catch _, _ -> 0 end
    else
      0
    end
  end

  @doc "Ticks needed for respawn."
  def respawn_ticks, do: @respawn_ticks
end
