defmodule Modus.Mind.Culture do
  @moduledoc """
  Culture — Emergent cultural evolution for agents.
  Spinoza: *Consuetudo* — habits and customs that arise from shared experience.

  Tracks catchphrases born from experience, traditions from seasonal events,
  and cultural drift across generations. Culture spreads via conversation
  and proximity, mutates over time, and can be lost if not reinforced.
  """

  @table :agent_culture
  @traditions_table :world_traditions
  @max_catchphrases 5
  @spread_chance 0.3
  @drift_chance 0.05
  @decay_amount 0.01

  # ── Types ──────────────────────────────────────────────

  @type catchphrase :: %{
          text: String.t(),
          origin_agent: String.t(),
          origin_tick: integer(),
          strength: float(),
          context: atom()
        }

  @type tradition :: %{
          id: String.t(),
          name: String.t(),
          type: atom(),
          season: atom(),
          description: String.t(),
          participants: [String.t()],
          created_tick: integer(),
          last_performed: integer(),
          strength: float()
        }

  # ── Initialization ─────────────────────────────────────

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    if :ets.whereis(@traditions_table) == :undefined do
      :ets.new(@traditions_table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  # ── Catchphrases ───────────────────────────────────────

  @catchphrase_templates %{
    hunger_critical: [
      "My stomach speaks louder than my words!",
      "Food first, philosophy later.",
      "The belly knows no patience.",
      "Empty stomachs make sharp tongues."
    ],
    action_success: [
      "Fortune favors the persistent!",
      "Another day, another victory!",
      "Hard work is its own reward.",
      "We build, we thrive!"
    ],
    social_positive: [
      "Together we are the substance!",
      "A friend found is a world expanded.",
      "No soul walks alone by nature.",
      "Connection is the truest wealth."
    ],
    rest: [
      "Even the sun must set.",
      "Rest is the seed of tomorrow's strength.",
      "Stillness speaks its own wisdom."
    ],
    action_failure: [
      "We fall, we learn, we rise.",
      "The world tests those it favors.",
      "Not every path leads forward."
    ],
    joy: [
      "What a time to be alive!",
      "Joy shared is joy doubled!",
      "The world smiles with us today."
    ],
    sadness: [
      "Even this shall pass...",
      "Tears water the roots of wisdom.",
      "The heart remembers what the mind forgets."
    ],
    fear: [
      "Courage is fear that has said its prayers.",
      "We face the dark together.",
      "What we fear, we can overcome."
    ]
  }

  @doc "Generate a catchphrase from an agent's experience. Called on significant events."
  def maybe_generate_catchphrase(agent_id, event_type, tick) do
    # Only generate with some probability
    if :rand.uniform() < 0.15 do
      # Use language-specific catchphrases if available
      lang =
        try do
          Modus.I18n.current_language()
        catch
          _, _ -> "en"
        end

      lang_pool = Modus.I18n.catchphrases(lang)

      templates =
        Map.get(lang_pool, event_type) || Map.get(@catchphrase_templates, event_type, [])

      if templates != [] do
        text = Enum.random(templates)
        # Add slight personality-based mutation
        catchphrase = %{
          text: text,
          origin_agent: agent_id,
          origin_tick: tick,
          strength: 1.0,
          context: event_type
        }

        add_catchphrase(agent_id, catchphrase)
        catchphrase
      end
    end
  end

  @doc "Add a catchphrase to an agent's cultural repertoire."
  def add_catchphrase(agent_id, catchphrase) do
    existing = get_catchphrases(agent_id)
    # Don't add duplicates
    unless Enum.any?(existing, fn c -> c.text == catchphrase.text end) do
      updated = Enum.take([catchphrase | existing], @max_catchphrases)
      :ets.insert(@table, {agent_id, updated})
    end

    :ok
  end

  @doc "Get an agent's catchphrases."
  def get_catchphrases(agent_id) do
    case :ets.lookup(@table, agent_id) do
      [{^agent_id, phrases}] -> phrases
      [] -> []
    end
  end

  @doc "Get a random catchphrase for use in conversation. Returns nil if none."
  def random_catchphrase(agent_id) do
    phrases = get_catchphrases(agent_id)

    if phrases != [] do
      # Weighted by strength
      weighted =
        Enum.flat_map(phrases, fn p ->
          count = max(round(p.strength * 10), 1)
          List.duplicate(p, count)
        end)

      Enum.random(weighted)
    end
  end

  @doc """
  Spread culture during conversation.
  When two agents talk, catchphrases may spread from one to the other.
  """
  def spread_culture(agent_a_id, agent_b_id, _tick) do
    spread_catchphrases(agent_a_id, agent_b_id)
    spread_catchphrases(agent_b_id, agent_a_id)
  end

  defp spread_catchphrases(from_id, to_id) do
    from_phrases = get_catchphrases(from_id)
    to_phrases = get_catchphrases(to_id)

    Enum.each(from_phrases, fn phrase ->
      already_has = Enum.any?(to_phrases, fn p -> p.text == phrase.text end)

      if not already_has and :rand.uniform() < @spread_chance * phrase.strength do
        # Spread with reduced strength
        spread_phrase = %{phrase | strength: phrase.strength * 0.7}
        add_catchphrase(to_id, spread_phrase)
      end
    end)
  end

  @doc "Apply cultural drift — phrases mutate slightly over time."
  def drift(agent_id) do
    phrases = get_catchphrases(agent_id)

    if phrases != [] and :rand.uniform() < @drift_chance do
      idx = :rand.uniform(length(phrases)) - 1
      phrase = Enum.at(phrases, idx)
      mutated = mutate_phrase(phrase)
      updated = List.replace_at(phrases, idx, mutated)
      :ets.insert(@table, {agent_id, updated})
    end
  end

  defp mutate_phrase(phrase) do
    mutations = [
      fn t -> String.replace(t, "!", "!!") end,
      fn t -> String.replace(t, "we", "all of us") end,
      fn t -> "As they say: " <> t end,
      fn t -> String.replace(t, ".", "...") end,
      fn t -> String.upcase(String.first(t)) <> String.slice(t, 1..-1//1) end
    ]

    mutation = Enum.random(mutations)
    new_text = mutation.(phrase.text)
    # Only mutate if result is different and not too long
    if new_text != phrase.text and String.length(new_text) < 80 do
      %{phrase | text: new_text}
    else
      phrase
    end
  end

  # ── Traditions ─────────────────────────────────────────

  @tradition_templates [
    %{
      name: "Harvest Festival",
      type: :harvest,
      season: :autumn,
      description: "Agents gather to celebrate the autumn harvest with feasting and song."
    },
    %{
      name: "Mourning Circle",
      type: :mourning,
      season: :any,
      description: "When an agent dies, nearby agents gather in a circle of remembrance."
    },
    %{
      name: "Dawn Greeting",
      type: :greeting,
      season: :any,
      description: "Agents greet each other at dawn with a shared phrase or gesture."
    },
    %{
      name: "Winter Vigil",
      type: :survival,
      season: :winter,
      description: "Agents huddle together during the coldest nights, sharing warmth and stories."
    },
    %{
      name: "Spring Awakening",
      type: :renewal,
      season: :spring,
      description: "A celebration of new life and new beginnings as the world blooms."
    },
    %{
      name: "Stargazing Rite",
      type: :wonder,
      season: :summer,
      description: "On summer nights, agents look up and share stories about the stars."
    }
  ]

  @doc "Check if a tradition should trigger based on current conditions."
  def check_traditions(tick, season, event_type \\ nil) do
    traditions = list_traditions()

    # Auto-create traditions from templates if none exist
    traditions =
      if traditions == [] and tick > 500 do
        seed_traditions(tick)
        list_traditions()
      else
        traditions
      end

    # Check which traditions should fire
    Enum.filter(traditions, fn t ->
      season_match = t.season == :any or t.season == season
      cooldown_ok = tick - t.last_performed > 300

      event_match =
        case {t.type, event_type} do
          {:mourning, :death} -> true
          {:harvest, _} -> season == :autumn
          # Checked every dawn
          {:greeting, _} -> true
          {:survival, _} -> season == :winter
          {:renewal, _} -> season == :spring
          {:wonder, _} -> season == :summer
          _ -> false
        end

      season_match and cooldown_ok and event_match
    end)
  end

  @doc "Perform a tradition — record it and return event data."
  def perform_tradition(tradition_id, participant_ids, tick) do
    case get_tradition(tradition_id) do
      nil ->
        {:error, :not_found}

      tradition ->
        updated = %{
          tradition
          | last_performed: tick,
            participants: participant_ids,
            strength: min(tradition.strength + 0.05, 1.0)
        }

        :ets.insert(@traditions_table, {tradition_id, updated})

        # Boost social bonds between participants
        pairs = for a <- participant_ids, b <- participant_ids, a < b, do: {a, b}

        Enum.each(pairs, fn {a, b} ->
          Modus.Mind.Cerebro.SocialNetwork.update_relationship(a, b, :conversation_joy)
        end)

        {:ok, updated}
    end
  end

  @doc "Seed initial traditions from templates."
  def seed_traditions(tick) do
    Enum.each(@tradition_templates, fn template ->
      id = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

      tradition = %{
        id: id,
        name: template.name,
        type: template.type,
        season: template.season,
        description: template.description,
        participants: [],
        created_tick: tick,
        last_performed: 0,
        strength: 0.5
      }

      :ets.insert(@traditions_table, {id, tradition})
    end)
  end

  @doc "Get a specific tradition."
  def get_tradition(id) do
    case :ets.lookup(@traditions_table, id) do
      [{^id, t}] -> t
      [] -> nil
    end
  end

  @doc "List all traditions."
  def list_traditions do
    :ets.tab2list(@traditions_table)
    |> Enum.map(fn {_id, t} -> t end)
  end

  # ── Decay & Maintenance ────────────────────────────────

  @doc "Decay all cultural elements. Called periodically."
  def decay_all do
    # Decay catchphrases
    :ets.tab2list(@table)
    |> Enum.each(fn {agent_id, phrases} ->
      updated =
        phrases
        |> Enum.map(fn p -> %{p | strength: max(p.strength - @decay_amount, 0.0)} end)
        |> Enum.reject(fn p -> p.strength < 0.05 end)

      if updated == [] do
        :ets.delete(@table, agent_id)
      else
        :ets.insert(@table, {agent_id, updated})
      end
    end)

    # Decay traditions
    :ets.tab2list(@traditions_table)
    |> Enum.each(fn {id, t} ->
      new_strength = max(t.strength - @decay_amount * 0.5, 0.0)

      if new_strength < 0.05 do
        :ets.delete(@traditions_table, id)
      else
        :ets.insert(@traditions_table, {id, %{t | strength: new_strength}})
      end
    end)

    :ok
  end

  # ── Generational Transfer ──────────────────────────────

  @doc "Transfer culture from parent/mentor to child agent."
  def inherit_culture(parent_id, child_id) do
    parent_phrases = get_catchphrases(parent_id)

    # Child inherits strongest phrases with some mutation
    parent_phrases
    |> Enum.filter(fn p -> p.strength > 0.3 end)
    |> Enum.take(3)
    |> Enum.each(fn phrase ->
      inherited = %{phrase | strength: phrase.strength * 0.6}
      # Small chance of mutation during inheritance
      final = if :rand.uniform() < 0.2, do: mutate_phrase(inherited), else: inherited
      add_catchphrase(child_id, final)
    end)
  end

  # ── Serialization for UI ───────────────────────────────

  @doc "Serialize an agent's culture for the detail panel."
  def serialize(agent_id) do
    phrases = get_catchphrases(agent_id)

    %{
      catchphrases:
        Enum.map(phrases, fn p ->
          %{
            text: p.text,
            strength: Float.round(p.strength, 2),
            context: to_string(p.context),
            origin_agent: p.origin_agent
          }
        end),
      traditions:
        list_traditions()
        |> Enum.map(fn t ->
          %{
            id: t.id,
            name: t.name,
            type: to_string(t.type),
            season: to_string(t.season),
            description: t.description,
            strength: Float.round(t.strength, 2),
            participant_count: length(t.participants)
          }
        end)
    }
  end

  @doc "Get a catchphrase string for chat injection."
  def chat_catchphrase(agent_id) do
    case random_catchphrase(agent_id) do
      nil -> nil
      phrase -> phrase.text
    end
  end
end
