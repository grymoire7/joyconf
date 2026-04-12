defmodule Speechwave.Repo do
  use Ecto.Repo,
    otp_app: :speechwave,
    adapter: Ecto.Adapters.Postgres
end
