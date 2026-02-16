defmodule Modus.Repo.Migrations.CreateWorlds do
  use Ecto.Migration

  def change do
    create table(:worlds) do
      add :name, :string, null: false
      add :template, :string, default: "village"
      add :config_json, :text
      add :state_json, :text

      timestamps()
    end

    create index(:worlds, [:name])
  end
end
