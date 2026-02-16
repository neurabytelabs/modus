defmodule Modus.Repo.Migrations.CreateUniverses do
  use Ecto.Migration

  def change do
    create table(:universes) do
      add :name, :string, null: false
      add :grid_size_x, :integer, default: 50
      add :grid_size_y, :integer, default: 50
      add :template, :string, default: "village"
      add :status, :string, default: "paused"
      add :config, :text
      add :total_ticks, :integer, default: 0

      timestamps()
    end

    create table(:agents) do
      add :universe_id, references(:universes, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position_x, :integer
      add :position_y, :integer
      add :occupation, :string, default: "explorer"
      add :personality, :text
      add :needs, :text
      add :conatus_score, :float, default: 5.0
      add :alive, :boolean, default: true
      add :age, :integer, default: 0

      timestamps()
    end

    create index(:agents, [:universe_id])

    create table(:events) do
      add :universe_id, references(:universes, on_delete: :delete_all), null: false
      add :agent_id, references(:agents, on_delete: :nilify_all)
      add :tick, :integer, null: false
      add :event_type, :string, null: false
      add :data, :text

      timestamps(updated_at: false)
    end

    create index(:events, [:universe_id, :tick])
    create index(:events, [:agent_id])
  end
end
