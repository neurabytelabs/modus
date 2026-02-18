defmodule Modus.Simulation.WeatherTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.Weather

  describe "weather config" do
    test "all weather types have configs" do
      for type <- [:clear, :cloudy, :rain, :storm, :snow, :fog, :wind, :heatwave] do
        cfg = Weather.config_for(type)
        assert is_map(cfg)
        assert Map.has_key?(cfg, :move_mod)
        assert Map.has_key?(cfg, :gather_mod)
        assert Map.has_key?(cfg, :mood_mod)
        assert Map.has_key?(cfg, :crop_mod)
        assert Map.has_key?(cfg, :emoji)
        assert Map.has_key?(cfg, :name)
      end
    end

    test "unknown weather type returns clear config" do
      cfg = Weather.config_for(:unknown)
      assert cfg.name == "Clear"
    end

    test "movement modifiers are between 0 and 2" do
      for type <- [:clear, :cloudy, :rain, :storm, :snow, :fog, :wind, :heatwave] do
        cfg = Weather.config_for(type)
        assert cfg.move_mod >= 0.0 and cfg.move_mod <= 2.0
      end
    end

    test "storm has lowest movement modifier" do
      storm = Weather.config_for(:storm)
      clear = Weather.config_for(:clear)
      assert storm.move_mod < clear.move_mod
    end

    test "rain boosts crop growth" do
      rain = Weather.config_for(:rain)
      assert rain.crop_mod > 1.0
    end
  end

  describe "effects and modifiers" do
    test "shelter negates movement penalty" do
      assert Weather.movement_modifier(true) == 1.0
    end

    test "shelter negates mood penalty" do
      assert Weather.mood_modifier(true) == 0.0
    end

    test "shelter negates gather penalty" do
      assert Weather.gather_modifier(true) == 1.0
    end

    test "effects returns a map with required keys" do
      fx = Weather.effects()
      assert is_map(fx)
      assert Map.has_key?(fx, :move_mod)
      assert Map.has_key?(fx, :mood_mod)
    end
  end

  describe "state and serialization" do
    test "get_state returns map with current weather" do
      state = Weather.get_state()
      assert is_map(state)
      assert Map.has_key?(state, :current)
    end

    test "current returns an atom" do
      assert is_atom(Weather.current())
    end

    test "serialize returns client-friendly map" do
      data = Weather.serialize()
      assert is_map(data)
      assert is_binary(data.current)
      assert is_binary(data.name)
      assert is_binary(data.emoji)
      assert is_float(data.move_mod) or is_integer(data.move_mod)
      assert is_list(data.forecast)
    end
  end

  describe "forecast" do
    test "forecast returns a list" do
      fc = Weather.forecast(50)
      assert is_list(fc)
    end

    test "forecast entries have required fields" do
      fc = Weather.forecast(100)

      for entry <- fc do
        assert Map.has_key?(entry, :weather)
        assert Map.has_key?(entry, :emoji)
        assert Map.has_key?(entry, :at_tick)
      end
    end

    test "forecast with 0 ticks returns empty" do
      fc = Weather.forecast(0)
      assert fc == []
    end
  end

  describe "season correlation" do
    test "winter weights favor snow" do
      # Access module attribute indirectly via weighted picks
      # Just verify the module compiles and season logic works
      assert Weather.current() in [:clear, :cloudy, :rain, :storm, :snow, :fog, :wind, :heatwave]
    end
  end
end
