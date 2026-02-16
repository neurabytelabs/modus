defmodule Modus.Mind.Affect do
  @moduledoc "Affect states — Spinoza's theory of emotions"

  @type affect :: :joy | :sadness | :desire | :fear | :neutral

  @doc "Transition affect state based on event, personality, and conatus energy."
  @spec transition(affect(), atom(), map(), float()) :: {affect(), String.t()}
  def transition(current_affect, event, personality, conatus_energy) do
    case determine_transition(current_affect, event, personality, conatus_energy) do
      nil -> {current_affect, "no change"}
      {new_affect, reason} -> {new_affect, reason}
    end
  end

  defp determine_transition(_current, :action_success, _personality, conatus) when conatus > 0.7 do
    {:joy, "successful action with high conatus"}
  end

  defp determine_transition(_current, :action_success, %{openness: o}, _conatus) when o > 0.6 do
    {:desire, "success fuels curiosity"}
  end

  defp determine_transition(_current, :action_success, _personality, _conatus) do
    {:joy, "successful action"}
  end

  defp determine_transition(_current, :action_success_minor, %{openness: o}, _conatus) when o > 0.6 do
    {:desire, "exploring new areas"}
  end

  defp determine_transition(_current, :action_success_minor, _personality, _conatus), do: nil

  defp determine_transition(_current, :action_failure, _personality, conatus) when conatus < 0.3 do
    {:fear, "failure with low conatus"}
  end

  defp determine_transition(_current, :action_failure, _personality, _conatus) do
    {:sadness, "action failed"}
  end

  defp determine_transition(_current, :social_positive, %{extraversion: e}, _conatus) when e > 0.5 do
    {:joy, "social success (extravert)"}
  end

  defp determine_transition(_current, :social_positive, _personality, _conatus), do: nil

  defp determine_transition(_current, :social_negative, _personality, _conatus) do
    {:sadness, "social rejection"}
  end

  defp determine_transition(_current, :rest, _personality, _conatus) do
    {:neutral, "resting recovery"}
  end

  defp determine_transition(_current, :hunger_critical, _personality, _conatus) do
    {:fear, "critical hunger"}
  end

  defp determine_transition(_current, :natural_decay, _personality, conatus) when conatus < 0.3 do
    {:fear, "low conatus anxiety"}
  end

  defp determine_transition(_current, :natural_decay, _personality, _conatus), do: nil

  defp determine_transition(_current, _event, _personality, _conatus), do: nil

  @doc "Conatus modifier applied per tick based on current affect."
  @spec conatus_modifier(affect()) :: float()
  def conatus_modifier(:joy), do: 0.002
  def conatus_modifier(:sadness), do: -0.003
  def conatus_modifier(:desire), do: 0.001
  def conatus_modifier(:fear), do: -0.002
  def conatus_modifier(:neutral), do: 0.0
  def conatus_modifier(_), do: 0.0
end
