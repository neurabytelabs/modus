defmodule Modus.Mind.ContextBuilderTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.ContextBuilder

  test "summarize_memories compresses text" do
    input = "Line one with lots of   extra   spaces\nLine two\nLine three\nLine four\nLine five\nLine six should be dropped"
    result = ContextBuilder.summarize_memories(input)
    assert is_binary(result)
    refute String.contains?(result, "Line six")
    refute String.contains?(result, "   ")
  end

  test "compress_text removes extra whitespace" do
    input = "Hello   world\n\n\nFoo   bar"
    result = ContextBuilder.compress_text(input)
    assert result == "Hello world\nFoo bar"
  end
end
