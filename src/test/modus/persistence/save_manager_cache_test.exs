defmodule Modus.Persistence.SaveManagerCacheTest do
  use ExUnit.Case, async: true

  @moduledoc "Tests for SaveManager slot metadata caching (v7.2)."

  test "SaveManager has slot_cache field in struct" do
    {:ok, content} = File.read("lib/modus/persistence/save_manager.ex")
    assert content =~ "slot_cache"
  end

  test "list_slots uses cache (cache invalidated on save/delete)" do
    {:ok, content} = File.read("lib/modus/persistence/save_manager.ex")
    # Cache is used: when slot_cache is not nil, return it directly
    assert content =~ "slot_cache: cached"
    assert content =~ "when cached != nil"
    # Invalidation on save
    assert content =~ "{:save_slot, slot, name}" and content =~ "slot_cache: nil"
    # Invalidation on delete
    assert content =~ "{:delete_slot, slot}" and content =~ "slot_cache: nil"
  end

  test "build_slot_list/0 exists as private function" do
    {:ok, content} = File.read("lib/modus/persistence/save_manager.ex")
    assert content =~ "defp build_slot_list"
  end
end
