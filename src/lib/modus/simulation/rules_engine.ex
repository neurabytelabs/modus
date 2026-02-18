defmodule Modus.Simulation.RulesEngine do
  @moduledoc """
  RulesEngine — Custom World Rules for MODUS simulations.

  ETS-backed configurable world parameters that affect simulation behavior:
  - time_speed: 0.5x to 3.0x tick rate multiplier
  - resource_abundance: :scarce / :normal / :abundant
  - danger_level: :peaceful / :moderate / :harsh / :extreme
  - social_tendency: 0.0 to 1.0 (how social agents are)
  - birth_rate: 0.0 to 2.0 multiplier
  - building_speed: 0.5 to 3.0 multiplier
  - mutation_rate: 0.0 to 1.0 (personality variance on birth)

  Presets provide quick configuration bundles.
  """

  @table :modus_rules_engine

  @type resource_abundance :: :scarce | :normal | :abundant
  @type danger_level :: :peaceful | :moderate | :harsh | :extreme

  @type rules :: %{
          time_speed: float(),
          resource_abundance: resource_abundance(),
          danger_level: danger_level(),
          social_tendency: float(),
          birth_rate: float(),
          building_speed: float(),
          mutation_rate: float(),
          preset: String.t() | nil
        }

  @default_rules %{
    time_speed: 1.0,
    resource_abundance: :normal,
    danger_level: :moderate,
    social_tendency: 0.5,
    birth_rate: 1.0,
    building_speed: 1.0,
    mutation_rate: 0.3,
    language: "en",
    preset: "Custom"
  }

  @presets %{
    "Peaceful Paradise" => %{
      time_speed: 1.0,
      resource_abundance: :abundant,
      danger_level: :peaceful,
      social_tendency: 0.8,
      birth_rate: 1.5,
      building_speed: 2.0,
      mutation_rate: 0.1
    },
    "Harsh Survival" => %{
      time_speed: 1.0,
      resource_abundance: :scarce,
      danger_level: :extreme,
      social_tendency: 0.3,
      birth_rate: 0.5,
      building_speed: 0.5,
      mutation_rate: 0.5
    },
    "Chaotic" => %{
      time_speed: 2.0,
      resource_abundance: :normal,
      danger_level: :harsh,
      social_tendency: 0.4,
      birth_rate: 1.5,
      building_speed: 1.5,
      mutation_rate: 0.9
    },
    "Utopia" => %{
      time_speed: 0.8,
      resource_abundance: :abundant,
      danger_level: :peaceful,
      social_tendency: 0.9,
      birth_rate: 1.2,
      building_speed: 2.5,
      mutation_rate: 0.0
    },
    "Evolution Lab" => %{
      time_speed: 3.0,
      resource_abundance: :normal,
      danger_level: :moderate,
      social_tendency: 0.5,
      birth_rate: 2.0,
      building_speed: 1.0,
      mutation_rate: 1.0
    }
  }

  # ── Init ────────────────────────────────────────────────────

  @doc "Initialize the rules engine ETS table."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ets.insert(@table, {:rules, @default_rules})
    :ok
  end

  # ── Public API ──────────────────────────────────────────────

  @doc "Get all current rules."
  @spec get_rules() :: rules()
  def get_rules do
    case :ets.lookup(@table, :rules) do
      [{:rules, rules}] -> rules
      _ -> @default_rules
    end
  end

  @doc "Get a single rule value."
  @spec get(atom()) :: term()
  def get(key) do
    rules = get_rules()
    Map.get(rules, key)
  end

  @doc "Update one or more rules. Resets preset to 'Custom' unless applying a preset."
  @spec update(map()) :: :ok
  def update(changes) when is_map(changes) do
    current = get_rules()
    updated = Map.merge(current, changes)

    # If not explicitly setting a preset, mark as Custom
    updated =
      if Map.has_key?(changes, :preset) do
        updated
      else
        Map.put(updated, :preset, "Custom")
      end

    :ets.insert(@table, {:rules, updated})

    # Broadcast changes
    Phoenix.PubSub.broadcast(Modus.PubSub, "modus:rules", {:rules_changed, updated})
    :ok
  end

  @doc "Apply a named preset."
  @spec apply_preset(String.t()) :: {:ok, rules()} | {:error, :unknown_preset}
  def apply_preset(preset_name) do
    case Map.get(@presets, preset_name) do
      nil ->
        {:error, :unknown_preset}

      preset_rules ->
        rules = Map.merge(preset_rules, %{preset: preset_name})
        :ets.insert(@table, {:rules, rules})
        Phoenix.PubSub.broadcast(Modus.PubSub, "modus:rules", {:rules_changed, rules})
        {:ok, rules}
    end
  end

  @doc "List all available presets."
  @spec presets() :: map()
  def presets, do: @presets

  @doc "Get preset names."
  @spec preset_names() :: [String.t()]
  def preset_names, do: Map.keys(@presets)

  @doc "Default rules."
  @spec defaults() :: rules()
  def defaults, do: @default_rules

  # ── Convenience Accessors ───────────────────────────────────

  @doc "Get time speed multiplier (0.5-3.0)."
  @spec time_speed() :: float()
  def time_speed, do: get(:time_speed) || 1.0

  @doc "Get resource abundance level."
  @spec resource_abundance() :: resource_abundance()
  def resource_abundance, do: get(:resource_abundance) || :normal

  @doc "Get danger level."
  @spec danger_level() :: danger_level()
  def danger_level, do: get(:danger_level) || :moderate

  @doc "Get social tendency (0.0-1.0)."
  @spec social_tendency() :: float()
  def social_tendency, do: get(:social_tendency) || 0.5

  @doc "Get birth rate multiplier."
  @spec birth_rate() :: float()
  def birth_rate, do: get(:birth_rate) || 1.0

  @doc "Get building speed multiplier."
  @spec building_speed() :: float()
  def building_speed, do: get(:building_speed) || 1.0

  @doc "Get mutation rate (0.0-1.0)."
  @spec mutation_rate() :: float()
  def mutation_rate, do: get(:mutation_rate) || 0.3

  @doc "Get world language."
  @spec language() :: String.t()
  def language, do: get(:language) || "en"

  # ── Serialization ───────────────────────────────────────────

  @doc "Serialize rules for JSON transport."
  @spec serialize() :: map()
  def serialize do
    rules = get_rules()

    %{
      time_speed: rules.time_speed,
      resource_abundance: to_string(rules.resource_abundance),
      danger_level: to_string(rules.danger_level),
      social_tendency: rules.social_tendency,
      birth_rate: rules.birth_rate,
      building_speed: rules.building_speed,
      mutation_rate: rules.mutation_rate,
      language: rules[:language] || "en",
      preset: rules.preset
    }
  end
end
