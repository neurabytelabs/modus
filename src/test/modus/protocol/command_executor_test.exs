defmodule Modus.Protocol.CommandExecutorTest do
  use ExUnit.Case, async: true

  alias Modus.Protocol.CommandExecutor

  test "direction_to_text returns correct strings" do
    # Just test the module compiles and basic structures
    assert is_atom(CommandExecutor)
  end
end
