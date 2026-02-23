defmodule Modus.UI.NotificationCenterTest do
  use ExUnit.Case, async: false

  alias Modus.UI.NotificationCenter

  setup do
    NotificationCenter.init()
    NotificationCenter.clear()
    :ok
  end

  describe "add/3 and list/1" do
    test "adds and lists notifications" do
      NotificationCenter.add(:world, :info, "Test message")
      assert length(NotificationCenter.list(:all)) == 1
    end

    test "filters by category" do
      NotificationCenter.add(:world, :info, "World msg")
      NotificationCenter.add(:agent, :info, "Agent msg")
      assert length(NotificationCenter.list(:world)) == 1
      assert length(NotificationCenter.list(:agent)) == 1
    end
  end

  describe "unread_count/0" do
    test "counts unread" do
      NotificationCenter.add(:world, :info, "Msg 1")
      NotificationCenter.add(:world, :info, "Msg 2")
      assert NotificationCenter.unread_count() == 2
    end
  end

  describe "mark_all_read/0" do
    test "marks all as read" do
      NotificationCenter.add(:world, :info, "Msg")
      NotificationCenter.mark_all_read()
      assert NotificationCenter.unread_count() == 0
    end
  end

  describe "detect_milestone/1" do
    test "detects birth milestone" do
      NotificationCenter.detect_milestone(%{type: :birth, data: %{name: "Ada"}})
      [n | _] = NotificationCenter.list(:all)
      assert n.message =~ "Ada"
      assert n.message =~ "👶"
    end

    test "detects death milestone" do
      NotificationCenter.detect_milestone(%{type: :death, data: %{name: "Bob"}})
      [n | _] = NotificationCenter.list(:all)
      assert n.message =~ "💀"
    end
  end
end
