defmodule Modus.Application do
  @moduledoc """
  MODUS Application — Universe Simulation Platform

  Supervision tree:
    Modus.Repo             → SQLite database
    Phoenix.PubSub         → Event broadcasting
    Modus.AgentRegistry    → Process registry for agents
    Modus.AgentSupervisor  → DynamicSupervisor for agent processes
    ModusWeb.Endpoint      → HTTP/WebSocket server
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Modus.Repo,
      {Phoenix.PubSub, name: Modus.PubSub},
      {Registry, keys: :unique, name: Modus.AgentRegistry},
      Modus.Intelligence.DecisionCache,
      Modus.Simulation.AgentSupervisor,
      Modus.Simulation.EventLog,
      Modus.Intelligence.LlmScheduler,
      ModusWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Modus.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ModusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
