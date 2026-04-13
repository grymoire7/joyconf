defmodule SpeechwaveWeb.Presence do
  use Phoenix.Presence,
    otp_app: :speechwave,
    pubsub_server: Speechwave.PubSub
end
