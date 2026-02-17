defmodule Modus.TestHelperUtils do
  @moduledoc "Shared test utilities for isolated environment setup."

  @doc "Ensure PubSub is available (skip start if already running globally)."
  def ensure_pubsub do
    case Process.whereis(Modus.PubSub) do
      nil -> ExUnit.Callbacks.start_supervised!({Phoenix.PubSub, name: Modus.PubSub})
      pid -> pid
    end
  end

  @doc "Ensure AgentRegistry is available."
  def ensure_registry do
    case Process.whereis(Modus.AgentRegistry) do
      nil -> ExUnit.Callbacks.start_supervised!({Registry, keys: :unique, name: Modus.AgentRegistry})
      pid -> pid
    end
  end

  @doc "Ensure Lifecycle ETS table exists."
  def ensure_lifecycle do
    Modus.Simulation.Lifecycle.init()
  end
end
