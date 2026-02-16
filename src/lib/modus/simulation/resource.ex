defmodule Modus.Simulation.Resource do
  @moduledoc """
  Resource — Gatherable items in the MODUS world.

  Resources exist at positions on the grid and can be depleted
  by agents through gathering actions.

  ## Types
  - `:food`  — sustenance, reduces hunger
  - `:wood`  — building material
  - `:stone` — building material
  - `:water` — hydration
  """

  defstruct [:id, :type, :position, :amount]

  @type resource_type :: :food | :wood | :stone | :water
  @type t :: %__MODULE__{
          id: String.t(),
          type: resource_type(),
          position: {integer(), integer()},
          amount: float()
        }

  @doc "Create a new resource."
  @spec new(resource_type(), {integer(), integer()}, number()) :: t()
  def new(type, position, amount \\ 10.0) do
    %__MODULE__{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      type: type,
      position: position,
      amount: amount / 1
    }
  end

  @doc "Gather from a resource, returning {gathered_amount, updated_resource}."
  @spec gather(t(), float()) :: {float(), t()}
  def gather(%__MODULE__{amount: amount} = resource, requested) do
    taken = min(requested, amount)
    {taken, %{resource | amount: amount - taken}}
  end

  @doc "Check if resource is depleted."
  @spec depleted?(t()) :: boolean()
  def depleted?(%__MODULE__{amount: amount}), do: amount <= 0.0
end
