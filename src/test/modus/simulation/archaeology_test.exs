defmodule Modus.Simulation.ArchaeologyTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.Archaeology

  setup do
    # Temiz ETS tabloları
    for table <- [:archaeology_ruins, :archaeology_artifacts, :archaeology_museums] do
      if :ets.whereis(table) != :undefined, do: :ets.delete_all_objects(table)
    end

    Archaeology.init_table()
    :ok
  end

  describe "init_table/0" do
    test "ETS tabloları oluşturulur" do
      assert :ets.whereis(:archaeology_ruins) != :undefined
      assert :ets.whereis(:archaeology_artifacts) != :undefined
      assert :ets.whereis(:archaeology_museums) != :undefined
    end
  end

  describe "create_ancient_ruin/3" do
    test "antik harabe oluşturur" do
      ruin = Archaeology.create_ancient_ruin(:temple, {10, 20}, 1000)
      assert ruin.type == :temple
      assert ruin.position == {10, 20}
      assert ruin.discovered == false
      assert is_float(ruin.decay_level)
      assert ruin.decay_level >= 0.5
    end

    test "artefaktlar ile birlikte oluşur" do
      ruin = Archaeology.create_ancient_ruin(:fortress, {5, 5}, 500)
      assert length(ruin.artifacts) >= 1
      assert length(ruin.artifacts) <= 5
    end

    test "tüm harabe türleri desteklenir" do
      for type <- [:temple, :fortress, :village, :monument] do
        ruin = Archaeology.create_ancient_ruin(type, {0, 0}, 100)
        assert ruin.type == type
      end
    end
  end

  describe "get_all_ruins/0" do
    test "tüm harabeler döner" do
      Archaeology.create_ancient_ruin(:temple, {1, 1}, 100)
      Archaeology.create_ancient_ruin(:fortress, {2, 2}, 100)
      assert length(Archaeology.get_all_ruins()) == 2
    end

    test "boş liste döner (harabe yoksa)" do
      assert Archaeology.get_all_ruins() == []
    end
  end

  describe "get_ruin_at/1" do
    test "pozisyona göre harabe bulur" do
      Archaeology.create_ancient_ruin(:village, {15, 25}, 100)
      ruin = Archaeology.get_ruin_at({15, 25})
      assert ruin != nil
      assert ruin.type == :village
    end

    test "boş pozisyon nil döner" do
      assert Archaeology.get_ruin_at({99, 99}) == nil
    end
  end

  describe "convert_building_to_ruin/2" do
    test "binayı harabeye dönüştürür" do
      building = %{id: "b1", type: :market, position: {3, 3}, built_tick: 0}
      ruin = Archaeology.convert_building_to_ruin(building, 3000)
      assert ruin.position == {3, 3}
      assert ruin.original_building_id == "b1"
      assert ruin.decay_level == 0.1
    end
  end

  describe "generate_ancient_ruins/3" do
    test "dünya boyutuna göre harabe üretir" do
      ruins = Archaeology.generate_ancient_ruins(50, 50, 1000)
      assert length(ruins) >= 3
    end
  end

  describe "excavate/3" do
    test "başarılı kazı artefakt döner" do
      ruin = Archaeology.create_ancient_ruin(:temple, {1, 1}, 100)
      # Birkaç deneme — şansa bağlı
      results = for _ <- 1..20, do: Archaeology.excavate(ruin.id, "agent_1", 2000)
      ok_results = Enum.filter(results, fn {status, _} -> status == :ok end)
      # En az bir başarılı kazı olmalı (20 denemede)
      assert length(ok_results) > 0
    end

    test "olmayan harabe hata döner" do
      assert {:fail, _} = Archaeology.excavate("nonexistent", "agent_1", 100)
    end

    test "keşfedilen artefaktın sahibi kaydedilir" do
      ruin = Archaeology.create_ancient_ruin(:fortress, {2, 2}, 100)
      # Bol deneme
      results = for _ <- 1..30, do: Archaeology.excavate(ruin.id, "agent_x", 500)
      ok_results = Enum.filter(results, fn {status, _} -> status == :ok end)

      if length(ok_results) > 0 do
        {:ok, artifact} = hd(ok_results)
        assert artifact.discovered_by == "agent_x"
        assert artifact.discovered_tick == 500
      end
    end
  end

  describe "add_to_museum/1" do
    test "keşfedilmiş artefaktı müzeye ekler" do
      ruin = Archaeology.create_ancient_ruin(:monument, {5, 5}, 100)
      # Kazı yap
      results = for _ <- 1..30, do: Archaeology.excavate(ruin.id, "digger", 200)
      ok_results = Enum.filter(results, fn {s, _} -> s == :ok end)

      if length(ok_results) > 0 do
        {:ok, art} = hd(ok_results)
        assert Archaeology.add_to_museum(art.id) == :ok
        assert length(Archaeology.get_museum_artifacts()) > 0
      end
    end

    test "keşfedilmemiş artefakt müzeye eklenemez" do
      assert Archaeology.add_to_museum("nonexistent") == :error
    end
  end

  describe "check_building_decay/2" do
    test "sahipsiz eski binalar harabeye dönüşür" do
      buildings = [
        %{id: "b1", type: :hut, position: {1, 1}, owner_id: nil, built_tick: 0},
        %{id: "b2", type: :farm, position: {2, 2}, owner_id: "agent_1", built_tick: 0}
      ]

      ruins = Archaeology.check_building_decay(buildings, 3000)
      assert length(ruins) == 1
      assert hd(ruins).original_building_id == "b1"
    end

    test "yeni binalar dönüştürülmez" do
      buildings = [%{id: "b1", type: :hut, position: {1, 1}, owner_id: nil, built_tick: 2900}]
      assert Archaeology.check_building_decay(buildings, 3000) == []
    end
  end

  describe "advance_decay/1" do
    test "harabe bozulması ilerler" do
      ruin = Archaeology.create_ancient_ruin(:village, {1, 1}, 100)
      initial_decay = ruin.decay_level
      Archaeology.advance_decay(200)
      updated = Archaeology.get_ruin(ruin.id)
      assert updated.decay_level > initial_decay
    end
  end

  describe "mood_effect/1" do
    test "haunted harabe negatif etki verir" do
      ruin = %{type: :temple, haunted: true}
      assert Archaeology.mood_effect(ruin) < 0
    end

    test "normal harabe pozitif etki verir" do
      ruin = %{type: :temple, haunted: false}
      assert Archaeology.mood_effect(ruin) > 0
    end
  end

  describe "to_render_data/1 ve all_render_data/0" do
    test "render data doğru formatta" do
      ruin = Archaeology.create_ancient_ruin(:monument, {7, 7}, 100)
      data = Archaeology.to_render_data(ruin)
      assert data.type == :monument
      assert data.emoji == "🗿"
      assert is_float(data.decay_level)
      assert is_float(data.culture_bonus)
    end
  end

  describe "stats/0" do
    test "istatistikler doğru hesaplanır" do
      Archaeology.create_ancient_ruin(:temple, {1, 1}, 100)
      Archaeology.create_ancient_ruin(:fortress, {2, 2}, 100)
      stats = Archaeology.stats()
      assert stats.total_ruins == 2
      assert stats.total_artifacts > 0
      assert stats.discovered_ruins == 0
    end
  end

  describe "museum_culture_bonus/0" do
    test "müze boşken bonus 0" do
      assert Archaeology.museum_culture_bonus() == 0.0
    end
  end
end
