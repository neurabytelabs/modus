defmodule Modus.Mind.Conatus do
  @moduledoc "Conatus — the agent's will to persist (Spinoza Ethics III)"

  @doc "Calculate conatus change based on action outcome and affect state."
  @spec update_energy(float(), atom(), atom()) :: {float(), float(), String.t()}
  def update_energy(current_energy, event, affect_state) do
    {base_delta, reason} = base_delta(event)
    delta = apply_affect_multiplier(base_delta, event, affect_state)
    new_energy = clamp(current_energy + delta)
    {new_energy, delta, reason}
  end

  defp base_delta(:action_success), do: {0.10, "successful action"}
  defp base_delta(:action_success_minor), do: {0.03, "minor success (explore)"}
  defp base_delta(:action_failure), do: {-0.06, "action failed"}
  defp base_delta(:social_positive), do: {0.08, "positive social interaction"}
  defp base_delta(:social_negative), do: {-0.06, "negative social interaction"}
  defp base_delta(:rest), do: {0.02, "resting recovery"}
  defp base_delta(:hunger_critical), do: {-0.015, "critical hunger drain"}
  defp base_delta(:natural_decay), do: {-0.0005, "entropy"}
  defp base_delta(_), do: {0.0, "unknown event"}

  defp apply_affect_multiplier(delta, _event, :neutral), do: delta

  defp apply_affect_multiplier(delta, event, :joy) do
    cond do
      delta > 0 -> delta * 1.5
      event == :action_failure -> delta * 0.7
      true -> delta
    end
  end

  defp apply_affect_multiplier(delta, event, :sadness) do
    cond do
      delta > 0 -> delta * 0.5
      event == :action_failure -> delta * 1.5
      true -> delta * 1.3
    end
  end

  defp apply_affect_multiplier(delta, event, :desire) do
    cond do
      delta > 0 -> delta * 1.3
      event == :natural_decay -> delta * 0.5
      true -> delta
    end
  end

  defp apply_affect_multiplier(delta, _event, :fear) do
    cond do
      delta > 0 -> delta * 0.7
      delta < 0 -> delta * 1.3
      true -> delta
    end
  end

  defp apply_affect_multiplier(delta, _event, _), do: delta

  @doc "Is the agent still alive?"
  @spec alive?(float()) :: boolean()
  def alive?(energy), do: energy > 0.0

  @doc "Clamp energy to [0.0, 1.0]"
  @spec clamp(float()) :: float()
  def clamp(energy), do: max(0.0, min(1.0, energy))
end
