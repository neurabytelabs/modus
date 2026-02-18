defmodule Modus.Simulation.EventProbabilityTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.EventProbability

  describe "calculate/1" do
    test "returns probabilities for all event types" do
      probs = EventProbability.calculate(%{})
      assert length(probs) == map_size(EventProbability.base_probabilities())

      for {event, prob} <- probs do
        assert is_atom(event)
        assert is_float(prob) or is_number(prob)
        assert prob >= 0
        assert prob <= 0.5
      end
    end

    test "drought probability increases in summer" do
      summer = EventProbability.calculate(%{season: :summer})
      winter = EventProbability.calculate(%{season: :winter})

      summer_drought = Enum.find(summer, fn {e, _} -> e == :drought end) |> elem(1)
      winter_drought = Enum.find(winter, fn {e, _} -> e == :drought end) |> elem(1)

      assert summer_drought > winter_drought
    end

    test "festival probability increases with high happiness" do
      happy = EventProbability.calculate(%{avg_happiness: 0.9})
      sad = EventProbability.calculate(%{avg_happiness: 0.1})

      happy_fest = Enum.find(happy, fn {e, _} -> e == :festival end) |> elem(1)
      sad_fest = Enum.find(sad, fn {e, _} -> e == :festival end) |> elem(1)

      assert happy_fest > sad_fest
    end

    test "cooldown reduces all probabilities" do
      recent = EventProbability.calculate(%{ticks_since_last_event: 5})
      old = EventProbability.calculate(%{ticks_since_last_event: 200})

      recent_total = Enum.reduce(recent, 0, fn {_, p}, acc -> acc + p end)
      old_total = Enum.reduce(old, 0, fn {_, p}, acc -> acc + p end)

      assert old_total > recent_total
    end

    test "results are sorted by probability descending" do
      probs = EventProbability.calculate(%{})
      probabilities = Enum.map(probs, &elem(&1, 1))
      assert probabilities == Enum.sort(probabilities, :desc)
    end
  end

  describe "roll/1" do
    test "returns nil or {event, severity} tuple" do
      results = for _ <- 1..200, do: EventProbability.roll(%{ticks_since_last_event: 1000, population: 50})

      non_nil = Enum.reject(results, &is_nil/1)

      for {event, severity} <- non_nil do
        assert is_atom(event)
        assert severity in [1, 2, 3]
      end
    end
  end
end
