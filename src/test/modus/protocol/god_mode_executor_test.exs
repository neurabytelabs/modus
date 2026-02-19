defmodule Modus.Protocol.GodModeExecutorTest do
  use ExUnit.Case, async: false

  alias Modus.Protocol.{IntentParser, GodModeExecutor}

  # ── IntentParser God Mode Detection ─────────────────────────

  describe "IntentParser.parse/1 god-mode weather intents" do
    test "English: 'Send a storm'" do
      assert {:god_mode, :weather_event, %{event: :storm}} = IntentParser.parse("Send a storm")
    end

    test "Turkish: 'Fırtına gönder'" do
      assert {:god_mode, :weather_event, %{event: :storm}} = IntentParser.parse("fırtına gönder")
    end

    test "trigger rain" do
      assert {:god_mode, :weather_event, %{event: :rain}} = IntentParser.parse("send a rain")
    end

    test "trigger earthquake" do
      assert {:god_mode, :weather_event, %{event: :earthquake}} = IntentParser.parse("trigger an earthquake")
    end

    test "trigger flood with severity" do
      {:god_mode, :weather_event, params} = IntentParser.parse("send a massive flood")
      assert params.event == :flood
      assert params.severity == 3
    end

    test "Turkish: 'deprem yap'" do
      assert {:god_mode, :weather_event, %{event: :earthquake}} = IntentParser.parse("deprem yap")
    end

    test "trigger festival" do
      assert {:god_mode, :weather_event, %{event: :festival}} = IntentParser.parse("start a festival")
    end

    test "clear weather" do
      assert {:god_mode, :weather_event, %{event: :clear}} = IntentParser.parse("clear weather")
    end
  end

  describe "IntentParser.parse/1 god-mode spawn intents" do
    test "spawn 5 agents" do
      assert {:god_mode, :spawn_entity, %{count: 5}} = IntentParser.parse("spawn 5 agents")
    end

    test "spawn a single agent" do
      assert {:god_mode, :spawn_entity, %{count: 1}} = IntentParser.parse("spawn an agent")
    end

    test "Turkish: create agents" do
      assert {:god_mode, :spawn_entity, %{count: 3}} = IntentParser.parse("oluştur 3 ajan")
    end
  end

  describe "IntentParser.parse/1 god-mode terrain intents" do
    test "change terrain to desert" do
      assert {:god_mode, :terrain_modify, %{terrain: "desert"}} =
               IntentParser.parse("change terrain to desert")
    end

    test "change terrain to forest" do
      assert {:god_mode, :terrain_modify, %{terrain: "forest"}} =
               IntentParser.parse("set terrain to forest")
    end

    test "transform terrain into mountain" do
      assert {:god_mode, :terrain_modify, %{terrain: "mountain"}} =
               IntentParser.parse("transform terrain into mountain")
    end
  end

  describe "IntentParser.parse/1 god-mode config intents" do
    test "set time speed" do
      assert {:god_mode, :config_change, %{key: :time_speed, value: 2.5}} =
               IntentParser.parse("set time speed to 2.5")
    end

    test "change danger level" do
      assert {:god_mode, :config_change, %{key: :danger_level, value: :extreme}} =
               IntentParser.parse("set danger level to extreme")
    end
  end

  describe "IntentParser.parse/1 god-mode rule inject intents" do
    test "apply preset" do
      assert {:god_mode, :rule_inject, %{preset: "Harsh Survival"}} =
               IntentParser.parse("apply preset 'Harsh Survival'")
    end

    test "detect preset name directly" do
      assert {:god_mode, :rule_inject, %{preset: _}} =
               IntentParser.parse("peaceful paradise")
    end
  end

  describe "IntentParser.parse/1 non-god-mode still works" do
    test "regular chat falls through" do
      assert {:chat, _} = IntentParser.parse("hello world")
    end

    test "location query still works" do
      assert {:query, :location} = IntentParser.parse("where are you")
    end

    test "move command still works" do
      assert {:command, :move, :north} = IntentParser.parse("go north")
    end
  end

  # ── GodModeExecutor.execute/1 ───────────────────────────────

  describe "GodModeExecutor.execute/1" do
    test "unknown action returns error" do
      assert {:error, _} = GodModeExecutor.execute({:god_mode, :unknown_action, %{}})
    end

    test "weather_event without event param returns error" do
      assert {:error, _} = GodModeExecutor.execute({:god_mode, :weather_event, %{}})
    end

    test "spawn_entity without count returns error" do
      assert {:error, _} = GodModeExecutor.execute({:god_mode, :spawn_entity, %{}})
    end

    test "terrain_modify without terrain returns error" do
      assert {:error, _} = GodModeExecutor.execute({:god_mode, :terrain_modify, %{}})
    end

    test "config_change without params returns error" do
      assert {:error, _} = GodModeExecutor.execute({:god_mode, :config_change, %{}})
    end

    test "rule_inject without preset or rules returns error" do
      assert {:error, _} = GodModeExecutor.execute({:god_mode, :rule_inject, %{}})
    end
  end
end
