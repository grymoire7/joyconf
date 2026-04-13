defmodule Speechwave.Repo.Migrations.AddUserIdToTalks do
  use Ecto.Migration

  def change do
    execute("DELETE FROM talk_sessions")
    execute("DELETE FROM talks")

    alter table(:talks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create index(:talks, [:user_id])
  end
end
