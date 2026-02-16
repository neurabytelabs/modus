defmodule Modus.Mind.Cerebro.SpatialMemory do
  @moduledoc "Spatial memory biases agent movement toward joy locations and away from fear"

  alias Modus.Mind.AffectMemory

  @joy_bias_chance 0.4
  @fear_repulsion_radius 5
  @joy_pull_weight 0.3

  @doc "Bias explore target based on affect memories."
  def bias_explore_target(agent_id, current_pos, default_target) do
    # Check fear repulsion first
    fear_memories = AffectMemory.recall(agent_id, affect: :fear, min_salience: 0.5, limit: 3)

    case check_fear_repulsion(current_pos, fear_memories, default_target) do
      {:repel, new_target} -> new_target
      :ok ->
        # Check joy attraction
        joy_memories = AffectMemory.recall(agent_id, affect: :joy, min_salience: 0.3, limit: 5)

        if joy_memories != [] and :rand.uniform() < @joy_bias_chance do
          pick_joy_target(current_pos, joy_memories, default_target)
        else
          default_target
        end
    end
  end

  defp check_fear_repulsion(current_pos, fear_memories, default_target) do
    {cx, cy} = current_pos

    nearby_fear = Enum.find(fear_memories, fn m ->
      {fx, fy} = m.position
      abs(fx - cx) <= @fear_repulsion_radius and abs(fy - cy) <= @fear_repulsion_radius
    end)

    if nearby_fear do
      {fx, fy} = nearby_fear.position
      # Move away from fear
      dx = cx - fx
      dy = cy - fy
      # Normalize and push away
      {tx, ty} = default_target
      new_tx = tx + sign(dx) * 3
      new_ty = ty + sign(dy) * 3
      {:repel, {new_tx, new_ty}}
    else
      :ok
    end
  end

  defp pick_joy_target(_current_pos, joy_memories, default_target) do
    # Weighted random selection by salience
    total = Enum.reduce(joy_memories, 0.0, & &2 + &1.salience)
    roll = :rand.uniform() * total

    selected = pick_weighted(joy_memories, roll, 0.0)
    {jx, jy} = selected.position
    {dx, dy} = default_target

    # Blend: 30% joy location, 70% default
    new_x = round(dx * (1 - @joy_pull_weight) + jx * @joy_pull_weight)
    new_y = round(dy * (1 - @joy_pull_weight) + jy * @joy_pull_weight)
    {new_x, new_y}
  end

  defp pick_weighted([m], _roll, _acc), do: m
  defp pick_weighted([m | rest], roll, acc) do
    new_acc = acc + m.salience
    if roll <= new_acc, do: m, else: pick_weighted(rest, roll, new_acc)
  end

  defp sign(0), do: 0
  defp sign(n) when n > 0, do: 1
  defp sign(_), do: -1
end
