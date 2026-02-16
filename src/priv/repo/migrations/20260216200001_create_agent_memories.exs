defmodule Modus.Repo.Migrations.CreateAgentMemories do
  use Ecto.Migration

  def change do
    create table(:agent_memories) do
      add :agent_id, :string, null: false
      add :agent_name, :string
      add :memory_type, :string, null: false
      add :content, :text, null: false
      add :importance, :float, default: 0.5
      add :tick, :integer, default: 0
      add :metadata_json, :text

      timestamps()
    end

    create index(:agent_memories, [:agent_id])
    create index(:agent_memories, [:memory_type])
    create index(:agent_memories, [:importance])
  end
end
