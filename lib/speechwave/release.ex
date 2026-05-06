defmodule Speechwave.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :speechwave

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()
    admin_email = System.get_env("ADMIN_EMAIL") || "admin@speechwave.live"

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Speechwave.Repo, fn _repo -> ensure_admin(admin_email) end)
  end

  defp ensure_admin(admin_email) do
    case Speechwave.Accounts.get_user_by_email(admin_email) do
      nil ->
        {:ok, user} = Speechwave.Accounts.register_user(%{email: admin_email})
        Speechwave.Repo.update!(Ecto.Changeset.change(user, is_admin: true))
        IO.puts("Admin user created: #{admin_email}")

      existing ->
        unless existing.is_admin do
          Speechwave.Repo.update!(Ecto.Changeset.change(existing, is_admin: true))
        end

        IO.puts("Admin user confirmed: #{existing.email}")
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
