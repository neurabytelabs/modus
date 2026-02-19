defmodule Modus.Mind.Creativity do
  @moduledoc """
  Creativity — Agent creative output: stories, naming, invention, art, oral tradition.
  Spinoza: *Ars* — the power to create is the power to exist more fully.

  Agents generate stories from experiences, name places and groups,
  discover recipes through experimentation, create art descriptions,
  and pass stories agent-to-agent with natural mutation.

  All state is ETS-backed for lock-free concurrent reads.
  """

  require Logger

  @stories_table :creativity_stories
  @names_table :creativity_names
  @inventions_table :creativity_inventions
  @art_table :creativity_art
  @oral_table :creativity_oral_tradition

  @max_stories_per_agent 5
  @max_oral_stories 20
  @mutation_chance 0.3
  @story_generation_chance 0.1

  # ── Types ──────────────────────────────────────────────

  @type story :: %{
          id: String.t(),
          author: String.t(),
          title: String.t(),
          text: String.t(),
          tick: integer(),
          based_on: atom(),
          spread_count: integer()
        }

  @type named_thing :: %{
          id: String.t(),
          name: String.t(),
          type: atom(),
          named_by: String.t(),
          tick: integer(),
          target: String.t()
        }

  @type invention :: %{
          id: String.t(),
          name: String.t(),
          ingredients: [atom()],
          discovered_by: String.t(),
          tick: integer(),
          usefulness: float()
        }

  @type art_piece :: %{
          id: String.t(),
          title: String.t(),
          description: String.t(),
          artist: String.t(),
          tick: integer(),
          style: atom()
        }

  # ── Initialization ─────────────────────────────────────

  def init do
    tables = [
      {@stories_table, [:set, :public, :named_table, read_concurrency: true]},
      {@names_table, [:set, :public, :named_table, read_concurrency: true]},
      {@inventions_table, [:set, :public, :named_table, read_concurrency: true]},
      {@art_table, [:set, :public, :named_table, read_concurrency: true]},
      {@oral_table, [:set, :public, :named_table, read_concurrency: true]}
    ]

    Enum.each(tables, fn {name, opts} ->
      if :ets.whereis(name) == :undefined do
        :ets.new(name, opts)
      end
    end)

    :ok
  end

  # ── Story Generation ───────────────────────────────────

  @story_templates %{
    survival: [
      "The day the hunger came, %{agent} learned that even the earth has moods.",
      "When the cold bit deep, %{agent} found warmth in memory alone.",
      "%{agent} once walked three days without food — and discovered patience."
    ],
    discovery: [
      "%{agent} stumbled upon a place where the river sang a different tune.",
      "It was %{agent} who first noticed the herbs growing in the shadow of the great rock.",
      "They say %{agent} found a path no one else had walked."
    ],
    social: [
      "The friendship of %{agent} and a stranger changed everything that season.",
      "%{agent} spoke words that turned enemies into allies.",
      "When %{agent} shared their last meal, the village was born."
    ],
    conflict: [
      "%{agent} stood alone against the storm, and the storm blinked first.",
      "The battle was lost, but %{agent} saved what mattered most — hope.",
      "They fought not for glory, but because %{agent} believed in tomorrow."
    ],
    wonder: [
      "%{agent} looked up one night and understood why the stars don't fall.",
      "In the silence after rain, %{agent} heard the world breathing.",
      "Some say %{agent} spoke to the wind. The wind answered."
    ]
  }

  @doc "Maybe generate a story from an agent's experience. Probabilistic."
  def maybe_generate_story(agent_id, event_type, tick, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    if force or :rand.uniform() < @story_generation_chance do
      generate_story(agent_id, event_type, tick, opts)
    end
  end

  @doc "Generate a story. Uses LLM if available, falls back to templates."
  def generate_story(agent_id, event_type, tick, opts \\ []) do
    use_llm = Keyword.get(opts, :use_llm, false)
    context = Keyword.get(opts, :context, %{})

    {title, text} =
      if use_llm do
        generate_story_llm(agent_id, event_type, context)
      else
        generate_story_template(agent_id, event_type)
      end

    id = random_id()

    story = %{
      id: id,
      author: agent_id,
      title: title,
      text: text,
      tick: tick,
      based_on: event_type,
      spread_count: 0
    }

    store_story(agent_id, story)
    story
  end

  defp generate_story_template(agent_id, event_type) do
    templates = Map.get(@story_templates, event_type, Map.get(@story_templates, :wonder))

    text =
      templates
      |> Enum.random()
      |> String.replace("%{agent}", agent_id)

    title = "The Tale of #{agent_id}"
    {title, text}
  end

  defp generate_story_llm(agent_id, event_type, context) do
    prompt = """
    You are a storyteller in a primitive village. Write a very short story (2-3 sentences)
    about an agent named #{agent_id} who experienced: #{event_type}.
    Context: #{inspect(context)}
    Return ONLY the story text, no titles or labels.
    """

    try do
      config = Modus.Intelligence.LlmProvider.get_config()

      case config.provider do
        :gemini ->
          messages = [%{role: "user", content: prompt}]

          case Modus.Intelligence.GeminiClient.chat_completion_direct(messages, config) do
            {:ok, text} -> {"The Tale of #{agent_id}", String.trim(text)}
            _ -> generate_story_template(agent_id, event_type)
          end

        :ollama ->
          messages = [%{role: "user", content: prompt}]

          case Modus.Intelligence.OllamaClient.chat_completion_direct(messages, config) do
            {:ok, text} -> {"The Tale of #{agent_id}", String.trim(text)}
            _ -> generate_story_template(agent_id, event_type)
          end

        _ ->
          generate_story_template(agent_id, event_type)
      end
    rescue
      _ -> generate_story_template(agent_id, event_type)
    end
  end

  defp store_story(agent_id, story) do
    existing = get_stories(agent_id)
    updated = Enum.take([story | existing], @max_stories_per_agent)
    :ets.insert(@stories_table, {agent_id, updated})
    :ok
  end

  @doc "Get all stories by an agent."
  def get_stories(agent_id) do
    case :ets.lookup(@stories_table, agent_id) do
      [{^agent_id, stories}] -> stories
      [] -> []
    end
  end

  # ── Naming System ──────────────────────────────────────

  @place_name_parts %{
    prefix: ~w(Green Shadow Golden Swift Silent Bright Dark Iron Stone Fire),
    suffix: ~w(hollow vale ridge creek haven point ford glen dale marsh)
  }

  @group_name_parts %{
    prefix: ~w(Iron Dawn Storm Moon Sun Star River Stone Wolf Bear),
    suffix: ~w(clan pack circle guild tribe kin folk band sept lodge)
  }

  @doc "Generate a name for a place."
  def name_place(agent_id, location_key, tick) do
    prefix = Enum.random(@place_name_parts.prefix)
    suffix = Enum.random(@place_name_parts.suffix)
    name = "#{prefix}#{suffix}"

    named = %{
      id: random_id(),
      name: name,
      type: :place,
      named_by: agent_id,
      tick: tick,
      target: inspect(location_key)
    }

    :ets.insert(@names_table, {{:place, location_key}, named})
    named
  end

  @doc "Generate a name for a group."
  def name_group(agent_id, group_id, tick) do
    prefix = Enum.random(@group_name_parts.prefix)
    suffix = Enum.random(@group_name_parts.suffix)
    name = "#{prefix} #{suffix}"

    named = %{
      id: random_id(),
      name: name,
      type: :group,
      named_by: agent_id,
      tick: tick,
      target: to_string(group_id)
    }

    :ets.insert(@names_table, {{:group, group_id}, named})
    named
  end

  @doc "Get the name of a place or group."
  def get_name(type, key) do
    case :ets.lookup(@names_table, {type, key}) do
      [{_, named}] -> named
      [] -> nil
    end
  end

  @doc "List all named things."
  def list_names do
    :ets.tab2list(@names_table)
    |> Enum.map(fn {_key, named} -> named end)
  end

  # ── Invention System ───────────────────────────────────

  @known_ingredients [:wood, :stone, :iron, :herb, :water, :food, :fiber, :clay, :bone, :hide]

  @discovery_recipes %{
    [:herb, :water] => {"Healing Potion", 0.8},
    [:clay, :water] => {"Clay Pot", 0.7},
    [:wood, :fiber] => {"Rope", 0.6},
    [:stone, :wood] => {"Stone Axe", 0.9},
    [:iron, :wood] => {"Iron Blade", 0.95},
    [:hide, :bone] => {"Leather Armor", 0.85},
    [:herb, :herb] => {"Herbal Mix", 0.5},
    [:clay, :fire] => {"Brick", 0.7},
    [:fiber, :fiber] => {"Cloth", 0.6},
    [:bone, :stone] => {"Bone Tool", 0.65}
  }

  @doc "Try to invent something by combining ingredients."
  def try_invention(agent_id, ingredient_a, ingredient_b, tick) do
    combo = Enum.sort([ingredient_a, ingredient_b])

    case Map.get(@discovery_recipes, combo) do
      {name, usefulness} ->
        # Check if already discovered
        existing = get_inventions()
        already = Enum.any?(existing, fn inv -> inv.name == name end)

        if already do
          {:already_known, name}
        else
          invention = %{
            id: random_id(),
            name: name,
            ingredients: combo,
            discovered_by: agent_id,
            tick: tick,
            usefulness: ensure_float(usefulness)
          }

          :ets.insert(@inventions_table, {invention.id, invention})
          {:discovered, invention}
        end

      nil ->
        {:failed, "Nothing useful came from combining #{ingredient_a} and #{ingredient_b}"}
    end
  end

  @doc "Try a random invention from available ingredients."
  def random_invention(agent_id, available_ingredients, tick) do
    usable = Enum.filter(available_ingredients, &(&1 in @known_ingredients))

    if length(usable) >= 2 do
      [a, b] = Enum.take_random(usable, 2)
      try_invention(agent_id, a, b, tick)
    else
      {:failed, "Not enough ingredients to experiment"}
    end
  end

  @doc "Get all inventions."
  def get_inventions do
    :ets.tab2list(@inventions_table)
    |> Enum.map(fn {_id, inv} -> inv end)
  end

  @doc "Get known ingredients list."
  def known_ingredients, do: @known_ingredients

  # ── Art Creation ───────────────────────────────────────

  @art_styles [:abstract, :naturalist, :symbolic, :narrative, :spiritual]

  @art_templates %{
    abstract: [
      "Swirling lines that seem to chase each other across the surface",
      "Bold marks in earth pigments, overlapping in chaotic harmony",
      "A single spiral drawn with confident, unbroken strokes"
    ],
    naturalist: [
      "A careful rendering of the great tree at the village center",
      "Animals gathered at the river, each drawn with loving detail",
      "The hills at sunset, captured in ochre and charcoal"
    ],
    symbolic: [
      "Three circles interlocked — the artist says it means unity",
      "A hand reaching upward, surrounded by stars",
      "The sign of the clan, drawn with precision and pride"
    ],
    narrative: [
      "A scene depicting the great hunt of last autumn",
      "Figures dancing around a fire — a celebration frozen in time",
      "The journey of the founders, told in a sequence of images"
    ],
    spiritual: [
      "Eyes that seem to watch from every angle",
      "The sun and moon embracing at the horizon",
      "Shapes that suggest the invisible forces of the world"
    ]
  }

  @doc "Create an art piece. Adds to culture module if available."
  def create_art(agent_id, tick, opts \\ []) do
    style = Keyword.get(opts, :style, Enum.random(@art_styles))
    templates = Map.get(@art_templates, style, Map.get(@art_templates, :abstract))
    description = Enum.random(templates)

    title = generate_art_title(style)

    art = %{
      id: random_id(),
      title: title,
      description: description,
      artist: agent_id,
      tick: tick,
      style: style
    }

    :ets.insert(@art_table, {art.id, art})

    # Register as cultural artifact
    try do
      Modus.Mind.Culture.maybe_generate_catchphrase(agent_id, :joy, tick)
    rescue
      _ -> :ok
    end

    art
  end

  defp generate_art_title(style) do
    adjectives = ~w(Silent Golden Eternal Broken Luminous Hidden Sacred Wild)

    nouns =
      case style do
        :abstract -> ~w(Dreams Echoes Ripples Fragments Visions)
        :naturalist -> ~w(River Mountain Forest Dawn Meadow)
        :symbolic -> ~w(Unity Bond Circle Path Mark)
        :narrative -> ~w(Journey Tale Chronicle Memory Legend)
        :spiritual -> ~w(Spirit Light Breath Soul Essence)
      end

    "#{Enum.random(adjectives)} #{Enum.random(nouns)}"
  end

  @doc "List all art pieces."
  def list_art do
    :ets.tab2list(@art_table)
    |> Enum.map(fn {_id, art} -> art end)
  end

  @doc "Get art by a specific agent."
  def get_art_by(agent_id) do
    list_art() |> Enum.filter(fn a -> a.artist == agent_id end)
  end

  # ── Oral Tradition ─────────────────────────────────────

  @doc """
  Pass a story from one agent to another. The story mutates slightly
  during transmission, simulating the telephone game of oral tradition.
  """
  def pass_story(from_id, to_id, story_id) do
    from_stories = get_stories(from_id)

    case Enum.find(from_stories, fn s -> s.id == story_id end) do
      nil ->
        {:error, :story_not_found}

      story ->
        mutated = maybe_mutate_story(story, to_id)
        store_story(to_id, mutated)

        # Track in oral tradition ledger
        record = %{
          story_id: story.id,
          original_author: story.author,
          from: from_id,
          to: to_id,
          generation: get_oral_generation(story.id) + 1,
          mutated: mutated.text != story.text
        }

        store_oral_record(record)

        # Update spread count on original
        updated_stories =
          Enum.map(from_stories, fn s ->
            if s.id == story_id, do: %{s | spread_count: s.spread_count + 1}, else: s
          end)

        :ets.insert(@stories_table, {from_id, updated_stories})

        {:ok, mutated}
    end
  end

  @doc "Pass a random story between agents during conversation."
  def maybe_share_story(from_id, to_id) do
    from_stories = get_stories(from_id)

    if from_stories != [] and :rand.uniform() < 0.2 do
      story = Enum.random(from_stories)
      pass_story(from_id, to_id, story.id)
    else
      :no_story
    end
  end

  defp maybe_mutate_story(story, new_holder) do
    if :rand.uniform() < @mutation_chance do
      mutated_text = mutate_text(story.text)
      new_id = random_id()

      %{
        story
        | id: new_id,
          text: mutated_text,
          author: "#{new_holder} (retelling #{story.author})"
      }
    else
      new_id = random_id()
      %{story | id: new_id}
    end
  end

  defp mutate_text(text) do
    mutations = [
      # Add emphasis
      fn t -> String.replace(t, ".", "!") end,
      # Exaggerate
      fn t -> String.replace(t, "once", "many times") end,
      fn t -> String.replace(t, "a ", "a great ") end,
      # Simplify
      fn t ->
        words = String.split(t)

        if length(words) > 5 do
          words |> Enum.take(length(words) - 2) |> Enum.join(" ") |> Kernel.<>("...")
        else
          t
        end
      end,
      # Add attribution
      fn t -> "As the elders say: " <> t end,
      # Swap detail
      fn t -> String.replace(t, "three", "seven") end
    ]

    mutation = Enum.random(mutations)
    result = mutation.(text)

    if result != text and String.length(result) < 200 do
      result
    else
      text <> " — or so they say."
    end
  end

  defp store_oral_record(record) do
    existing = get_oral_records()
    updated = Enum.take([record | existing], @max_oral_stories)
    :ets.insert(@oral_table, {:records, updated})
  end

  defp get_oral_records do
    case :ets.lookup(@oral_table, :records) do
      [{:records, records}] -> records
      [] -> []
    end
  end

  defp get_oral_generation(story_id) do
    get_oral_records()
    |> Enum.filter(fn r -> r.story_id == story_id end)
    |> Enum.map(fn r -> r.generation end)
    |> Enum.max(fn -> 0 end)
  end

  @doc "Get the oral tradition history."
  def oral_tradition_history do
    get_oral_records()
  end

  # ── Serialization for UI ───────────────────────────────

  @doc "Serialize an agent's creative output for display."
  def serialize(agent_id) do
    %{
      stories:
        get_stories(agent_id)
        |> Enum.map(fn s ->
          %{
            id: s.id,
            title: s.title,
            text: s.text,
            based_on: to_string(s.based_on),
            tick: s.tick,
            spread_count: s.spread_count
          }
        end),
      art:
        get_art_by(agent_id)
        |> Enum.map(fn a ->
          %{
            id: a.id,
            title: a.title,
            description: a.description,
            style: to_string(a.style),
            tick: a.tick
          }
        end),
      names:
        list_names()
        |> Enum.filter(fn n -> n.named_by == agent_id end)
        |> Enum.map(fn n ->
          %{name: n.name, type: to_string(n.type), target: n.target}
        end),
      inventions:
        get_inventions()
        |> Enum.filter(fn i -> i.discovered_by == agent_id end)
        |> Enum.map(fn i ->
          %{
            name: i.name,
            ingredients: Enum.map(i.ingredients, &to_string/1),
            usefulness: i.usefulness
          }
        end)
    }
  end

  # ── Helpers ────────────────────────────────────────────

  defp random_id do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
