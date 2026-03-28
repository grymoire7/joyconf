defmodule Joyconf.Repo.Migrations.CreateReactions do
  use Ecto.Migration

  def change do
    create table(:reactions) do
      add :talk_session_id, references(:talk_sessions, on_delete: :delete_all), null: false
      add :emoji, :string, null: false
      add :slide_number, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:reactions, [:talk_session_id])
  end
end
