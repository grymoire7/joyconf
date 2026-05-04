defmodule Speechwave.DbBackup do
  @moduledoc false
  # GenServer that runs a SQLite backup on a schedule (5-minute initial delay,
  # then every hour). Uses SQLite's VACUUM INTO for a live, consistent snapshot,
  # then uploads the file to S3-compatible object storage via Req.
  # Registered under its own module name so `run_now/0` can be called from
  # IEx or a Mix task during development without waiting for the timer.
  use GenServer
  require Logger

  alias Ecto.Adapters.SQL

  @initial_delay :timer.minutes(5)
  @interval :timer.hours(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :backup, @initial_delay)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:backup, state) do
    run_backup()
    Process.send_after(self(), :backup, @interval)
    {:noreply, state}
  end

  def run_now, do: run_backup()

  defp run_backup do
    backup_path = "/tmp/speechwave_backup.db"

    Logger.info("[DbBackup] Starting backup")

    try do
      # VACUUM INTO creates a consistent, compacted snapshot while the DB is live
      SQL.query!(Speechwave.Repo, "VACUUM INTO '#{backup_path}'", [])
      upload(backup_path)
      Logger.info("[DbBackup] Backup uploaded successfully")
    rescue
      e -> Logger.error("[DbBackup] Backup failed: #{Exception.message(e)}")
    after
      File.rm(backup_path)
    end
  end

  defp upload(path) do
    endpoint = System.fetch_env!("STORAGE_URL")
    bucket = System.fetch_env!("STORAGE_BUCKET")
    access_key_id = System.fetch_env!("STORAGE_ACCESS_KEY_ID")
    secret_access_key = System.fetch_env!("STORAGE_SECRET_ACCESS_KEY")

    Req.put!("#{endpoint}/#{bucket}/backup/speechwave.db",
      body: File.read!(path),
      aws_sigv4: [
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        region: "auto",
        service: "s3"
      ]
    )
  end
end
