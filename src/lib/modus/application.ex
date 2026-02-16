defmodule Modus.Application do
  @moduledoc """
  MODUS Application — Universe Simulation Platform
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Modus.Repo,
      {Finch, name: Modus.Finch, pools: %{default: [size: 10, count: 3]}},
      {Phoenix.PubSub, name: Modus.PubSub},
      {Registry, keys: :unique, name: Modus.AgentRegistry},
      Modus.Intelligence.DecisionCache,
      Modus.Intelligence.LlmProvider,
      Modus.Simulation.AgentSupervisor,
      Modus.Simulation.EventLog,
      Modus.Intelligence.LlmScheduler,
      Modus.Simulation.Ticker,
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
