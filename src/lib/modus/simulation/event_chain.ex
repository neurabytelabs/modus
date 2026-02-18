defmodule Modus.Simulation.EventChain do
  @moduledoc """
  EventChain — Complex cascading event system.

  Implements event chains where one event can trigger subsequent events:
  - drought → famine → migration → conflict
  - celebration → festival → cultural_bloom
  - discovery → exploration_boom → settlement

  Each chain link has a probability and delay (in ticks).

  ## Spinoza: *Causa sui* — Every event contains the seed of its successor.
  """

  @chains %{
    drought: [
      %{event: :famine, probability: 0.7, delay: 80, severity_mod: 0},
      %{event: :migration_wave, probability: 0.4, delay: 150, severity_mod: -1},
      %{event: :conflict, probability: 0.3, delay: 200, severity_mod: 0}
    ],
    famine: [
      %{event: :migration_wave, probability: 0.6, delay: 60, severity_mod: 0},
      %{event: :plague, probability: 0.3, delay: 100, severity_mod: -1}
    ],
    flood: [
      %{event: :famine, probability: 0.4, delay: 50, severity_mod: -1},
      %{event: :discovery, probability: 0.2, delay: 30, severity_mod: 0}
    ],
    fire: [
      %{event: :drought, probability: 0.3, delay: 40, severity_mod: 0}
    ],
    golden_age: [
      %{event: :festival, probability: 0.8, delay: 30, severity_mod: 0},
      %{event: :migration_wave, probability: 0.5, delay: 60, severity_mod: 0}
    ],
    festival: [
      %{event: :golden_age, probability: 0.2, delay: 50, severity_mod: 0}
    ],
    discovery: [
      %{event: :festival, probability: 0.4, delay: 20, severity_mod: 0}
    ]
  }

  @doc "Get chain reactions for an event type."
  @spec get_chain(atom()) :: [map()]
  def get_chain(event_type) do
    Map.get(@chains, event_type, [])
  end

  @doc "Evaluate and schedule chain reactions for a completed/active event."
  @spec evaluate(atom(), non_neg_integer(), non_neg_integer()) :: [
          {atom(), non_neg_integer(), non_neg_integer()}
        ]
  def evaluate(event_type, current_tick, severity) do
    @chains
    |> Map.get(event_type, [])
    |> Enum.filter(fn link -> :rand.uniform() <= link.probability end)
    |> Enum.map(fn link ->
      new_severity = max(1, min(3, severity + link.severity_mod))
      trigger_tick = current_tick + link.delay
      {link.event, trigger_tick, new_severity}
    end)
  end

  @doc "All defined chain types."
  def chain_types, do: Map.keys(@chains)
end
