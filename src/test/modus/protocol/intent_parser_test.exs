defmodule Modus.Protocol.IntentParserTest do
  use ExUnit.Case, async: true

  alias Modus.Protocol.IntentParser

  describe "parse/1" do
    test "location queries" do
      assert {:query, :location} = IntentParser.parse("Neredesin?")
      assert {:query, :location} = IntentParser.parse("Koordinatların ne?")
      assert {:query, :location} = IntentParser.parse("Where are you?")
    end

    test "status queries" do
      assert {:query, :status} = IntentParser.parse("Nasılsın?")
      assert {:query, :status} = IntentParser.parse("Durumun nasıl?")
      assert {:query, :status} = IntentParser.parse("How are you?")
    end

    test "relationship queries" do
      assert {:query, :relationships} = IntentParser.parse("Arkadaşların kim?")
      assert {:query, :relationships} = IntentParser.parse("Onu tanıyor musun?")
    end

    test "movement commands" do
      assert {:command, :move, :north} = IntentParser.parse("kuzeye git")
      assert {:command, :move, :south} = IntentParser.parse("güneye yürü")
      assert {:command, :move, :east} = IntentParser.parse("go east")
      assert {:command, :move, :west} = IntentParser.parse("move west")
    end

    test "stop commands" do
      assert {:command, :stop} = IntentParser.parse("dur")
      assert {:command, :stop} = IntentParser.parse("bekle")
      assert {:command, :stop} = IntentParser.parse("stop")
    end

    test "chat fallback" do
      assert {:chat, "merhaba"} = IntentParser.parse("merhaba")
      assert {:chat, "güzel hava var"} = IntentParser.parse("güzel hava var")
    end
  end
end
