defmodule Modus.Performance.Monitor do
  @moduledoc """
  Performance Monitor — Collects real-time system health metrics
  for the Performance Monitor UI overlay.
  """

  @doc "Get current performance metrics for the UI."
  @spec metrics() :: map()
  def metrics do
    mem = :erlang.memory()
    agent_count = try do
      Registry.count(Modus.AgentRegistry)
    catch
      _, _ -> 0
    end

    tick_info = try do
      Modus.Simulation.Ticker.status()
    catch
      _, _ -> %{tick: 0, state: :paused}
    end

    total_mb = mem[:total] / (1024 * 1024)
    proc_mb = mem[:processes] / (1024 * 1024)
    ets_mb = mem[:ets] / (1024 * 1024)

    # CPU approximation via scheduler utilization
    cpu = try do
      :scheduler.utilization(1)
      |> Enum.filter(fn {type, _, _} -> type == :normal end)
      |> Enum.map(fn {_, _, pct} -> pct end)
      |> then(fn list ->
        if list == [], do: 0.0, else: Enum.sum(list) / length(list) * 100
      end)
    catch
      _, _ -> 0.0
    end

    health = cond do
      total_mb > 500 or agent_count > 150 -> :critical
      total_mb > 300 or agent_count > 100 -> :warning
      true -> :healthy
    end

    %{
      agent_count: agent_count,
      tick: tick_info.tick,
      tick_state: tick_info.state,
      memory_total_mb: Float.round(total_mb, 1),
      memory_processes_mb: Float.round(proc_mb, 1),
      memory_ets_mb: Float.round(ets_mb, 1),
      cpu_percent: Float.round(ensure_float(cpu), 1),
      health: health
    }
  end

  defp ensure_float(v) when is_float(v), do: v
  defp ensure_float(v) when is_integer(v), do: v * 1.0
  defp ensure_float(_), do: 0.0
end
