defmodule Modus.Protocol.IntentParserTest do
  use ExUnit.Case, async: true

  alias Modus.Protocol.IntentParser

  test "parse simple move" do
    assert {:command, :move, :north} = IntentParser.parse("kuzeye git")
  end

  test "parse stop" do
    assert {:command, :stop} = IntentParser.parse("dur")
  end

  test "parse location query" do
    assert {:query, :location} = IntentParser.parse("neredesin")
  end

  test "parse status query" do
    assert {:query, :status} = IntentParser.parse("nasılsın")
  end

  test "parse multi-step command" do
    result = IntentParser.parse("kuzeye git ve dur")
    assert {:multi, steps} = result
    assert length(steps) >= 2
  end

  test "parse chat fallback" do
    assert {:chat, _} = IntentParser.parse("bugün hava güzel")
  end
end
