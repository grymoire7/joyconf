defmodule Speechwave.Repo.Migrations.CreateTalkSessions do
  use Ecto.Migration

  def change do
    create table(:talk_sessions) do
      add :talk_id, references(:talks, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:talk_sessions, [:talk_id])
  end
end
