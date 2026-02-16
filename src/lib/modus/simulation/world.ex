defmodule Modus.Simulation.World do
  @moduledoc """
  World — The universe container.

  Manages the grid, resources, and coordinates the tick loop.
  In Spinoza's terms, the World is "Substance" — the one reality
  in which all agents (modi) exist.

  ## Architecture

  - Grid: 50x50 ETS table with terrain types
  - Tick: 100ms interval, coordinated by Ticker
  - Broadcast: Delta-only updates via PubSub
  """
  use GenServer

  defstruct [
    :id,
    :name,
    :grid_size,
    :current_tick,
    :status,
    :config,
    :created_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          grid_size: {integer(), integer()},
          current_tick: integer(),
          status: :initializing | :running | :paused | :stopped,
          config: map(),
          created_at: DateTime.t()
        }

  @doc "Create a new world with default 50x50 grid."
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    size = Keyword.get(opts, :grid_size, {50, 50})

    %__MODULE__{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      name: name,
      grid_size: size,
      current_tick: 0,
      status: :initializing,
      config: %{
        template: Keyword.get(opts, :template, :village),
        resource_abundance: Keyword.get(opts, :resource_abundance, :medium),
        danger_level: Keyword.get(opts, :danger_level, :normal)
      },
      created_at: DateTime.utc_now()
    }
  end

  # --- GenServer ---

  def start_link(world) do
    GenServer.start_link(__MODULE__, world, name: __MODULE__)
  end

  @impl true
  def init(world) do
    {:ok, %{world | status: :paused}}
  end

  @impl true
  def handle_call(:get_state, _from, world) do
    {:reply, world, world}
  end

  @impl true
  def handle_call(:status, _from, world) do
    {:reply, %{
      name: world.name,
      tick: world.current_tick,
      status: world.status,
      grid_size: world.grid_size
    }, world}
  end

  @impl true
  def handle_cast(:tick, world) do
    world = %{world | current_tick: world.current_tick + 1}
    {:noreply, world}
  end
end
