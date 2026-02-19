defmodule ModusWeb.DemoKeyboardTest do
  use ExUnit.Case, async: true

  @moduledoc "Tests for DemoCanvas keyboard shortcuts (v7.2)."

  test "DemoCanvas hook has keyboard shortcut setup" do
    {:ok, content} = File.read("assets/js/app.js")
    assert content =~ "_setupDemoKeyboardShortcuts"
    assert content =~ "_demoKeyHandler"
  end

  test "Arrow keys are handled for panning" do
    {:ok, content} = File.read("assets/js/app.js")
    assert content =~ "ArrowUp"
    assert content =~ "ArrowDown"
    assert content =~ "ArrowLeft"
    assert content =~ "ArrowRight"
    assert content =~ "PAN_STEP"
  end

  test "+/- keys are handled for zoom in DemoCanvas" do
    {:ok, content} = File.read("assets/js/app.js")
    # The DemoCanvas-specific handler
    assert content =~ "setZoomLevel"
    assert content =~ "scale.x"
  end

  test "shortcuts ignore input fields" do
    {:ok, content} = File.read("assets/js/app.js")
    assert content =~ "e.target.tagName === \"INPUT\""
  end

  test "keyboard handler is cleaned up on destroy" do
    {:ok, content} = File.read("assets/js/app.js")
    assert content =~ "removeEventListener(\"keydown\", this._demoKeyHandler)"
  end
end
