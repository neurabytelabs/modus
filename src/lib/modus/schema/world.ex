defmodule Modus.Schema.World do
  @moduledoc """
  World schema for SQLite persistence.
  Stores world config + full agent state as JSON.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "worlds" do
    field :name, :string
    field :template, :string, default: "village"
    field :config_json, :string
    field :state_json, :string

    timestamps()
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [:name, :template, :config_json, :state_json])
    |> validate_required([:name])
  end
end
