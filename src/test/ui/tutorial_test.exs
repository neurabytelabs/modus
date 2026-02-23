defmodule Modus.UI.TutorialTest do
  use ExUnit.Case, async: false

  alias Modus.UI.Tutorial

  setup do
    Tutorial.init()
    Tutorial.reset()
    :ok
  end

  test "init creates table and defaults to not completed" do
    refute Tutorial.completed?()
    assert Tutorial.step_index() == 0
  end

  test "start sets first step" do
    Tutorial.start()
    step = Tutorial.current_step()
    assert step.id == :select_world
    assert step.title == "Dünya Seç"
  end

  test "advance progresses through steps" do
    Tutorial.start()
    assert :ok = Tutorial.advance()
    assert Tutorial.current_step().id == :inspect_agent
    assert :ok = Tutorial.advance()
    assert Tutorial.current_step().id == :open_chat
    assert :ok = Tutorial.advance()
    assert Tutorial.current_step().id == :try_god_mode
    assert :ok = Tutorial.advance()
    assert :completed = Tutorial.advance()
    assert Tutorial.completed?()
  end

  test "skip marks as completed immediately" do
    Tutorial.start()
    Tutorial.skip()
    assert Tutorial.completed?()
    assert Tutorial.current_step() == nil
  end

  test "state returns full state map" do
    Tutorial.start()
    state = Tutorial.state()
    assert state.step == 1
    assert state.total == 5
    assert state.title == "Dünya Seç"
    refute state.completed
  end

  test "reset returns to initial state" do
    Tutorial.start()
    Tutorial.advance()
    Tutorial.reset()
    assert Tutorial.step_index() == 0
    refute Tutorial.completed?()
  end
end
