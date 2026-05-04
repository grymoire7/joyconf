defmodule SpeechwaveWeb.Presence do
  @moduledoc false
  use Phoenix.Presence,
    otp_app: :speechwave,
    pubsub_server: Speechwave.PubSub
end
