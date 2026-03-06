defmodule Modus.Simulation.Archaeology do
  @moduledoc """
  Archaeology — Ruins and artifact system.

  Dead settlements become ruins over time; agents can excavate
  ancient knowledge and treasures. New worlds may contain
  yerleştirilmiş antik kalıntılar da bulunur.

  Spinoza: *Ruina* — every civilization leaves traces, knowledge never perishes.

  ## Harabe Türleri
  - temple: Tapınak — kültür bonusu, nadiren antik yazıt
  - fortress: Kale — silah/zırh artefaktları
  - village: Köy — günlük eşya, tarifler
  - monument: Anıt — büyük kültür bonusu, nadir

  ## Artefakt Türleri
  - tool: Alet — crafting bonus
  - writing: Yazıt — bilgi/tarif keşfi
  - treasure: Hazine — ekonomik değer
  - relic: Kutsal eşya — mood bonus

  ## Müze
  - Artefaktlar müzede sergilenebilir → kültür bonusu
  """

  require Logger

  @ruins_table :archaeology_ruins
  @artifacts_table :archaeology_artifacts
  @museums_table :archaeology_museums

  # Decay: bina harabeye dönüşme süresi (tick)
  @decay_threshold 2000
  # Kazı başarı şansı (base)
  @excavation_base_chance 0.3
  # Maksimum artefakt per harabe
  @max_artifacts_per_ruin 5

  @ruin_types [:temple, :fortress, :village, :monument]

  @ruin_emojis %{
    temple: "🏛️",
    fortress: "🏰",
    village: "🏚️",
    monument: "🗿"
  }

  @ruin_culture_bonus %{
    temple: 15.0,
    fortress: 5.0,
    village: 8.0,
    monument: 20.0
  }

  # Artifact types: :tool, :writing, :treasure, :relic

  @haunted_chance 0.2

  # ── Types ──────────────────────────────────────────────

  @type ruin_type :: :temple | :fortress | :village | :monument
  @type artifact_type :: :tool | :writing | :treasure | :relic

  @type ruin :: %{
          id: String.t(),
          type: ruin_type(),
          position: {integer(), integer()},
          artifacts: [artifact()],
          discovered: boolean(),
          haunted: boolean(),
          decay_level: float(),
          created_tick: integer(),
          original_building_id: String.t() | nil
        }

  @type artifact :: %{
          id: String.t(),
          type: artifact_type(),
          name: String.t(),
          description: String.t(),
          value: float(),
          discovered_by: String.t() | nil,
          discovered_tick: integer() | nil,
          in_museum: boolean()
        }

  # ── ETS Setup ─────────────────────────────────────────

  def init_table do
    if :ets.whereis(@ruins_table) == :undefined do
      :ets.new(@ruins_table, [:named_table, :set, :public, read_concurrency: true])
    end

    if :ets.whereis(@artifacts_table) == :undefined do
      :ets.new(@artifacts_table, [:named_table, :set, :public, read_concurrency: true])
    end

    if :ets.whereis(@museums_table) == :undefined do
      :ets.new(@museums_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  # ── Public API ────────────────────────────────────────

  @doc "Tüm harabeler."
  @spec get_all_ruins() :: [ruin()]
  def get_all_ruins do
    case :ets.whereis(@ruins_table) do
      :undefined -> []
      _ -> :ets.tab2list(@ruins_table) |> Enum.map(fn {_id, ruin} -> ruin end)
    end
  end

  @doc "Pozisyona göre harabe bul."
  @spec get_ruin_at({integer(), integer()}) :: ruin() | nil
  def get_ruin_at(position) do
    get_all_ruins() |> Enum.find(fn r -> r.position == position end)
  end

  @doc "ID ile harabe bul."
  @spec get_ruin(String.t()) :: ruin() | nil
  def get_ruin(id) do
    case :ets.whereis(@ruins_table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@ruins_table, id) do
          [{_id, ruin}] -> ruin
          _ -> nil
        end
    end
  end

  @doc "Tüm artefaktlar."
  @spec get_all_artifacts() :: [artifact()]
  def get_all_artifacts do
    case :ets.whereis(@artifacts_table) do
      :undefined -> []
      _ -> :ets.tab2list(@artifacts_table) |> Enum.map(fn {_id, art} -> art end)
    end
  end

  @doc "Müzedeki artefaktlar."
  @spec get_museum_artifacts() :: [artifact()]
  def get_museum_artifacts do
    get_all_artifacts() |> Enum.filter(fn a -> a.in_museum end)
  end

  @doc "Müze kültür bonusu."
  @spec museum_culture_bonus() :: float()
  def museum_culture_bonus do
    get_museum_artifacts()
    |> Enum.reduce(0.0, fn art, acc ->
      base =
        case art.type do
          :relic -> 10.0
          :writing -> 7.0
          :treasure -> 5.0
          :tool -> 3.0
          _ -> 2.0
        end

      acc + base
    end)
  end

  # ── Ruin Creation ─────────────────────────────────────

  @doc "Create a new ruin (ancient/pre-generated)."
  @spec create_ancient_ruin(ruin_type(), {integer(), integer()}, integer()) :: ruin()
  def create_ancient_ruin(type, position, current_tick) when type in @ruin_types do
    init_table()

    artifacts = generate_artifacts(type, Enum.random(1..@max_artifacts_per_ruin))

    ruin = %{
      id: "ruin_#{:erlang.unique_integer([:positive])}",
      type: type,
      position: position,
      artifacts: Enum.map(artifacts, fn a -> a.id end),
      discovered: false,
      haunted: :rand.uniform() < @haunted_chance,
      decay_level: ensure_float(0.5 + :rand.uniform() * 0.5),
      created_tick: current_tick - Enum.random(5000..20000),
      original_building_id: nil
    }

    :ets.insert(@ruins_table, {ruin.id, ruin})

    Enum.each(artifacts, fn art ->
      :ets.insert(@artifacts_table, {art.id, art})
    end)

    Logger.info("Ancient ruin created: #{type} @ #{inspect(position)}")
    ruin
  end

  @doc "Bir binayı harabeye dönüştür (ölü yerleşim)."
  @spec convert_building_to_ruin(map(), integer()) :: ruin()
  def convert_building_to_ruin(building, current_tick) do
    init_table()

    ruin_type = building_to_ruin_type(Map.get(building, :type, :hut))
    artifact_count = Enum.random(0..3)
    artifacts = generate_artifacts(ruin_type, artifact_count)

    ruin = %{
      id: "ruin_#{:erlang.unique_integer([:positive])}",
      type: ruin_type,
      position: Map.get(building, :position, {0, 0}),
      artifacts: Enum.map(artifacts, fn a -> a.id end),
      discovered: false,
      haunted: :rand.uniform() < @haunted_chance,
      decay_level: 0.1,
      created_tick: current_tick,
      original_building_id: Map.get(building, :id)
    }

    :ets.insert(@ruins_table, {ruin.id, ruin})

    Enum.each(artifacts, fn art ->
      :ets.insert(@artifacts_table, {art.id, art})
    end)

    Logger.info("Bina harabeye dönüştü: #{ruin_type} @ #{inspect(ruin.position)}")
    ruin
  end

  @doc "Place ancient ruins during world creation."
  @spec generate_ancient_ruins(integer(), integer(), integer()) :: [ruin()]
  def generate_ancient_ruins(world_width, world_height, current_tick) do
    count = max(3, div(world_width * world_height, 400))

    Enum.map(1..count, fn _ ->
      type = Enum.random(@ruin_types)
      pos = {Enum.random(0..(world_width - 1)), Enum.random(0..(world_height - 1))}
      create_ancient_ruin(type, pos, current_tick)
    end)
  end

  # ── Excavation ────────────────────────────────────────

  @doc "Agent excavates a ruin. Returns an artifact on success."
  @spec excavate(String.t(), String.t(), integer()) ::
          {:ok, artifact()} | {:empty, String.t()} | {:fail, String.t()}
  def excavate(ruin_id, agent_id, current_tick) do
    case get_ruin(ruin_id) do
      nil ->
        {:fail, "Harabe bulunamadı"}

      ruin ->
        # Keşfedilmemiş artefaktlar
        undiscovered =
          ruin.artifacts
          |> Enum.map(&get_artifact/1)
          |> Enum.filter(fn a -> a != nil and a.discovered_by == nil end)

        cond do
          undiscovered == [] ->
            {:empty, "Bu harabede keşfedilecek bir şey kalmadı"}

          :rand.uniform() > excavation_chance(ruin) ->
            {:fail, "Kazı başarısız — tekrar dene"}

          true ->
            artifact = Enum.random(undiscovered)
            updated = %{artifact | discovered_by: agent_id, discovered_tick: current_tick}
            :ets.insert(@artifacts_table, {updated.id, updated})

            # Harabeyi keşfedilmiş olarak işaretle
            unless ruin.discovered do
              :ets.insert(@ruins_table, {ruin.id, %{ruin | discovered: true}})
            end

            Logger.info("Artefakt keşfedildi: #{updated.name} by #{agent_id}")
            {:ok, updated}
        end
    end
  end

  @doc "Artefaktı müzeye ekle."
  @spec add_to_museum(String.t()) :: :ok | :error
  def add_to_museum(artifact_id) do
    case get_artifact(artifact_id) do
      nil ->
        :error

      art ->
        if art.discovered_by != nil and not art.in_museum do
          :ets.insert(@artifacts_table, {art.id, %{art | in_museum: true}})
          Logger.info("Artefakt müzeye eklendi: #{art.name}")
          :ok
        else
          :error
        end
    end
  end

  # ── Decay Tick ────────────────────────────────────────

  @doc "Binaların zamanla harabeye dönüşmesini kontrol et."
  @spec check_building_decay([map()], integer()) :: [ruin()]
  def check_building_decay(buildings, current_tick) do
    buildings
    |> Enum.filter(fn b ->
      owner = Map.get(b, :owner_id)
      age = current_tick - Map.get(b, :built_tick, current_tick)
      # Sahipsiz binalar decay_threshold sonra harabeye dönüşür
      (owner == nil or owner == "") and age >= @decay_threshold
    end)
    |> Enum.map(fn b -> convert_building_to_ruin(b, current_tick) end)
  end

  @doc "Harabe bozulma ilerlemesi (her tick)."
  @spec advance_decay(integer()) :: :ok
  def advance_decay(_current_tick) do
    get_all_ruins()
    |> Enum.each(fn ruin ->
      new_decay = min(1.0, ensure_float(ruin.decay_level) + 0.0005)
      :ets.insert(@ruins_table, {ruin.id, %{ruin | decay_level: new_decay}})
    end)

    :ok
  end

  # ── Mood Effects ──────────────────────────────────────

  @doc "Harabenin mood etkisini hesapla (haunted = negatif)."
  @spec mood_effect(ruin()) :: float()
  def mood_effect(ruin) do
    base = Map.get(@ruin_culture_bonus, ruin.type, 5.0)
    if ruin.haunted, do: ensure_float(-base * 0.5), else: ensure_float(base * 0.1)
  end

  # ── Render Data ───────────────────────────────────────

  @doc "Convert a ruin to a render-ready map for the frontend."
  @spec to_render_data(ruin()) :: map()
  def to_render_data(ruin) do
    %{
      id: ruin.id,
      type: ruin.type,
      emoji: Map.get(@ruin_emojis, ruin.type, "🏚️"),
      position: ruin.position,
      discovered: ruin.discovered,
      haunted: ruin.haunted,
      decay_level: ensure_float(ruin.decay_level),
      artifact_count: length(ruin.artifacts),
      culture_bonus: Map.get(@ruin_culture_bonus, ruin.type, 0.0)
    }
  end

  @doc "Tüm harabeler için render data."
  @spec all_render_data() :: [map()]
  def all_render_data do
    get_all_ruins() |> Enum.map(&to_render_data/1)
  end

  # ── Stats ─────────────────────────────────────────────

  @doc "Arkeoloji istatistikleri."
  @spec stats() :: map()
  def stats do
    ruins = get_all_ruins()
    artifacts = get_all_artifacts()

    %{
      total_ruins: length(ruins),
      discovered_ruins: Enum.count(ruins, fn r -> r.discovered end),
      haunted_ruins: Enum.count(ruins, fn r -> r.haunted end),
      total_artifacts: length(artifacts),
      discovered_artifacts: Enum.count(artifacts, fn a -> a.discovered_by != nil end),
      museum_artifacts: Enum.count(artifacts, fn a -> a.in_museum end),
      museum_culture_bonus: museum_culture_bonus(),
      ruins_by_type: Enum.frequencies_by(ruins, fn r -> r.type end)
    }
  end

  # ── Private Helpers ───────────────────────────────────

  defp get_artifact(id) do
    case :ets.whereis(@artifacts_table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@artifacts_table, id) do
          [{_id, art}] -> art
          _ -> nil
        end
    end
  end

  defp generate_artifacts(ruin_type, count) when count > 0 do
    Enum.map(1..count, fn _ ->
      type = weighted_artifact_type()

      %{
        id: "artifact_#{:erlang.unique_integer([:positive])}",
        type: type,
        name: artifact_name(type, ruin_type),
        description: artifact_description(type, ruin_type),
        value: artifact_value(type),
        discovered_by: nil,
        discovered_tick: nil,
        in_museum: false
      }
    end)
  end

  defp generate_artifacts(_ruin_type, _count), do: []

  defp weighted_artifact_type do
    roll = :rand.uniform()

    cond do
      roll < 0.4 -> :tool
      roll < 0.7 -> :writing
      roll < 0.9 -> :treasure
      true -> :relic
    end
  end

  defp artifact_name(:tool, _),
    do: Enum.random(["Antik Çekiç", "Obsidyen Bıçak", "Bronz Keski", "Taş Balta", "Kemik İğne"])

  defp artifact_name(:writing, _),
    do:
      Enum.random(["Kil Tablet", "Papirüs Parçası", "Taş Yazıt", "Antik Harita", "Şifreli Rulo"])

  defp artifact_name(:treasure, _),
    do: Enum.random(["Altın Kolye", "Yakut Yüzük", "Gümüş Kupa", "Fildişi Heykel", "Jade Maske"])

  defp artifact_name(:relic, :temple),
    do: Enum.random(["Kutsal Kadeh", "Ritüel Bıçağı", "Dua Taşı", "Antik İkon"])

  defp artifact_name(:relic, _),
    do: Enum.random(["Mühürlü Kutu", "Gizemli Küre", "Eski Pusula", "Kristal Prizma"])

  defp artifact_description(:tool, _), do: "Eski bir uygarlığın zanaatkarlarına ait alet."
  defp artifact_description(:writing, _), do: "Kayıp bir dilin izlerini taşıyan yazıt."

  defp artifact_description(:treasure, _),
    do: "Bright and valuable — proof of past riches."

  defp artifact_description(:relic, _), do: "An ancient relic emanating mysterious energy."

  defp artifact_value(:tool), do: ensure_float(10.0 + :rand.uniform() * 20.0)
  defp artifact_value(:writing), do: ensure_float(15.0 + :rand.uniform() * 25.0)
  defp artifact_value(:treasure), do: ensure_float(30.0 + :rand.uniform() * 50.0)
  defp artifact_value(:relic), do: ensure_float(50.0 + :rand.uniform() * 100.0)

  defp building_to_ruin_type(building_type) do
    case building_type do
      t when t in [:market, :watchtower] -> :fortress
      :farm -> :village
      :mansion -> :monument
      _ -> Enum.random([:temple, :village])
    end
  end

  defp excavation_chance(ruin) do
    base = @excavation_base_chance
    haunted_penalty = if ruin.haunted, do: -0.1, else: 0.0
    decay_bonus = ensure_float(ruin.decay_level) * 0.2
    ensure_float(base + haunted_penalty + decay_bonus)
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
