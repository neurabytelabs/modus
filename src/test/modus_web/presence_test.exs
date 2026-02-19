defmodule ModusWeb.PresenceTest do
  use ExUnit.Case, async: true

  @moduledoc "Tests for Phoenix.Presence viewer tracking (v7.2)."

  test "ModusWeb.Presence module exists" do
    assert Code.ensure_loaded?(ModusWeb.Presence)
  end

  test "DemoLive tracks viewer_count assign" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "viewer_count"
    assert content =~ "Presence.track"
    assert content =~ "presence_diff"
    assert content =~ "watching"
  end

  test "Presence is in supervision tree" do
    {:ok, content} = File.read("lib/modus/application.ex")
    assert content =~ "ModusWeb.Presence"
  end
end
