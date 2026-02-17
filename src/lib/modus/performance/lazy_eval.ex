defmodule Modus.Performance.LazyEval do
  @moduledoc """
  LazyEval — Simplified processing for distant/off-screen agents.

  Agents far from any observer or interaction get reduced tick processing:
  - No LLM calls
  - Simplified need decay
  - No social interactions
  - Movement only every N ticks
  """

  @lazy_distance 20
  @lazy_tick_interval 5

  @doc "Determine if an agent should receive lazy (simplified) processing this tick."
  @spec lazy?(String.t(), {integer(), integer()}, non_neg_integer()) :: boolean()
  def lazy?(_agent_id, _position, tick) do
    # Lazy agents only process every @lazy_tick_interval ticks
    rem(tick, @lazy_tick_interval) != 0
  end

  @doc "Check if position is far from all active observers (other agents nearby)."
  @spec distant?({integer(), integer()}, non_neg_integer()) :: boolean()
  def distant?({x, y}, _tick) do
    nearby_count = try do
      Modus.Performance.SpatialIndex.nearby({x, y}, @lazy_distance) |> length()
    catch
      _, _ -> 1
    end
    # If very few neighbors, agent is in a remote area
    nearby_count <= 1
  end

  @doc "Simplified tick for lazy agents — minimal computation."
  @spec simplified_tick(map()) :: map()
  def simplified_tick(agent) do
    # Only decay needs slowly
    needs = agent.needs
    new_needs = %{
      needs
      | hunger: min(needs.hunger + 0.005, 100.0),
        rest: max(needs.rest - 0.005, 0.0)
    }
    %{agent | needs: new_needs}
  end
end
