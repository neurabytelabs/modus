defmodule Modus.Mind.EpisodicMemory.Memory do
  @moduledoc """
  Struct definitions for episodic memory types: event, social, spatial, emotional.
  """

  @enforce_keys [:id, :agent_id, :type, :tick, :description, :weight]
  defstruct [
    :id, :agent_id, :type, :tick, :description, :weight,
    :position, :related_agent, :emotion, :intensity, :metadata
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    agent_id: String.t(),
    type: :event | :social | :spatial | :emotional,
    tick: non_neg_integer(),
    description: String.t(),
    weight: float(),
    position: {number(), number()} | nil,
    related_agent: String.t() | nil,
    emotion: atom() | nil,
    intensity: float() | nil,
    metadata: map() | nil
  }

  def new(agent_id, type, data, opts \\ []) do
    %__MODULE__{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(),
      agent_id: agent_id,
      type: type,
      tick: Keyword.get(opts, :tick, 0),
      description: Map.get(data, :description, ""),
      weight: ensure_float(Map.get(data, :weight, 1.0)),
      position: Map.get(data, :position),
      related_agent: Map.get(data, :related_agent),
      emotion: Map.get(data, :emotion),
      intensity: safe_float(Map.get(data, :intensity)),
      metadata: Map.get(data, :metadata)
    }
  end

  def to_context_string(%__MODULE__{} = m) do
    base = "[#{m.type}] Tick #{m.tick}: #{m.description}"
    parts = [base]
    parts = if m.emotion, do: parts ++ [" (felt #{m.emotion})"], else: parts
    parts = if m.related_agent, do: parts ++ [" with #{m.related_agent}"], else: parts
    parts = if m.position, do: parts ++ [" at #{inspect(m.position)}"], else: parts
    Enum.join(parts)
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  defp safe_float(nil), do: nil
  defp safe_float(val), do: ensure_float(val)
end
