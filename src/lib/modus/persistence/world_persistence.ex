defmodule Modus.Persistence.WorldPersistence do
  @moduledoc """
  WorldPersistence — Save and load world state to/from SQLite.

  Captures:
  - World config (template, danger_level, seed, grid_size)
  - Current tick
  - All agent states (position, needs, personality, relationships, etc.)
  """
  require Logger

  alias Modus.Repo
  alias Modus.Schema.World, as: WorldSchema
  alias Modus.Simulation.{World, Agent, AgentSupervisor, Ticker}
  import Ecto.Query

  @doc "Save current simulation state to SQLite. Returns {:ok, world} or {:error, reason}."
  def save(name \\ nil) do
    try do
      world_state = World.get_state()
      tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0

      name = name || "#{world_state.name}_t#{tick}"

      config = %{
        template: to_string(world_state.config.template),
        danger_level: to_string(world_state.config.danger_level),
        resource_abundance: to_string(world_state.config.resource_abundance),
        seed: world_state.config.seed,
        grid_size: %{x: elem(world_state.grid_size, 0), y: elem(world_state.grid_size, 1)}
      }

      agents = collect_agent_states()

      state = %{
        tick: tick,
        world_name: world_state.name,
        agents: agents
      }

      attrs = %{
        name: name,
        template: to_string(world_state.config.template),
        config_json: Jason.encode!(config),
        state_json: Jason.encode!(state)
      }

      changeset = WorldSchema.changeset(%WorldSchema{}, attrs)

      case Repo.insert(changeset) do
        {:ok, world} ->
          Logger.info("World saved: #{name} (#{length(agents)} agents, tick #{tick})")
          {:ok, %{id: world.id, name: world.name, agents: length(agents), tick: tick}}
        {:error, changeset} ->
          {:error, inspect(changeset.errors)}
      end
    catch
      kind, reason ->
        Logger.error("World save failed: #{inspect({kind, reason})}")
        {:error, "Save failed: #{inspect(reason)}"}
    end
  end

  @doc "Load a saved world by id. Returns {:ok, info} or {:error, reason}."
  def load(world_id) do
    case Repo.get(WorldSchema, world_id) do
      nil ->
        {:error, "World not found"}

      saved ->
        try do
          config = Jason.decode!(saved.config_json)
          state = Jason.decode!(saved.state_json)

          # Stop current simulation
          Ticker.pause()
          AgentSupervisor.terminate_all()
          if Process.whereis(World), do: GenServer.stop(World)

          # Create new world with saved config
          world = World.new(
            state["world_name"] || saved.name,
            template: String.to_atom(config["template"] || "village"),
            danger_level: String.to_atom(config["danger_level"] || "normal"),
            resource_abundance: String.to_atom(config["resource_abundance"] || "medium"),
            seed: config["seed"] || :rand.uniform(1_000_000),
            grid_size: {
              get_in(config, ["grid_size", "x"]) || 50,
              get_in(config, ["grid_size", "y"]) || 50
            }
          )

          {:ok, _pid} = World.start_link(world)

          # Restore agents
          agents_data = state["agents"] || []
          restored = restore_agents(agents_data)

          Logger.info("World loaded: #{saved.name} (#{length(restored)} agents, tick #{state["tick"]})")
          {:ok, %{id: saved.id, name: saved.name, agents: length(restored), tick: state["tick"] || 0}}
        catch
          kind, reason ->
            Logger.error("World load failed: #{inspect({kind, reason})}")
            {:error, "Load failed: #{inspect(reason)}"}
        end
    end
  end

  @doc "List all saved worlds."
  def list do
    WorldSchema
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Enum.map(fn w ->
      state = case Jason.decode(w.state_json || "{}") do
        {:ok, s} -> s
        _ -> %{}
      end

      %{
        id: w.id,
        name: w.name,
        template: w.template,
        tick: state["tick"] || 0,
        agents: length(state["agents"] || []),
        saved_at: w.inserted_at
      }
    end)
  end

  @doc "Delete a saved world."
  def delete(world_id) do
    case Repo.get(WorldSchema, world_id) do
      nil -> {:error, "Not found"}
      world -> Repo.delete(world)
    end
  end

  # ── Private ─────────────────────────────────────────────

  defp collect_agent_states do
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.reduce([], fn {_id, pid}, acc ->
      try do
        state = GenServer.call(pid, :get_state, 2_000)
        agent_map = %{
          id: state.id,
          name: state.name,
          position: %{x: elem(state.position, 0), y: elem(state.position, 1)},
          occupation: to_string(state.occupation),
          personality: %{
            openness: state.personality.openness,
            conscientiousness: state.personality.conscientiousness,
            extraversion: state.personality.extraversion,
            agreeableness: state.personality.agreeableness,
            neuroticism: state.personality.neuroticism
          },
          needs: %{
            hunger: state.needs.hunger,
            social: state.needs.social,
            rest: state.needs.rest,
            shelter: state.needs.shelter
          },
          relationships: serialize_relationships(state.relationships),
          current_action: to_string(state.current_action),
          conatus_score: state.conatus_score,
          alive: state.alive?,
          age: state.age
        }
        [agent_map | acc]
      catch
        :exit, _ -> acc
      end
    end)
  end

  defp serialize_relationships(rels) when is_map(rels) do
    Enum.map(rels, fn {id, {type, strength}} ->
      %{agent_id: id, type: to_string(type), strength: strength}
    end)
  end
  defp serialize_relationships(_), do: []

  defp restore_agents(agents_data) do
    Enum.reduce(agents_data, [], fn data, acc ->
      try do
        agent = %Agent{
          id: data["id"] || Agent.__struct__().id |> then(fn _ -> :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower) end),
          name: data["name"] || "Unknown",
          position: {data["position"]["x"] || 25, data["position"]["y"] || 25},
          occupation: String.to_atom(data["occupation"] || "explorer"),
          personality: %{
            openness: get_in(data, ["personality", "openness"]) || :rand.uniform(),
            conscientiousness: get_in(data, ["personality", "conscientiousness"]) || :rand.uniform(),
            extraversion: get_in(data, ["personality", "extraversion"]) || :rand.uniform(),
            agreeableness: get_in(data, ["personality", "agreeableness"]) || :rand.uniform(),
            neuroticism: get_in(data, ["personality", "neuroticism"]) || :rand.uniform()
          },
          needs: %{
            hunger: get_in(data, ["needs", "hunger"]) || 50.0,
            social: get_in(data, ["needs", "social"]) || 50.0,
            rest: get_in(data, ["needs", "rest"]) || 80.0,
            shelter: get_in(data, ["needs", "shelter"]) || 70.0
          },
          relationships: deserialize_relationships(data["relationships"]),
          memory: [],
          current_action: String.to_atom(data["current_action"] || "idle"),
          conatus_score: data["conatus_score"] || 5.0,
          alive?: data["alive"] != false,
          age: data["age"] || 0
        }

        case AgentSupervisor.spawn_agent(agent) do
          {:ok, _pid} -> [agent | acc]
          _ -> acc
        end
      catch
        _, _ -> acc
      end
    end)
  end

  defp deserialize_relationships(nil), do: %{}
  defp deserialize_relationships(rels) when is_list(rels) do
    Enum.reduce(rels, %{}, fn rel, acc ->
      Map.put(acc, rel["agent_id"], {String.to_atom(rel["type"] || "acquaintance"), rel["strength"] || 0.0})
    end)
  end
  defp deserialize_relationships(_), do: %{}
end
