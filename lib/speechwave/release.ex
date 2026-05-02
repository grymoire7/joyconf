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

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Speechwave.Repo, fn _repo ->
        admin_email = System.get_env("ADMIN_EMAIL") || "admin@speechwave.live"
        admin_password = System.fetch_env!("ADMIN_SEED_PASSWORD")

        case Speechwave.Accounts.get_user_by_email(admin_email) do
          nil ->
            {:ok, user} = Speechwave.Accounts.register_user(%{email: admin_email, password: admin_password})
            Speechwave.Repo.update!(Ecto.Changeset.change(user, is_admin: true))
            IO.puts("Admin user created: #{admin_email}")

          existing ->
            IO.puts("Admin user already exists: #{existing.email}")
        end
      end)
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
