defmodule ModusWeb.DemoLiveTest do
  use ExUnit.Case, async: true

  @moduledoc "Tests for Demo/Watch mode (IT-06)."

  # Test 1: DemoLive module exists and compiles
  test "demo_live module exists" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "defmodule ModusWeb.DemoLive"
    assert content =~ "DEMO MODE"
    assert content =~ "Read-only"
  end

  # Test 2: Route is defined in router
  test "router has /demo route" do
    {:ok, content} = File.read("lib/modus_web/router.ex")
    assert content =~ "live(\"/demo\", DemoLive, :index)"
  end

  # Test 3: No God Mode controls in demo
  test "demo has no god mode or chat input" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    refute content =~ "toggle_god_mode"
    refute content =~ "send_chat"
    refute content =~ "inject_event"
    refute content =~ "divine_command"
  end

  # Test 4: Demo shows metrics (population, conatus, season)
  test "demo shows key metrics" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "POP"
    assert content =~ "CONATUS"
    assert content =~ "TICK"
    assert content =~ "season_emoji"
    assert content =~ "weather_emoji"
  end

  # Test 5: Demo has "no simulation" fallback
  test "demo shows no simulation message when world not running" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "No simulation running"
    assert content =~ "world_running"
  end

  # Test 6: Demo subscribes to PubSub topics
  test "demo subscribes to events, prayers, agent_chats" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "PubSub.subscribe(Modus.PubSub, \"prayers\")"
    assert content =~ "PubSub.subscribe(Modus.PubSub, \"agent_chats\")"
    assert content =~ "PubSub.subscribe(Modus.PubSub, \"world_events\")"
    assert content =~ "EventLog.subscribe()"
  end

  # Test 7: Demo has chat feed, prayer feed, event feed
  test "demo has all three feed streams" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "chat_feed"
    assert content =~ "prayer_feed"
    assert content =~ "event_feed"
    assert content =~ "Agent Chats"
    assert content =~ "Prayers"
    assert content =~ "Events"
  end

  # Test 8: Demo has banner indicator
  test "demo has demo banner" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "DEMO MODE"
    assert content =~ "Read-only observation"
  end

  # Test 9: No auth required — no session checks
  test "demo has no auth checks" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    refute content =~ "current_user"
    refute content =~ "require_authenticated"
    refute content =~ "redirect"
  end

  # Test 10: Demo handles tick_update event
  test "demo handles tick_update" do
    {:ok, content} = File.read("lib/modus_web/live/demo_live.ex")
    assert content =~ "handle_event" and content =~ "tick_update"
  end
end
