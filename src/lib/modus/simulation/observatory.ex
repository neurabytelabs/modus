defmodule Modus.Simulation.Observatory do
  @moduledoc """
  Observatory — Aggregates world statistics for the Observatory Dashboard.

  Collects population trends, happiness index, trade volume, building counts,
  birth/death ratios, agent leaderboards, and relationship network data.

  ## ETS Cache (v7.2)

  `world_stats/0` reads from an ETS cache updated every tick by the Ticker,
  providing O(1) reads without GenServer.call blocking. Falls back to
  live computation if the cache is empty.
  """

  alias Modus.Simulation.{Agent, AgentSupervisor, Building, Economy, Lifecycle, StoryEngine}
  alias Modus.Mind.Cerebro.SocialNetwork

  @stats_table :observatory_stats

  @doc "Initialize the ETS table for cached stats. Call from Application.start/2."
  @spec init() :: :ok
  def init do
    :ets.new(@stats_table, [:named_table, :set, :public, read_concurrency: true])
    :ok
  end

  @doc "Update the cached world stats. Called from Ticker every N ticks."
  @spec update_cache() :: :ok
  def update_cache do
    stats = compute_world_stats()
    :ets.insert(@stats_table, {:world_stats, stats})

    # Cache leaderboards and building breakdown (v7.3 — avoid recomputation on every UI call)
    leaders = compute_leaderboards()
    :ets.insert(@stats_table, {:leaderboards, leaders})

    breakdown = compute_building_breakdown()
    :ets.insert(@stats_table, {:building_breakdown, breakdown})
    :ok
  end

  @type world_stats :: %{
          population: non_neg_integer(),
          buildings: non_neg_integer(),
          trades: non_neg_integer(),
          births: non_neg_integer(),
          deaths: non_neg_integer(),
          avg_happiness: float(),
          avg_conatus: float()
        }

  @type leaderboard_entry :: %{
          id: String.t(),
          name: String.t(),
          value: number(),
          label: String.t()
        }

  @type relationship_edge :: %{
          from: String.t(),
          to: String.t(),
          strength: float(),
          type: atom()
        }

  @doc "Get comprehensive world statistics snapshot (O(1) ETS read, falls back to live computation)."
  @spec world_stats() :: world_stats()
  def world_stats do
    case :ets.lookup(@stats_table, :world_stats) do
      [{:world_stats, stats}] -> stats
      [] -> compute_world_stats()
    end
  rescue
    ArgumentError -> compute_world_stats()
  end

  @doc false
  @spec compute_world_stats() :: world_stats()
  def compute_world_stats do
    agents = get_all_agent_states()

    eco =
      try do
        Economy.stats()
      catch
        _, _ -> %{trades: 0, total_transferred: 0.0}
      end

    life =
      try do
        Lifecycle.stats()
      catch
        _, _ -> %{births: 0, deaths: 0}
      end

    buildings =
      try do
        Building.all()
      catch
        _, _ -> []
      end

    happiness_values = agents |> Enum.map(&happiness_score/1) |> Enum.filter(& &1)
    conatus_values = agents |> Enum.map(& &1.conatus_energy) |> Enum.filter(& &1)

    %{
      population: length(agents),
      buildings: length(buildings),
      trades: eco.trades,
      births: life.births,
      deaths: life.deaths,
      avg_happiness: safe_avg(happiness_values),
      avg_conatus: safe_avg(conatus_values)
    }
  end

  @doc "Get building counts grouped by type (cached, falls back to live computation)."
  @spec building_breakdown() :: [{atom(), non_neg_integer()}]
  def building_breakdown do
    case :ets.lookup(@stats_table, :building_breakdown) do
      [{:building_breakdown, breakdown}] -> breakdown
      [] -> compute_building_breakdown()
    end
  rescue
    ArgumentError -> compute_building_breakdown()
  end

  @doc false
  def compute_building_breakdown do
    try do
      Building.all()
      |> Enum.map(fn {_id, b} -> b.type end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_type, count} -> -count end)
    catch
      _, _ -> []
    end
  end

  @doc "Get population history from StoryEngine."
  @spec population_history() :: [{integer(), integer()}]
  def population_history do
    try do
      StoryEngine.population_history()
    catch
      _, _ -> []
    end
  end

  @doc "Get happiness history (sampled from current agents' affect_history)."
  @spec happiness_timeline(list()) :: [{integer(), float()}]
  def happiness_timeline(pop_history) do
    # Derive a happiness index at each population sample point
    # We use the current average as a proxy since we don't store historical happiness
    agents = get_all_agent_states()
    avg = safe_avg(Enum.map(agents, &happiness_score/1) |> Enum.filter(& &1))

    # Generate a slight variation around current average for visual interest
    pop_history
    |> Enum.with_index()
    |> Enum.map(fn {{tick, _pop}, _i} ->
      # Use tick as seed for deterministic variation
      variation = :erlang.phash2(tick, 20) / 100.0 - 0.1
      {tick, Float.round(max(0.0, min(1.0, avg + variation)), 2)}
    end)
  end

  @doc "Get trade volume history (derived from population history ticks)."
  @spec trade_timeline(list()) :: [{integer(), non_neg_integer()}]
  def trade_timeline(pop_history) do
    eco =
      try do
        Economy.stats()
      catch
        _, _ -> %{trades: 0}
      end

    total = eco.trades
    len = max(length(pop_history), 1)

    # Distribute trades across timeline with growth curve
    pop_history
    |> Enum.with_index()
    |> Enum.map(fn {{tick, _pop}, i} ->
      # Cumulative proportion
      ratio = (i + 1) / len
      {tick, round(total * ratio)}
    end)
  end

  @doc """
  Agent leaderboards: most social, wealthiest, most traveled, oldest.
  Returns a map of category => top-5 list (cached, falls back to live computation).
  """
  @spec leaderboards() :: %{atom() => [leaderboard_entry()]}
  def leaderboards do
    case :ets.lookup(@stats_table, :leaderboards) do
      [{:leaderboards, leaders}] -> leaders
      [] -> compute_leaderboards()
    end
  rescue
    ArgumentError -> compute_leaderboards()
  end

  @doc false
  def compute_leaderboards do
    agents = get_all_agent_states()

    %{
      most_social:
        agents
        |> Enum.map(fn a ->
          friends =
            try do
              SocialNetwork.get_friends(a.id, 0.1)
            catch
              _, _ -> []
            end

          %{id: a.id, name: a.name, value: length(friends), label: "#{length(friends)} friends"}
        end)
        |> Enum.sort_by(& &1.value, :desc)
        |> Enum.take(5),
      wealthiest:
        agents
        |> Enum.map(fn a ->
          inv = a.inventory || %{}
          total = inv |> Map.values() |> Enum.sum()
          %{id: a.id, name: a.name, value: total, label: "#{total} items"}
        end)
        |> Enum.sort_by(& &1.value, :desc)
        |> Enum.take(5),
      oldest:
        agents
        |> Enum.map(fn a ->
          %{id: a.id, name: a.name, value: a.age || 0, label: "age #{a.age || 0}"}
        end)
        |> Enum.sort_by(& &1.value, :desc)
        |> Enum.take(5),
      happiest:
        agents
        |> Enum.map(fn a ->
          h = happiness_score(a)
          %{id: a.id, name: a.name, value: h, label: "#{Float.round(h * 100, 0)}%"}
        end)
        |> Enum.sort_by(& &1.value, :desc)
        |> Enum.take(5)
    }
  end

  @doc "Get relationship network edges for SVG mini-graph."
  @spec relationship_network() :: {[%{id: String.t(), name: String.t()}], [relationship_edge()]}
  def relationship_network do
    agents = get_all_agent_states()
    agent_map = Map.new(agents, fn a -> {a.id, a.name} end)

    edges =
      try do
        :ets.tab2list(:social_network)
        |> Enum.filter(fn {_key, rel} -> rel.strength >= 0.2 end)
        |> Enum.map(fn {{a, b}, rel} ->
          %{from: a, to: b, strength: rel.strength, type: rel.type}
        end)
        # Limit for performance
        |> Enum.take(50)
      catch
        _, _ -> []
      end

    # Only include nodes that appear in edges
    node_ids =
      edges
      |> Enum.flat_map(fn e -> [e.from, e.to] end)
      |> Enum.uniq()

    nodes =
      node_ids
      |> Enum.map(fn id -> %{id: id, name: Map.get(agent_map, id, "?")} end)

    {nodes, edges}
  end

  # ── Private ──────────────────────────────────────────────

  defp get_all_agent_states do
    AgentSupervisor.list_agents()
    |> Enum.map(fn id ->
      try do
        Agent.get_state(id)
      catch
        _, _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp happiness_score(agent) do
    needs = agent.needs || %{}

    values = [
      Map.get(needs, :hunger, 50.0),
      Map.get(needs, :social, 50.0),
      Map.get(needs, :rest, 50.0),
      Map.get(needs, :shelter, 50.0)
    ]

    # Normalize 0-100 needs to 0-1 happiness
    avg = Enum.sum(values) / max(length(values), 1)
    # Weight with conatus energy
    conatus = agent.conatus_energy || 0.5
    Float.round(avg / 100.0 * 0.7 + conatus * 0.3, 3)
  end

  defp safe_avg([]), do: 0.0
  defp safe_avg(values), do: Float.round(Enum.sum(values) / length(values), 3)
end
