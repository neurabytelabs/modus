defmodule Modus.UI.SettingsTest do
  use ExUnit.Case, async: false

  alias Modus.UI.Settings

  setup do
    Settings.init()
    Settings.reset()
    :ok
  end

  test "defaults are set correctly" do
    assert Settings.get(:language) == "TR"
    assert Settings.get(:theme) == "dark"
    assert Settings.get(:provider) == "ollama"
    assert Settings.get(:show_names) == true
  end

  test "set and get work" do
    Settings.set(:language, "EN")
    assert Settings.get(:language) == "EN"
  end

  test "get with default returns default for unknown keys" do
    assert Settings.get(:nonexistent, "fallback") == "fallback"
  end

  test "category returns keys for that category" do
    general = Settings.category(:general)
    assert Map.has_key?(general, :language)
    assert Map.has_key?(general, :theme)
    refute Map.has_key?(general, :provider)
  end

  test "all returns complete settings map" do
    all = Settings.all()
    assert Map.has_key?(all, :language)
    assert Map.has_key?(all, :provider)
    assert Map.has_key?(all, :keyboard_shortcuts)
  end

  test "reset restores defaults" do
    Settings.set(:theme, "light")
    Settings.reset()
    assert Settings.get(:theme) == "dark"
  end
end
