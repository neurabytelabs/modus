defmodule Modus.Nexus.ActionEngine do
  @moduledoc """
  ActionEngine — Chat ile dünyayı değiştirme motoru.

  Nexus Router'dan gelen action intent'lerini işler:
  - terrain_modify: belirli alandaki biome'u değiştir
  - spawn_entity: yeni ajan ekle
  - config_update: decay rate, speed, danger level değiştir
  - rule_inject: yeni kural ekle (key-value)

  ## Safety

  Her komut önce validate edilir, sonra execute.
  Tehlikeli komutlar (terminate_all, world_reset) için onay mekanizması.
  Undo desteği: son komutu geri al (state snapshot).
  """
  use GenServer

  alias Modus.Simulation.{Agent, AgentSupervisor, TerrainGenerator}

  @valid_biomes ~w(ocean desert plains forest swamp mountain tundra)a
  # Reserved for future use: dangerous action types requiring confirmation
  # @dangerous_actions [:terminate_all, :world_reset, :kill_all_agents]
  @ets_rules :nexus_rules
  @ets_config :nexus_config

  defstruct undo_stack: [], pending_confirmation: nil

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Execute an action command. Returns {:ok, result} or {:error, reason}."
  @spec execute(atom(), map()) :: {:ok, String.t()} | {:error, String.t()} | {:confirm, String.t()}
  def execute(sub_intent, params) do
    GenServer.call(__MODULE__, {:execute, sub_intent, params})
  end

  @doc "Confirm a pending dangerous action."
  @spec confirm() :: {:ok, String.t()} | {:error, String.t()}
  def confirm do
    GenServer.call(__MODULE__, :confirm)
  end

  @doc "Cancel a pending dangerous action."
  @spec cancel() :: :ok
  def cancel do
    GenServer.call(__MODULE__, :cancel)
  end

  @doc "Undo the last action."
  @spec undo() :: {:ok, String.t()} | {:error, String.t()}
  def undo do
    GenServer.call(__MODULE__, :undo)
  end

  @doc "Get current custom rules."
  @spec get_rules() :: map()
  def get_rules do
    :ets.tab2list(@ets_rules) |> Map.new()
  end

  @doc "Get current config overrides."
  @spec get_config() :: map()
  def get_config do
    :ets.tab2list(@ets_config) |> Map.new()
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(:ok) do
    ensure_ets(@ets_rules)
    ensure_ets(@ets_config)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:execute, sub_intent, params}, _from, state) do
    case validate(sub_intent, params) do
      :ok ->
        if dangerous?(sub_intent, params) do
          pending = {sub_intent, params}
          {:reply, {:confirm, danger_message(sub_intent, params)},
           %{state | pending_confirmation: pending}}
        else
          {result, undo_entry} = do_execute(sub_intent, params)
          new_stack = if undo_entry, do: [undo_entry | state.undo_stack], else: state.undo_stack
          {:reply, result, %{state | undo_stack: Enum.take(new_stack, 20)}}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:confirm, _from, %{pending_confirmation: nil} = state) do
    {:reply, {:error, "⚠️ Onay bekleyen komut yok."}, state}
  end

  @impl true
  def handle_call(:confirm, _from, %{pending_confirmation: {sub, params}} = state) do
    {result, undo_entry} = do_execute(sub, params)
    new_stack = if undo_entry, do: [undo_entry | state.undo_stack], else: state.undo_stack
    {:reply, result, %{state | pending_confirmation: nil, undo_stack: Enum.take(new_stack, 20)}}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    {:reply, :ok, %{state | pending_confirmation: nil}}
  end

  @impl true
  def handle_call(:undo, _from, %{undo_stack: []} = state) do
    {:reply, {:error, "⚠️ Geri alınacak komut yok."}, state}
  end

  @impl true
  def handle_call(:undo, _from, %{undo_stack: [last | rest]} = state) do
    result = do_undo(last)
    {:reply, result, %{state | undo_stack: rest}}
  end

  # ── Validation ──────────────────────────────────────────

  defp validate(:terrain_modify, params) do
    with {:ok, _biome} <- validate_biome(params),
         {:ok, _coords} <- validate_coords(params) do
      :ok
    end
  end

  defp validate(:spawn_entity, params) do
    name = Map.get(params, :name, Map.get(params, "name"))
    if name && is_binary(name) && String.length(name) > 0,
      do: :ok,
      else: {:error, "❌ Ajan adı gerekli."}
  end

  defp validate(:config_change, params) do
    key = Map.get(params, :key, Map.get(params, "key"))
    value = Map.get(params, :value, Map.get(params, "value"))

    cond do
      is_nil(key) -> {:error, "❌ Config anahtarı gerekli."}
      is_nil(value) -> {:error, "❌ Config değeri gerekli."}
      not is_binary(key) and not is_atom(key) -> {:error, "❌ Geçersiz anahtar tipi."}
      true -> :ok
    end
  end

  defp validate(:rule_inject, params) do
    key = Map.get(params, :key, Map.get(params, "key"))
    value = Map.get(params, :value, Map.get(params, "value"))

    cond do
      is_nil(key) -> {:error, "❌ Kural adı gerekli."}
      is_nil(value) -> {:error, "❌ Kural değeri gerekli."}
      true -> :ok
    end
  end

  defp validate(_, _), do: {:error, "❌ Bilinmeyen action tipi."}

  defp validate_biome(params) do
    biome_raw = Map.get(params, :biome, Map.get(params, "biome"))

    biome =
      try do
        cond do
          is_atom(biome_raw) and biome_raw in @valid_biomes -> biome_raw
          is_binary(biome_raw) -> String.to_existing_atom(biome_raw)
          true -> nil
        end
      rescue
        ArgumentError -> nil
      end

    if biome && biome in @valid_biomes do
      {:ok, biome}
    else
      {:error, "❌ Geçersiz biome: #{inspect(biome_raw)}. Geçerli: #{inspect(@valid_biomes)}"}
    end
  end

  defp validate_coords(params) do
    x = Map.get(params, :x, Map.get(params, "x", 0))
    y = Map.get(params, :y, Map.get(params, "y", 0))
    radius = Map.get(params, :radius, Map.get(params, "radius", 1))

    cond do
      not is_integer(x) or not is_integer(y) -> {:error, "❌ Koordinatlar integer olmalı."}
      not is_integer(radius) or radius < 0 or radius > 10 -> {:error, "❌ Radius 0-10 arasında olmalı."}
      true -> {:ok, {x, y, radius}}
    end
  end

  # ── Execution ───────────────────────────────────────────

  defp do_execute(:terrain_modify, params) do
    biome_raw = Map.get(params, :biome, Map.get(params, "biome"))
    biome = if is_atom(biome_raw), do: biome_raw, else: String.to_existing_atom(biome_raw)
    x = Map.get(params, :x, Map.get(params, "x", 0))
    y = Map.get(params, :y, Map.get(params, "y", 0))
    radius = Map.get(params, :radius, Map.get(params, "radius", 1))

    # Snapshot old biomes for undo
    coords = for dx <- -radius..radius, dy <- -radius..radius, do: {x + dx, y + dy}

    old_data =
      Enum.map(coords, fn {cx, cy} ->
        {{cx, cy}, TerrainGenerator.get(cx, cy)}
      end)
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    # Apply new biome
    count =
      Enum.count(coords, fn {cx, cy} ->
        case TerrainGenerator.get(cx, cy) do
          nil -> false
          data ->
            new_data = %{data | biome: biome}
            :ets.insert(:modus_terrain, {{cx, cy}, new_data})
            true
        end
      end)

    undo = {:terrain_restore, old_data}
    {{:ok, "🗺️ #{count} tile #{biome} olarak değiştirildi (#{x},#{y} r=#{radius})."}, undo}
  end

  defp do_execute(:spawn_entity, params) do
    name = Map.get(params, :name, Map.get(params, "name", "Yeni Ajan"))
    x = Map.get(params, :x, Map.get(params, "x", Enum.random(5..45)))
    y = Map.get(params, :y, Map.get(params, "y", Enum.random(5..45)))
    occupation = Map.get(params, :occupation, Map.get(params, "occupation", :explorer))
    occupation = if is_binary(occupation), do: String.to_existing_atom(occupation), else: occupation

    agent = Agent.new(name, {x, y}, occupation)

    case AgentSupervisor.spawn_agent(agent) do
      {:ok, _pid} ->
        undo = {:kill_agent, agent.id}
        {{:ok, "🧬 '#{name}' oluşturuldu! Konum: (#{x},#{y}), Meslek: #{occupation}"}, undo}

      {:error, reason} ->
        {{:error, "❌ Ajan oluşturulamadı: #{inspect(reason)}"}, nil}
    end
  end

  defp do_execute(:config_change, params) do
    key = Map.get(params, :key, Map.get(params, "key")) |> to_string()
    value = Map.get(params, :value, Map.get(params, "value"))

    # Save old value for undo
    old_value =
      case :ets.lookup(@ets_config, key) do
        [{^key, v}] -> v
        [] -> :not_set
      end

    :ets.insert(@ets_config, {key, value})
    undo = {:config_restore, key, old_value}
    {{:ok, "⚙️ Config '#{key}' = #{inspect(value)} olarak ayarlandı."}, undo}
  end

  defp do_execute(:rule_inject, params) do
    key = Map.get(params, :key, Map.get(params, "key")) |> to_string()
    value = Map.get(params, :value, Map.get(params, "value"))

    old_value =
      case :ets.lookup(@ets_rules, key) do
        [{^key, v}] -> v
        [] -> :not_set
      end

    :ets.insert(@ets_rules, {key, value})
    undo = {:rule_restore, key, old_value}
    {{:ok, "📜 Kural '#{key}' = #{inspect(value)} eklendi."}, undo}
  end

  defp do_execute(_, _) do
    {{:error, "❌ Bilinmeyen action."}, nil}
  end

  # ── Undo ────────────────────────────────────────────────

  defp do_undo({:terrain_restore, old_data}) do
    Enum.each(old_data, fn {{cx, cy}, data} ->
      :ets.insert(:modus_terrain, {{cx, cy}, data})
    end)

    {:ok, "↩️ Terrain değişiklikleri geri alındı (#{length(old_data)} tile)."}
  end

  defp do_undo({:kill_agent, agent_id}) do
    case AgentSupervisor.kill_agent(agent_id) do
      :ok -> {:ok, "↩️ Ajan silindi."}
      {:error, :not_found} -> {:error, "⚠️ Ajan bulunamadı (zaten ölmüş olabilir)."}
    end
  end

  defp do_undo({:config_restore, key, :not_set}) do
    :ets.delete(@ets_config, key)
    {:ok, "↩️ Config '#{key}' kaldırıldı."}
  end

  defp do_undo({:config_restore, key, old_value}) do
    :ets.insert(@ets_config, {key, old_value})
    {:ok, "↩️ Config '#{key}' eski değerine döndü: #{inspect(old_value)}"}
  end

  defp do_undo({:rule_restore, key, :not_set}) do
    :ets.delete(@ets_rules, key)
    {:ok, "↩️ Kural '#{key}' kaldırıldı."}
  end

  defp do_undo({:rule_restore, key, old_value}) do
    :ets.insert(@ets_rules, {key, old_value})
    {:ok, "↩️ Kural '#{key}' eski değerine döndü: #{inspect(old_value)}"}
  end

  # ── Safety ──────────────────────────────────────────────

  defp dangerous?(:terrain_modify, params) do
    radius = Map.get(params, :radius, Map.get(params, "radius", 1))
    radius > 5
  end

  defp dangerous?(:spawn_entity, _), do: false
  defp dangerous?(:config_change, _), do: false
  defp dangerous?(:rule_inject, _), do: false
  defp dangerous?(_, _), do: false

  defp danger_message(:terrain_modify, params) do
    radius = Map.get(params, :radius, Map.get(params, "radius"))
    "⚠️ Büyük alan değişikliği (radius=#{radius}). #{(2 * radius + 1) * (2 * radius + 1)} tile etkilenecek. Onaylıyor musunuz?"
  end

  defp danger_message(action, _), do: "⚠️ Tehlikeli komut: #{action}. Onaylıyor musunuz?"

  # ── Helpers ─────────────────────────────────────────────

  defp ensure_ets(name) do
    if :ets.whereis(name) == :undefined do
      :ets.new(name, [:set, :public, :named_table])
    end
  end

  @doc "Parse action parameters from raw chat message."
  @spec parse_params(atom(), String.t()) :: map()
  def parse_params(:terrain_modify, raw) do
    biome = extract_biome(raw)
    {x, y} = extract_coords(raw)
    radius = extract_radius(raw)
    %{biome: biome, x: x, y: y, radius: radius}
  end

  def parse_params(:spawn_entity, raw) do
    name = extract_name(raw)
    {x, y} = extract_coords(raw)
    %{name: name, x: x, y: y}
  end

  def parse_params(:config_change, raw) do
    {key, value} = extract_key_value(raw)
    %{key: key, value: value}
  end

  def parse_params(:rule_inject, raw) do
    {key, value} = extract_key_value(raw)
    %{key: key, value: value}
  end

  def parse_params(_, _raw), do: %{}

  # Simple extractors using pattern matching

  defp extract_biome(raw) do
    msg = String.downcase(raw)
    biome_map = %{
      "orman" => :forest, "forest" => :forest,
      "çöl" => :desert, "desert" => :desert,
      "okyanus" => :ocean, "ocean" => :ocean, "deniz" => :ocean,
      "dağ" => :mountain, "mountain" => :mountain,
      "ova" => :plains, "plains" => :plains,
      "bataklık" => :swamp, "swamp" => :swamp,
      "tundra" => :tundra
    }

    Enum.find_value(biome_map, :forest, fn {keyword, biome} ->
      if String.contains?(msg, keyword), do: biome
    end)
  end

  defp extract_coords(raw) do
    case Regex.run(~r/(\d+)\s*[,\s]\s*(\d+)/, raw) do
      [_, x, y] -> {String.to_integer(x), String.to_integer(y)}
      _ -> {Enum.random(5..45), Enum.random(5..45)}
    end
  end

  defp extract_radius(raw) do
    case Regex.run(~r/(?:radius|r|yarıçap)\s*=?\s*(\d+)/i, raw) do
      [_, r] -> min(String.to_integer(r), 10)
      _ -> 2
    end
  end

  defp extract_name(raw) do
    # Try to find quoted name or name after "adlı/named/called"
    case Regex.run(~r/["']([^"']+)["']/, raw) do
      [_, name] -> name
      _ ->
        case Regex.run(~r/(?:adlı|named?|called?|isimli)\s+(\w+)/iu, raw) do
          [_, name] -> name
          _ -> "Ajan-#{:rand.uniform(999)}"
        end
    end
  end

  defp extract_key_value(raw) do
    case Regex.run(~r/(\w+)\s*[=:]\s*(.+)/u, raw) do
      [_, key, value] -> {String.trim(key), parse_value(String.trim(value))}
      _ ->
        tokens = String.split(raw, ~r/\s+/, trim: true)
        key = Enum.at(tokens, -2, "unknown")
        value = Enum.at(tokens, -1, "true")
        {key, parse_value(value)}
    end
  end

  defp parse_value(str) do
    cond do
      str =~ ~r/^\d+$/ -> String.to_integer(str)
      str =~ ~r/^\d+\.\d+$/ -> String.to_float(str)
      str in ["true", "evet", "yes"] -> true
      str in ["false", "hayır", "no"] -> false
      true -> str
    end
  end
end
