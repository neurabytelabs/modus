defmodule Modus.TestHelperUtils do
  @moduledoc "Shared test utilities for isolated environment setup."

  @doc "Ensure PubSub is available (skip start if already running globally)."
  def ensure_pubsub do
    case Process.whereis(Modus.PubSub) do
      nil ->
        {:ok, pid} = Phoenix.PubSub.Supervisor.start_link(name: Modus.PubSub)
        pid
      pid -> pid
    end
  end

  @doc "Ensure AgentRegistry is available."
  def ensure_registry do
    case Process.whereis(Modus.AgentRegistry) do
      nil ->
        {:ok, pid} = Registry.start_link(keys: :unique, name: Modus.AgentRegistry)
        pid
      pid ->
        pid
    end
  end

  @doc "Ensure Lifecycle ETS table exists."
  def ensure_lifecycle do
    Modus.Simulation.Lifecycle.init()
  end
end
