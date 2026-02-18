defmodule Modus.Schema.AgentMemory do
  @moduledoc """
  AgentMemory schema — persistent long-term memories for agents.

  Memory types:
  - :death — agent witnessed or experienced death
  - :friendship — formed a meaningful relationship
  - :discovery — found something notable
  - :conversation — significant conversation
  - :conflict — experienced conflict
  - :emotional — high-affect emotional event
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_memories" do
    field(:agent_id, :string)
    field(:agent_name, :string)
    field(:memory_type, :string)
    field(:content, :string)
    field(:importance, :float, default: 0.5)
    field(:tick, :integer, default: 0)
    field(:metadata_json, :string)

    timestamps()
  end

  @valid_types ~w(death friendship discovery conversation conflict emotional)

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :agent_id,
      :agent_name,
      :memory_type,
      :content,
      :importance,
      :tick,
      :metadata_json
    ])
    |> validate_required([:agent_id, :memory_type, :content])
    |> validate_inclusion(:memory_type, @valid_types)
    |> validate_number(:importance, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
