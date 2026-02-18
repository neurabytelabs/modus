defmodule Modus.Simulation.ResourceSystem do
  @moduledoc """
  ResourceSystem — Manages renewable resources on the grid.

  Every 50 ticks, regenerates resources based on terrain type.
  Night doubles regeneration rates.
  """
  use GenServer

  @regen_interval 50

  @regen_rates %{
    forest: %{food: {2, 5}, wood: {1, 8}},
    grass: %{food: {1, 3}, wild_berries: {0.5, 2}},
    water: %{fish: {1, 6}, fresh_water: {2, 10}},
    mountain: %{stone: {1, 10}, ore: {0.5, 4}},
    farm: %{crops: {3, 12}, food: {2, 8}},
    flowers: %{herbs: {1, 6}, food: {0.5, 2}}
  }

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Gather resources from a cell. Returns {actual_amount, remaining}."
  @spec gather({integer(), integer()}, atom(), number()) :: {:ok, number()} | {:error, term()}
  def gather(position, resource_type, amount) do
    GenServer.call(__MODULE__, {:gather, position, resource_type, amount})
  end

  # ── GenServer ───────────────────────────────────────────────

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    {:ok, state}
  end

  @impl true
  def handle_call({:gather, {x, y}, resource_type, amount}, _from, state) do
    result = do_gather({x, y}, resource_type, amount)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:tick, tick_number}, state) do
    if rem(tick_number, @regen_interval) == 0 do
      regenerate_all()
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internal ────────────────────────────────────────────────

  defp do_gather({x, y}, resource_type, amount) do
    world =
      try do
        Modus.Simulation.World.get_state()
      catch
        :exit, _ -> nil
      end

    if world == nil do
      {:error, :no_world}
    else
      case :ets.lookup(world.grid_table, {x, y}) do
        [{{^x, ^y}, cell}] ->
          current = Map.get(cell.resources, resource_type, 0)
          actual = min(ensure_float(amount), ensure_float(current))
          actual = Float.round(ensure_float(actual), 1)

          new_resources =
            Map.put(cell.resources, resource_type, Float.round(ensure_float(current - actual), 1))

          :ets.insert(world.grid_table, {{x, y}, %{cell | resources: new_resources}})
          {:ok, actual}

        _ ->
          {:error, :out_of_bounds}
      end
    end
  end

  defp regenerate_all do
    world =
      try do
        Modus.Simulation.World.get_state()
      catch
        :exit, _ -> nil
      end

    if world do
      night? =
        try do
          Modus.Simulation.Environment.is_night?()
        catch
          :exit, _ -> false
        end

      multiplier = if night?, do: 2.0, else: 1.0
      {max_x, max_y} = world.grid_size

      for x <- 0..(max_x - 1), y <- 0..(max_y - 1) do
        case :ets.lookup(world.grid_table, {x, y}) do
          [{{^x, ^y}, cell}] ->
            rates = Map.get(@regen_rates, cell.terrain)

            if rates do
              new_resources =
                Enum.reduce(rates, cell.resources, fn {res, {rate, max_val}}, acc ->
                  current = ensure_float(Map.get(acc, res, 0))
                  added = ensure_float(rate) * multiplier
                  new_val = min(current + added, ensure_float(max_val))
                  Map.put(acc, res, Float.round(new_val, 1))
                end)

              :ets.insert(world.grid_table, {{x, y}, %{cell | resources: new_resources}})
            end

          _ ->
            :ok
        end
      end
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0
end
