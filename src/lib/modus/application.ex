defmodule Modus.Application do
  @moduledoc """
  MODUS Application — Universe Simulation Platform
  """
  use Application

  @impl true
  def start(_type, _args) do
    # Initialize ETS-based affect memory before agents spawn
    Modus.Mind.AffectMemory.init()
    Modus.Mind.Cerebro.SocialNetwork.init()
    Modus.Mind.Cerebro.Group.init()
    Modus.Mind.Cerebro.AgentConversation.init()
    Modus.Simulation.Economy.init()
    Modus.Simulation.Lifecycle.init()
    Modus.Mind.Learning.init()
    Modus.Simulation.RulesEngine.init()
    Modus.Mind.Goals.init()
    Modus.Mind.Culture.init()
    Modus.Performance.SpatialIndex.init()
    Modus.Performance.GcTuning.apply_defaults()

    children = [
      Modus.Repo,
      {Finch, name: Modus.Finch, pools: %{default: [size: 10, count: 3]}},
      {Phoenix.PubSub, name: Modus.PubSub},
      {Registry, keys: :unique, name: Modus.AgentRegistry},
      Modus.Intelligence.DecisionCache,
      Modus.Intelligence.ResponseCache,
      Modus.Intelligence.LlmProvider,
      Modus.Simulation.AgentSupervisor,
      Modus.Simulation.EventLog,
      Modus.Intelligence.LlmScheduler,
      Modus.Persistence.SaveManager,
      Modus.Simulation.Ticker,
      Modus.Simulation.Environment,
      Modus.Simulation.ResourceSystem,
      Modus.Simulation.WorldSystems,
      Modus.Simulation.StoryEngine,
      Modus.Simulation.WorldHistory,
      Modus.Simulation.WorldEvents,
      Modus.Simulation.DivineIntervention,
      Modus.Simulation.Seasons,
      Modus.Simulation.Weather,
      Modus.Simulation.Wildlife,
      {Task.Supervisor, name: Modus.Nexus.InsightEngine.TaskSupervisor},
      Modus.Nexus.InsightEngine,
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
