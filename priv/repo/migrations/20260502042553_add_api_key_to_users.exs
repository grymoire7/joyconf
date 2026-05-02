defmodule Speechwave.Repo.Migrations.AddApiKeyToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :api_key, :string
    end

    create unique_index(:users, [:api_key])

    # Backfill existing users with a unique api_key
    flush()
    execute("UPDATE users SET api_key = lower(hex(randomblob(32))) WHERE api_key IS NULL")
  end

  def down do
    drop_if_exists unique_index(:users, [:api_key])

    alter table(:users) do
      remove :api_key
    end
  end
end
