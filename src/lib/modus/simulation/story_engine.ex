defmodule Modus.Simulation.StoryEngine do
  @moduledoc """
  StoryEngine — Automatic narrative generation from simulation events.

  Watches the EventLog and weaves events into stories.
  Maintains a chronicle of the world's history as structured entries.

  ## Spinoza: *Potentia* — The power of narrative to reveal being.
  """
  use GenServer

  alias Modus.Simulation.EventLog

  @max_chronicle 500
  # story_interval: 50 ticks between story generation

  defstruct chronicle: [],
            last_story_tick: 0,
            population_history: [],
            notable_events: []

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc "Get the full chronicle (list of story entries)."
  @spec get_chronicle() :: [map()]
  def get_chronicle do
    GenServer.call(__MODULE__, :get_chronicle)
  end

  @doc "Get the timeline (notable events with narrative descriptions)."
  @spec get_timeline(keyword()) :: [map()]
  def get_timeline(opts \\ []) do
    GenServer.call(__MODULE__, {:get_timeline, opts})
  end

  @doc "Export chronicle as markdown."
  @spec export_markdown() :: String.t()
  def export_markdown do
    GenServer.call(__MODULE__, :export_markdown)
  end

  @doc "Record a population snapshot."
  @spec record_population(integer(), integer()) :: :ok
  def record_population(tick, count) do
    GenServer.cast(__MODULE__, {:record_population, tick, count})
  end

  @doc "Get population history for graphing."
  @spec population_history() :: [{integer(), integer()}]
  def population_history do
    GenServer.call(__MODULE__, :population_history)
  end

  @doc "Process an event and potentially generate narrative."
  @spec process_event(map()) :: :ok
  def process_event(event) do
    GenServer.cast(__MODULE__, {:process_event, event})
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(state) do
    EventLog.subscribe()
    {:ok, state}
  end

  @impl true
  def handle_cast({:process_event, event}, state) do
    entry = narrate_event(event)
    notable = is_notable?(event)

    chronicle = Enum.take([entry | state.chronicle], @max_chronicle)

    notable_events =
      if notable do
        Enum.take([entry | state.notable_events], 200)
      else
        state.notable_events
      end

    {:noreply, %{state | chronicle: chronicle, notable_events: notable_events}}
  end

  @impl true
  def handle_cast({:record_population, tick, count}, state) do
    # Keep one entry per 10 ticks to avoid bloat
    history = [{tick, count} | state.population_history]
    |> Enum.take(1000)
    {:noreply, %{state | population_history: history}}
  end

  @impl true
  def handle_call(:get_chronicle, _from, state) do
    {:reply, Enum.reverse(state.chronicle), state}
  end

  @impl true
  def handle_call({:get_timeline, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 50)
    timeline = state.notable_events
    |> Enum.take(limit)
    |> Enum.reverse()
    {:reply, timeline, state}
  end

  @impl true
  def handle_call(:export_markdown, _from, state) do
    md = build_markdown(state)
    {:reply, md, state}
  end

  @impl true
  def handle_call(:population_history, _from, state) do
    {:reply, Enum.reverse(state.population_history), state}
  end

  @impl true
  def handle_info({:event, event}, state) do
    # Auto-process events from PubSub
    entry = narrate_event(event)
    notable = is_notable?(event)

    chronicle = Enum.take([entry | state.chronicle], @max_chronicle)

    notable_events =
      if notable do
        Enum.take([entry | state.notable_events], 200)
      else
        state.notable_events
      end

    # Broadcast notable events as toast notifications
    if notable do
      Phoenix.PubSub.broadcast(Modus.PubSub, "story", {:toast, entry})
    end

    {:noreply, %{state | chronicle: chronicle, notable_events: notable_events}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Narrative Generation ────────────────────────────────

  defp narrate_event(event) do
    lang = try do Modus.I18n.current_language() catch _, _ -> "en" end
    narrative = case event.type do
      :birth ->
        name = event.data[:name] || "a new soul"
        narrate_birth(lang, name)

      :death ->
        name = event.data[:name] || "an agent"
        cause = event.data[:cause] || "the weight of existence"
        narrate_death(lang, name, cause)

      :conversation ->
        agents = event.agents
        cond do
          length(agents) >= 2 ->
            narrate_conversation(lang)
          true ->
            narrate_conversation(lang)
        end

      :conflict ->
        narrate_conflict(lang)

      :resource_gathered ->
        name = event.data[:name] || "Someone"
        "#{name} gathered resources, strengthening their hold on existence."

      :disaster ->
        victim = event.data[:victim] || "someone"
        "A natural disaster struck! #{victim} was caught in the upheaval."

      :migration ->
        "A stranger arrived from beyond the borders, seeking a new life."

      :resource ->
        "The land yielded bounty — resources appeared across the world."

      :trade ->
        "A trade was completed, resources flowing between agents."

      :building_upgrade ->
        name = event.data[:name] || "Someone"
        to = event.data[:to] || "a grander dwelling"
        level = event.data[:level] || 2
        "#{name} upgraded their home to #{to} (level #{level}) — a testament to their perseverance."

      :neighborhood_formed ->
        hood_name = event.data[:name] || "a new quarter"
        size = event.data[:size] || 3
        "#{hood_name} emerged — #{size} buildings clustered together, forming a neighborhood. Community takes root."

      :season_change ->
        season = event.data[:season] || :spring
        year = event.data[:year] || 1
        toast = Modus.I18n.season_toast(lang, season)
        "Year #{year} — #{toast}"

      :world_event ->
        evt_type = event.data[:type] || :unknown
        severity = event.data[:severity] || 1
        severity_word = case severity do
          1 -> "minor"
          2 -> "severe"
          3 -> "catastrophic"
          _ -> "mysterious"
        end
        case evt_type do
          :storm -> "A #{severity_word} storm swept across the land, darkening the skies."
          :earthquake -> "The earth trembled — a #{severity_word} earthquake shook the foundations of existence."
          :meteor_shower -> "Meteors streaked across the sky — a #{severity_word} celestial display."
          :plague -> "A #{severity_word} plague spread through the population, weakening all in its path."
          :golden_age -> "A golden age dawned — prosperity and joy filled the world."
          :flood -> "Waters rose — a #{severity_word} flood consumed the lowlands."
          :fire -> "Flames erupted — a #{severity_word} fire scorched the earth."
          _ -> "A #{severity_word} world event reshapes the landscape."
        end

      _ ->
        "Something stirred in the world (#{event.type})."
    end

    %{
      tick: event.tick,
      type: event.type,
      narrative: narrative,
      agents: event.agents,
      emoji: event_emoji(event.type),
      timestamp: event.timestamp || DateTime.utc_now()
    }
  end

  defp is_notable?(event) do
    event.type in [:birth, :death, :disaster, :migration, :conflict, :trade, :world_event, :season_change]
  end

  defp event_emoji(:birth), do: "👶"
  defp event_emoji(:death), do: "💀"
  defp event_emoji(:conversation), do: "💬"
  defp event_emoji(:conflict), do: "⚔️"
  defp event_emoji(:resource_gathered), do: "🌾"
  defp event_emoji(:disaster), do: "🌋"
  defp event_emoji(:migration), do: "🚶"
  defp event_emoji(:resource), do: "🎁"
  defp event_emoji(:trade), do: "🤝"
  defp event_emoji(:building_upgrade), do: "⬆️"
  defp event_emoji(:neighborhood_formed), do: "🏘️"
  defp event_emoji(:season_change), do: "🍃"
  defp event_emoji(:world_event), do: "🌍"
  defp event_emoji(_), do: "⚡"

  # ── Markdown Export ─────────────────────────────────────

  defp build_markdown(state) do
    entries = Enum.reverse(state.chronicle)

    header = """
    # MODUS World Chronicle
    ## "Deus sive Natura" — God, or Nature

    > *The order and connection of ideas is the same as the order and connection of things.* — Spinoza

    ---

    ### Population History
    #{format_population_summary(state.population_history)}

    ---

    ### Chronicle of Events

    """

    body = entries
    |> Enum.map(fn entry ->
      tick_str = String.pad_leading(to_string(entry.tick), 6, " ")
      "**[Tick #{tick_str}]** #{entry.emoji} #{entry.narrative}"
    end)
    |> Enum.join("\n\n")

    footer = """

    ---

    *Generated by MODUS — Where Spinoza Meets Silicon*
    *#{DateTime.utc_now() |> DateTime.to_string()}*
    """

    header <> body <> footer
  end

  # ── Language-Aware Narrative Helpers ─────────────────────

  defp narrate_birth("tr", name), do: "#{name} dünyaya geldi, yeni bir conatus kıvılcımı."
  defp narrate_birth("de", name), do: "#{name} wurde in die Welt geboren, ein neuer Funke des Conatus."
  defp narrate_birth("fr", name), do: "#{name} est né(e) dans le monde, une nouvelle étincelle de conatus."
  defp narrate_birth("es", name), do: "#{name} nació en el mundo, una nueva chispa de conatus."
  defp narrate_birth("ja", name), do: "#{name}が世界に生まれた。新たなコナトゥスの火花。"
  defp narrate_birth(_, name), do: "#{name} was born into the world, a fresh spark of conatus."

  defp narrate_death("tr", name, cause), do: "#{name} hayatını kaybetti — #{cause}. Işığı dünyadan silindi."
  defp narrate_death("de", name, cause), do: "#{name} ist gestorben — #{cause}. Ihr Licht erlischt."
  defp narrate_death("fr", name, cause), do: "#{name} a péri — #{cause}. Sa lumière s'éteint."
  defp narrate_death("es", name, cause), do: "#{name} pereció — #{cause}. Su luz se apaga."
  defp narrate_death("ja", name, cause), do: "#{name}が逝った — #{cause}。その光は消えた。"
  defp narrate_death(_, name, cause), do: "#{name} perished — #{cause}. Their light fades from the world."

  defp narrate_conversation("tr"), do: "İki ruh karşılaştı ve sözlerini paylaştı."
  defp narrate_conversation("de"), do: "Zwei Seelen kreuzten ihre Wege und tauschten Worte aus."
  defp narrate_conversation("fr"), do: "Deux âmes se sont croisées et ont partagé des mots."
  defp narrate_conversation("es"), do: "Dos almas se cruzaron y compartieron palabras."
  defp narrate_conversation("ja"), do: "二つの魂が出会い、言葉を交わした。"
  defp narrate_conversation(_), do: "Two souls crossed paths and shared words, weaving the social fabric tighter."

  defp narrate_conflict("tr"), do: "Çatışma patlak verdi — koruma ve yıkım arasındaki ebedi gerilim."
  defp narrate_conflict("de"), do: "Ein Konflikt brach aus — die ewige Spannung zwischen Bewahrung und Zerstörung."
  defp narrate_conflict("fr"), do: "Un conflit a éclaté — la tension éternelle entre préservation et destruction."
  defp narrate_conflict("es"), do: "Estalló un conflicto — la eterna tensión entre preservación y destrucción."
  defp narrate_conflict("ja"), do: "争いが勃発した — 保存と破壊の永遠の緊張。"
  defp narrate_conflict(_), do: "Conflict erupted — the eternal tension between preservation and destruction."

  defp format_population_summary(history) do
    case history do
      [] -> "No population data recorded yet."
      _ ->
        reversed = Enum.reverse(history)
        {first_tick, first_pop} = List.first(reversed)
        {last_tick, last_pop} = List.last(reversed)
        max_pop = reversed |> Enum.map(&elem(&1, 1)) |> Enum.max()
        min_pop = reversed |> Enum.map(&elem(&1, 1)) |> Enum.min()

        """
        - **Start:** #{first_pop} agents (tick #{first_tick})
        - **Current:** #{last_pop} agents (tick #{last_tick})
        - **Peak:** #{max_pop} agents
        - **Lowest:** #{min_pop} agents
        """
    end
  end
end
