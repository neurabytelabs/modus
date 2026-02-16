defmodule Modus.Protocol.BridgeTest do
  use ExUnit.Case, async: true

  # Bridge requires running agents (GenServer), so we test the components it uses
  # IntentParser is tested separately; here we verify integration logic patterns

  alias Modus.Protocol.IntentParser

  test "intent parser feeds bridge correctly for location" do
    assert {:query, :location} = IntentParser.parse("Neredesin?")
  end

  test "intent parser feeds bridge correctly for status" do
    assert {:query, :status} = IntentParser.parse("Nasılsın?")
  end

  test "intent parser feeds bridge correctly for move" do
    assert {:command, :move, :north} = IntentParser.parse("kuzeye git")
  end

  test "intent parser feeds bridge correctly for chat" do
    assert {:chat, "selam dostum"} = IntentParser.parse("selam dostum")
  end
end
