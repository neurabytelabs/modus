defmodule Modus.Simulation.WorldSystems do
  @moduledoc """
  WorldSystems — Coordinates economy and lifecycle ticks.

  Subscribes to simulation tick PubSub and runs world-level systems
  (economy, lifecycle) each tick. Lightweight GenServer.
  """
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:tick, tick_number}, state) do
    # Run world-level systems (non-blocking, fire-and-forget)
    Modus.Simulation.Economy.tick(tick_number)
    Modus.Simulation.Lifecycle.tick(tick_number)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
