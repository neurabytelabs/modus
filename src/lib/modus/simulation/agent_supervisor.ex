defmodule Modus.Simulation.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for agent processes.

  Each agent in the MODUS universe runs as a separate GenServer
  process under this supervisor — true BEAM-native concurrency.
  """
  use DynamicSupervisor

  alias Modus.Simulation.Agent

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Spawn a new agent process."
  @spec spawn_agent(Agent.t()) :: {:ok, pid()} | {:error, term()}
  def spawn_agent(%Agent{} = agent) do
    DynamicSupervisor.start_child(__MODULE__, {Agent, agent})
  end

  @doc "Kill an agent process by id."
  @spec kill_agent(String.t()) :: :ok | {:error, :not_found}
  def kill_agent(agent_id) do
    case Registry.lookup(Modus.AgentRegistry, agent_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  @doc "Terminate all agent processes."
  @spec terminate_all() :: :ok
  def terminate_all do
    for {id, _} <-
          Registry.select(Modus.AgentRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}]) do
      case Registry.lookup(Modus.AgentRegistry, id) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
        _ -> :ok
      end
    end

    :ok
  end

  @doc "List all running agent ids."
  @spec list_agents() :: [String.t()]
  def list_agents do
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
  end
end
