defmodule Modus.UI.SmartToastTest do
  use ExUnit.Case, async: false

  alias Modus.UI.SmartToast

  setup do
    SmartToast.init()
    SmartToast.reset()
    :ok
  end

  describe "show/3" do
    test "creates a toast with correct level" do
      toast = SmartToast.show(:info, "Hello")
      assert toast.level == :info
      assert toast.message == "Hello"
      assert toast.duration == 3000
    end

    test "critical has nil duration (persistent)" do
      toast = SmartToast.show(:critical, "Alert!")
      assert toast.duration == nil
    end
  end

  describe "queue/0" do
    test "returns max 3 visible" do
      for i <- 1..5, do: SmartToast.show(:info, "Toast #{i}")
      assert length(SmartToast.queue()) == 3
    end
  end

  describe "dismiss/1" do
    test "removes toast by id" do
      toast = SmartToast.show(:info, "Bye")
      SmartToast.dismiss(toast.id)
      assert SmartToast.queue() == []
    end
  end
end
