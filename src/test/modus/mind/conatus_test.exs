defmodule Modus.Mind.ConatusTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.Conatus

  describe "update_energy/3" do
    test "action_success increases energy" do
      {new_energy, delta, _reason} = Conatus.update_energy(0.5, :action_success, :neutral)
      assert delta > 0
      assert new_energy > 0.5
    end

    test "action_failure decreases energy" do
      {new_energy, delta, _reason} = Conatus.update_energy(0.5, :action_failure, :neutral)
      assert delta < 0
      assert new_energy < 0.5
    end

    test "joy amplifies gains" do
      {_, delta_neutral, _} = Conatus.update_energy(0.5, :action_success, :neutral)
      {_, delta_joy, _} = Conatus.update_energy(0.5, :action_success, :joy)
      assert delta_joy > delta_neutral
    end

    test "sadness amplifies losses" do
      {_, delta_neutral, _} = Conatus.update_energy(0.5, :action_failure, :neutral)
      {_, delta_sad, _} = Conatus.update_energy(0.5, :action_failure, :sadness)
      assert delta_sad < delta_neutral
    end

    test "fear reduces gains" do
      {_, delta_neutral, _} = Conatus.update_energy(0.5, :action_success, :neutral)
      {_, delta_fear, _} = Conatus.update_energy(0.5, :action_success, :fear)
      assert delta_fear < delta_neutral
    end

    test "desire fights entropy" do
      {_, delta_neutral, _} = Conatus.update_energy(0.5, :natural_decay, :neutral)
      {_, delta_desire, _} = Conatus.update_energy(0.5, :natural_decay, :desire)
      assert abs(delta_desire) < abs(delta_neutral)
    end

    test "energy is clamped to [0, 1]" do
      {energy, _, _} = Conatus.update_energy(0.99, :action_success, :joy)
      assert energy <= 1.0

      {energy, _, _} = Conatus.update_energy(0.01, :hunger_critical, :fear)
      assert energy >= 0.0
    end
  end

  describe "alive?/1" do
    test "returns true for positive energy" do
      assert Conatus.alive?(0.5)
    end

    test "returns false for zero energy" do
      refute Conatus.alive?(0.0)
    end
  end

  describe "clamp/1" do
    test "clamps to range" do
      assert Conatus.clamp(1.5) == 1.0
      assert Conatus.clamp(-0.5) == 0.0
      assert Conatus.clamp(0.5) == 0.5
    end
  end
end
