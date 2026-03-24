defmodule Joyconf.RateLimiter do
  use GenServer

  @cooldown_ms 5_000
  @table :rate_limiter

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  def allow?(session_id) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, session_id) do
      [{^session_id, last_at}] when now - last_at < @cooldown_ms ->
        false

      _ ->
        :ets.insert(@table, {session_id, now})
        true
    end
  end
end
