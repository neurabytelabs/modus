defmodule Modus.Application do
  @moduledoc """
  MODUS Application — Universe Simulation Platform

  Supervision tree:
    Modus.Repo          → SQLite database
    Phoenix.PubSub      → Event broadcasting
    ModusWeb.Endpoint    → HTTP/WebSocket server
    (Simulation modules will be added in Week 1)
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Modus.Repo,
      {Phoenix.PubSub, name: Modus.PubSub},
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
