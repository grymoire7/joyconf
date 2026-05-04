defmodule Speechwave.RateLimiter do
  @moduledoc false
  # GenServer that throttles emoji reactions per session using an ETS table.
  # ETS (Erlang Term Storage) is an in-memory key/value store built into the
  # BEAM — fast enough to check on every tap without hitting the database.
  # The table is created with :public so allow?/1 can be called directly from
  # any process without going through the GenServer's message queue.
  use GenServer

  @cooldown_ms 3_000
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
