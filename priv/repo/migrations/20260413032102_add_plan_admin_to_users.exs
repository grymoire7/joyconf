defmodule Speechwave.Repo.Migrations.AddPlanAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :plan, :string, null: false, default: "free"
      add :is_admin, :boolean, null: false, default: false
    end
  end
end
