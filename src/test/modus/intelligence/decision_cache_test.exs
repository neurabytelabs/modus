defmodule Modus.Intelligence.DecisionCacheTest do
  use ExUnit.Case, async: true

  alias Modus.Intelligence.DecisionCache

  describe "get/put" do
    test "returns nil for missing key" do
      assert DecisionCache.get("nonexistent_#{System.unique_integer()}") == nil
    end

    test "stores and retrieves a decision" do
      id = "test_agent_#{System.unique_integer()}"
      DecisionCache.put(id, {:explore, %{reason: "curious"}})
      assert {:explore, %{reason: "curious"}} = DecisionCache.get(id)
    end

    test "clear removes all entries" do
      id = "test_clear_#{System.unique_integer()}"
      DecisionCache.put(id, {:idle, %{}})
      DecisionCache.clear()
      assert DecisionCache.get(id) == nil
    end
  end
end
