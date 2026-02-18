defmodule Modus.Mind.CreativityTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Creativity

  setup do
    Creativity.init()
    agent_id = "creative_agent_#{:rand.uniform(100_000)}"
    {:ok, agent_id: agent_id}
  end

  # ── Story Generation ───────────────────────────────────

  describe "story generation" do
    test "generate_story creates a story from template", %{agent_id: agent_id} do
      story = Creativity.generate_story(agent_id, :survival, 100)
      assert story.author == agent_id
      assert story.tick == 100
      assert story.based_on == :survival
      assert is_binary(story.title)
      assert is_binary(story.text)
      assert String.contains?(story.text, agent_id)
      assert story.spread_count == 0
    end

    test "stories are stored and retrievable", %{agent_id: agent_id} do
      Creativity.generate_story(agent_id, :discovery, 200)
      Creativity.generate_story(agent_id, :social, 201)

      stories = Creativity.get_stories(agent_id)
      assert length(stories) == 2
    end

    test "max stories per agent is enforced", %{agent_id: agent_id} do
      for i <- 1..10 do
        Creativity.generate_story(agent_id, :wonder, i * 100)
      end

      stories = Creativity.get_stories(agent_id)
      assert length(stories) <= 5
    end

    test "maybe_generate_story with force option", %{agent_id: agent_id} do
      result = Creativity.maybe_generate_story(agent_id, :conflict, 50, force: true)
      assert result != nil
      assert result.based_on == :conflict
    end

    test "get_stories returns empty for unknown agent" do
      assert Creativity.get_stories("nobody") == []
    end
  end

  # ── Naming System ──────────────────────────────────────

  describe "naming system" do
    test "name_place generates a place name", %{agent_id: agent_id} do
      named = Creativity.name_place(agent_id, {5, 10}, 300)
      assert is_binary(named.name)
      assert named.type == :place
      assert named.named_by == agent_id
      assert named.tick == 300
    end

    test "name_group generates a group name", %{agent_id: agent_id} do
      named = Creativity.name_group(agent_id, "group_alpha", 400)
      assert is_binary(named.name)
      assert named.type == :group
      assert String.contains?(named.name, " ")
    end

    test "get_name retrieves named places", %{agent_id: agent_id} do
      Creativity.name_place(agent_id, :river_bend, 500)
      result = Creativity.get_name(:place, :river_bend)
      assert result != nil
      assert result.named_by == agent_id
    end

    test "get_name returns nil for unnamed things" do
      assert Creativity.get_name(:place, :nonexistent) == nil
    end

    test "list_names returns all names", %{agent_id: agent_id} do
      Creativity.name_place(agent_id, :loc_a, 100)
      Creativity.name_group(agent_id, :grp_b, 101)
      names = Creativity.list_names()
      agent_names = Enum.filter(names, fn n -> n.named_by == agent_id end)
      assert length(agent_names) >= 2
    end
  end

  # ── Invention System ───────────────────────────────────

  describe "invention system" do
    test "try_invention discovers a known recipe", %{agent_id: agent_id} do
      result = Creativity.try_invention(agent_id, :herb, :water, 600)
      assert {:discovered, invention} = result
      assert invention.name == "Healing Potion"
      assert invention.discovered_by == agent_id
      assert is_float(invention.usefulness)
    end

    test "try_invention fails for unknown combo", %{agent_id: agent_id} do
      result = Creativity.try_invention(agent_id, :wood, :water, 700)
      assert {:failed, _msg} = result
    end

    test "try_invention reports already known", %{agent_id: agent_id} do
      Creativity.try_invention(agent_id, :clay, :water, 800)
      result = Creativity.try_invention(agent_id, :clay, :water, 801)
      assert {:already_known, "Clay Pot"} = result
    end

    test "random_invention with available ingredients", %{agent_id: agent_id} do
      result = Creativity.random_invention(agent_id, [:herb, :water, :stone, :wood], 900)
      assert elem(result, 0) in [:discovered, :already_known, :failed]
    end

    test "random_invention fails with insufficient ingredients", %{agent_id: agent_id} do
      assert {:failed, _} = Creativity.random_invention(agent_id, [:unknown], 1000)
    end

    test "get_inventions lists all discoveries", %{agent_id: agent_id} do
      Creativity.try_invention(agent_id, :stone, :wood, 1100)
      inventions = Creativity.get_inventions()
      assert length(inventions) >= 1
    end

    test "known_ingredients returns ingredient list" do
      ingredients = Creativity.known_ingredients()
      assert :wood in ingredients
      assert :herb in ingredients
      assert length(ingredients) == 10
    end
  end

  # ── Art Creation ───────────────────────────────────────

  describe "art creation" do
    test "create_art generates an art piece", %{agent_id: agent_id} do
      art = Creativity.create_art(agent_id, 1200)
      assert is_binary(art.title)
      assert is_binary(art.description)
      assert art.artist == agent_id
      assert art.style in [:abstract, :naturalist, :symbolic, :narrative, :spiritual]
    end

    test "create_art with specific style", %{agent_id: agent_id} do
      art = Creativity.create_art(agent_id, 1300, style: :symbolic)
      assert art.style == :symbolic
    end

    test "list_art returns all art", %{agent_id: agent_id} do
      Creativity.create_art(agent_id, 1400)
      arts = Creativity.list_art()
      assert length(arts) >= 1
    end

    test "get_art_by filters by artist", %{agent_id: agent_id} do
      Creativity.create_art(agent_id, 1500)
      Creativity.create_art("other_artist", 1501)
      mine = Creativity.get_art_by(agent_id)
      assert Enum.all?(mine, fn a -> a.artist == agent_id end)
    end
  end

  # ── Oral Tradition ─────────────────────────────────────

  describe "oral tradition" do
    test "pass_story transfers a story between agents", %{agent_id: agent_id} do
      story = Creativity.generate_story(agent_id, :wonder, 1600)
      to_id = "listener_#{:rand.uniform(100_000)}"

      assert {:ok, received} = Creativity.pass_story(agent_id, to_id, story.id)
      assert is_binary(received.text)

      to_stories = Creativity.get_stories(to_id)
      assert length(to_stories) == 1
    end

    test "pass_story increments spread count", %{agent_id: agent_id} do
      story = Creativity.generate_story(agent_id, :survival, 1700)
      to_id = "listener2_#{:rand.uniform(100_000)}"
      Creativity.pass_story(agent_id, to_id, story.id)

      updated = Creativity.get_stories(agent_id)
      original = Enum.find(updated, fn s -> s.id == story.id end)
      assert original.spread_count == 1
    end

    test "pass_story fails for nonexistent story", %{agent_id: agent_id} do
      assert {:error, :story_not_found} =
               Creativity.pass_story(agent_id, "someone", "fake_id")
    end

    test "oral_tradition_history tracks transmissions", %{agent_id: agent_id} do
      story = Creativity.generate_story(agent_id, :social, 1800)
      to_id = "listener3_#{:rand.uniform(100_000)}"
      Creativity.pass_story(agent_id, to_id, story.id)

      history = Creativity.oral_tradition_history()
      assert length(history) >= 1
      record = hd(history)
      assert record.from == agent_id
      assert record.to == to_id
    end

    test "maybe_share_story returns :no_story when no stories", %{agent_id: agent_id} do
      result = Creativity.maybe_share_story(agent_id, "someone")
      assert result == :no_story
    end
  end

  # ── Serialization ──────────────────────────────────────

  describe "serialize" do
    test "serialize returns structured data", %{agent_id: agent_id} do
      Creativity.generate_story(agent_id, :discovery, 2000)
      Creativity.create_art(agent_id, 2001)
      Creativity.name_place(agent_id, :my_spot, 2002)
      Creativity.try_invention(agent_id, :wood, :fiber, 2003)

      data = Creativity.serialize(agent_id)
      assert is_list(data.stories)
      assert is_list(data.art)
      assert is_list(data.names)
      assert is_list(data.inventions)
      assert length(data.stories) >= 1
      assert length(data.art) >= 1
    end
  end
end
