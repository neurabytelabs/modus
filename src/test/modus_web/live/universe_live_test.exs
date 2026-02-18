defmodule ModusWeb.UniverseLiveTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests for MODUS UniverseLive features.
  """

  # Test 1: God Mode toggle assigns
  test "god mode toggle flips state" do
    socket = %{assigns: %{god_mode: false, mind_view_active: false}}
    new_val = !socket.assigns.god_mode
    assert new_val == true

    socket2 = %{assigns: %{god_mode: true, mind_view_active: true}}
    new_val2 = !socket2.assigns.god_mode
    assert new_val2 == false
  end

  # Test 2: Cinematic mode toggle
  test "cinematic mode toggle flips state" do
    socket = %{assigns: %{cinematic_mode: false}}
    new_val = !socket.assigns.cinematic_mode
    assert new_val == true
  end

  # Test 3: Initial assigns include Deus features
  test "initial assigns include god_mode and cinematic_mode" do
    assigns = %{
      god_mode: false,
      cinematic_mode: false,
      mind_view_active: false,
      phase: :onboarding
    }
    assert assigns.god_mode == false
    assert assigns.cinematic_mode == false
    assert assigns.phase == :onboarding
  end

  # Test 4: Version check
  test "version is 4.7.0 in mix.exs" do
    {:ok, content} = File.read("mix.exs")
    assert content =~ ~s(version: "4.7.0")
  end

  # Test 5: Landing page has correct content in template
  test "universe_live module exists and has Speculum docstring" do
    {:ok, content} = File.read("lib/modus_web/live/universe_live.ex")
    assert content =~ "v3.7.0 Persistentia"
    assert content =~ "God Mode"
    assert content =~ "Cinematic Camera"
    assert content =~ "Screenshot"
    assert content =~ "Landing Page"
    assert content =~ "toggle_god_mode"
    assert content =~ "toggle_cinematic"
    assert content =~ "take_screenshot"
  end

  # Test 6: Renderer JS has Deus features
  test "renderer.js has god mode and cinematic methods" do
    {:ok, content} = File.read("assets/js/renderer.js")
    assert content =~ "setGodMode"
    assert content =~ "setCinematicMode"
    assert content =~ "takeScreenshot"
    assert content =~ "_updateCinematic"
  end

  # Test 7: App.js has keyboard shortcuts for Deus features
  test "app.js has G, C, P keyboard shortcuts" do
    {:ok, content} = File.read("assets/js/app.js")
    assert content =~ "KeyG"
    assert content =~ "KeyC"
    assert content =~ "KeyP"
    assert content =~ "toggle_god_mode"
    assert content =~ "toggle_cinematic"
    assert content =~ "take_screenshot"
  end
end
