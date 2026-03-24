defmodule Joyconf.Repo.Migrations.CreateTalks do
  use Ecto.Migration

  def change do
    create table(:talks) do
      add :title, :string, null: false
      add :slug, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:talks, [:slug])
  end
end
