defmodule Joyconf.Repo do
  use Ecto.Repo,
    otp_app: :joyconf,
    adapter: Ecto.Adapters.Postgres
end
